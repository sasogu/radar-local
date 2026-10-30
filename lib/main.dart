import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'core/alert_engine.dart';
import 'core/proposal.dart';
import 'core/radar.dart';
import 'core/speed_limit.dart';
import 'proposal_screen.dart';
import 'services/data_store.dart';
import 'services/proposal_store.dart';
import 'services/settings.dart';
import 'services/update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(RadarApp(AppSettings(await SharedPreferences.getInstance())));
}

class RadarApp extends StatelessWidget {
  const RadarApp(this.settings, {super.key});
  final AppSettings settings;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Radar Local',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.amber,
      brightness: Brightness.dark,
    ),
    home: HomeScreen(settings),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen(this.settings, {super.key});
  final AppSettings settings;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _store = DataStore();
  final _tts = FlutterTts();
  Timer? _updateTimer;
  RadarDataset? _dataset;
  RadarDataset? _pendingDataset;
  AlertEngine? _engine;
  StreamSubscription<Position>? _positions;
  Position? _latestPosition;
  String _status = '';
  RadarAlert? _alert;
  DateTime? _alertAt;
  double? _speed;
  int? _speedLimit;
  bool _busy = false;
  bool _updating = false;
  bool _pendingUpdate = false;
  bool _driving = false;
  bool _offlineVoiceAvailable = true;
  bool get _va => widget.settings.language == 'va';
  String tr(String va, String es) => _va ? va : es;
  String sourceLabel(RadarDataset data) => data.source.contains('Tachwire/IGN')
      ? tr('Espanya · cobertura parcial', 'España · cobertura parcial')
      : data.source.contains('Ayuntamiento de Madrid') &&
            data.source.contains('Servei Català de Trànsit')
      ? tr(
          'Madrid + Catalunya · cobertura parcial',
          'Madrid + Cataluña · cobertura parcial',
        )
      : data.source;
  Color _speedColor(BuildContext context, SpeedZone? zone) => switch (zone) {
    null => Theme.of(context).colorScheme.onSurface,
    SpeedZone.within => Colors.green.shade400,
    SpeedZone.tolerance => Colors.orange.shade400,
    SpeedZone.fine => Colors.red.shade400,
  };

  @override
  void initState() {
    super.initState();
    _load();
    _updateTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _maybeAutomaticUpdate(),
    );
  }

  Future<void> _load() async {
    try {
      await _store.applyPending();
      final data = await _store.load();
      if (!mounted) return;
      setState(() {
        _dataset = data;
        _engine = AlertEngine(data);
      });
      _maybeAutomaticUpdate();
      if (widget.settings.autoStart) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_start());
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    }
  }

  void _maybeAutomaticUpdate() {
    final last = widget.settings.lastUpdateCheck;
    if (mounted &&
        !_updating &&
        widget.settings.automaticUpdates &&
        (last == null ||
            DateTime.now().difference(last) > const Duration(days: 7))) {
      unawaited(_download(automatic: true));
    }
  }

  Future<void> _start() async {
    if (_driving || _busy) return;
    setState(() => _busy = true);
    try {
      if (_dataset == null || _dataset!.radars.isEmpty) {
        throw StateError(
          tr(
            'Importa dades de radars abans de començar',
            'Importa datos de radares antes de empezar',
          ),
        );
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError(tr('Activa la ubicació', 'Activa la ubicación'));
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(
          tr('Cal autoritzar la ubicació', 'Debes autorizar la ubicación'),
        );
      }
      final language = _va ? 'ca-ES' : 'es-ES';
      _offlineVoiceAvailable = true;
      if (widget.settings.voice) {
        try {
          await _tts.setLanguage(language);
          if (Platform.isAndroid) {
            final voices = (await _tts.getVoices as List?) ?? const [];
            final offline = voices.whereType<Map>().where(
              (voice) =>
                  voice['locale'] == language &&
                  voice['network_required'] == '0' &&
                  !(voice['features'] as String? ?? '').contains(
                    'not_installed',
                  ),
            );
            _offlineVoiceAvailable = offline.isNotEmpty;
            if (_offlineVoiceAvailable) {
              final voice = offline.first;
              await _tts.setVoice({
                'name': voice['name'] as String,
                'locale': language,
              });
            }
          }
          if (_offlineVoiceAvailable) await _tts.setSpeechRate(0.48);
        } catch (_) {
          _offlineVoiceAvailable = false;
        }
      }
      final LocationSettings settings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 15,
              intervalDuration: const Duration(seconds: 3),
              forceLocationManager: true,
              foregroundNotificationConfig: ForegroundNotificationConfig(
                notificationTitle: 'Radar Local',
                notificationText: tr(
                  'Avisos de radars actius',
                  'Avisos de radares activos',
                ),
                notificationChannelName: 'Radar Local',
                setOngoing: true,
              ),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 15,
            );
      _positions = Geolocator.getPositionStream(locationSettings: settings)
          .listen(
            _onPosition,
            onError: (Object error) {
              if (mounted) setState(() => _status = '$error');
            },
          );
      setState(() {
        _driving = true;
        _speedLimit = null;
        _status = tr('Escoltant GPS', 'Escuchando GPS');
      });
      if (widget.settings.keepScreenOn) {
        unawaited(WakelockPlus.enable());
      } else {
        unawaited(WakelockPlus.disable());
      }
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onPosition(Position position) {
    if (!mounted || !_driving) return;
    _latestPosition = position;
    final fix = GpsFix(
      point: Point(position.latitude, position.longitude),
      time: position.timestamp,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      speedAccuracy: position.speedAccuracy,
      headingAccuracy: position.headingAccuracy,
    );
    final alert = _engine?.evaluate(fix);
    final limit = _engine?.limitAhead(fix)?.speedLimit;
    setState(() {
      _speed = position.speed * 3.6;
      _speedLimit = limit;
      _status = !_offlineVoiceAvailable
          ? tr(
              'Veu offline no disponible: només so',
              'Voz offline no disponible: solo sonido',
            )
          : fix.reliable
          ? tr('GPS actiu', 'GPS activo')
          : tr(
              'Esperant un senyal GPS fiable',
              'Esperando una señal GPS fiable',
            );
      if (alert != null) {
        _alert = alert;
        _alertAt = position.timestamp;
      } else if (_alertAt != null &&
          position.timestamp.difference(_alertAt!) >
              const Duration(seconds: 20)) {
        _alert = null;
        _alertAt = null;
      }
    });
    if (alert != null) unawaited(_announce(alert));
  }

  Future<void> _announce(RadarAlert alert) async {
    if (widget.settings.sound) await SystemSound.play(SystemSoundType.alert);
    if (widget.settings.voice && _offlineVoiceAvailable) {
      final kind = alert.radar.kind == RadarKind.section
          ? tr('radar de tram', 'radar de tramo')
          : alert.radar.kind == RadarKind.redLight
          ? tr('radar de semàfor', 'radar de semáforo')
          : alert.radar.kind == RadarKind.phone
          ? tr(
              'càmera de control de cinturó i mòbil',
              'cámara de control de cinturón y móvil',
            )
          : alert.radar.kind == RadarKind.lineStop
          ? tr(
              'càmera de línia contínua o stop',
              'cámara de línea continua o stop',
            )
          : tr('radar fix', 'radar fijo');
      final metres = (alert.distanceMeters / 50).round() * 50;
      await _tts.speak(tr('$kind a $metres metres', '$kind a $metres metros'));
    }
  }

  Future<bool> _stop() async {
    if (!mounted || _busy) return false;
    unawaited(WakelockPlus.disable());
    setState(() => _busy = true);
    RadarDataset? pendingInMemory;
    try {
      await _positions?.cancel();
      _positions = null;
      await _tts.stop();
      if (!mounted) return false;
      pendingInMemory = _pendingDataset;
      setState(() {
        _driving = false;
        _pendingUpdate = false;
        _pendingDataset = null;
        _speed = null;
        _speedLimit = null;
        _alert = null;
        _alertAt = null;
        _status = tr('Conducció finalitzada', 'Conducción finalizada');
      });
      final pending = await _store.applyPending() ?? pendingInMemory;
      if (mounted && pending != null) {
        setState(() {
          _dataset = pending;
          _engine = AlertEngine(pending);
          _pendingUpdate = false;
          _status = tr(
            '${pending.radars.length} radars actualitzats',
            '${pending.radars.length} radares actualizados',
          );
        });
        return true;
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _pendingDataset = pendingInMemory;
          _pendingUpdate = pendingInMemory != null;
          _status = '$error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  Future<void> _applyPendingNow() async {
    if (!_driving || !_pendingUpdate || _busy) return;
    final activated = await _stop();
    if (activated && mounted) await _start();
  }

  Future<void> _markProposal() async {
    final position = _latestPosition;
    if (position == null ||
        !position.accuracy.isFinite ||
        position.accuracy < 0 ||
        position.accuracy > 50 ||
        DateTime.now().difference(position.timestamp).inSeconds.abs() > 15) {
      if (mounted) {
        setState(
          () => _status = tr(
            'Espera un senyal GPS fiable per marcar el punt',
            'Espera una señal GPS fiable para marcar el punto',
          ),
        );
      }
      return;
    }
    try {
      final heading =
          position.headingAccuracy >= 0 &&
              position.headingAccuracy <= 45 &&
              position.heading >= 0 &&
              position.heading < 360
          ? position.heading
          : null;
      await ProposalStore(widget.settings.prefs).save(
        RadarProposal(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          point: Point(position.latitude, position.longitude),
          createdAt: DateTime.now().toUtc(),
          accuracy: position.accuracy,
          heading: heading,
        ),
      );
      if (mounted) {
        setState(
          () => _status = tr(
            'Punt guardat localment. Revisa’l en acabar.',
            'Punto guardado localmente. Revísalo al terminar.',
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    }
  }

  Future<void> _openProposals() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProposalScreen(
          store: ProposalStore(widget.settings.prefs),
          language: widget.settings.language,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<bool> _import() async {
    if (_updating || _driving) return false;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null) return false;
    final bytes = result.files.single.bytes;
    if (bytes == null) throw const FormatException('Cannot read file');
    if (bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('Dataset too large');
    }
    final data = await _store.replace(utf8.decode(bytes));
    if (!mounted) return false;
    setState(() {
      _dataset = data;
      _engine = AlertEngine(data);
      _pendingDataset = null;
      _pendingUpdate = false;
      _status = tr(
        '${data.radars.length} radars importats',
        '${data.radars.length} radares importados',
      );
    });
    return true;
  }

  Future<void> _download({bool automatic = false}) async {
    if (_updating || (!automatic && (_driving || _busy))) return;
    _updating = true;
    if (!automatic) setState(() => _busy = true);
    try {
      final sourceUrl = widget.settings.updateUrl;
      final fetched = await UpdateService(_store).fetch(sourceUrl);
      if (widget.settings.updateUrl != sourceUrl) return;
      final data = automatic
          ? await _store.stage(fetched.encode())
          : await _store.replace(fetched.encode());
      if (automatic && !_driving) await _store.applyPending();
      await widget.settings.markUpdateCheck();
      if (mounted) {
        if (_driving) {
          setState(() {
            _pendingDataset = data;
            _pendingUpdate = true;
          });
        } else {
          setState(() {
            _dataset = data;
            _engine = AlertEngine(data);
            _pendingDataset = null;
            _pendingUpdate = false;
            _status = tr(
              '${data.radars.length} radars actualitzats',
              '${data.radars.length} radares actualizados',
            );
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    } finally {
      _updating = false;
      if (!automatic && mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          widget.settings,
          onDownload: _download,
          onImport: _import,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _positions?.cancel();
    _tts.stop();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _dataset;
    final speed = _speed?.round();
    final limit = _speedLimit;
    final zone = speed == null || limit == null
        ? null
        : SpeedLimit.zone(speed, limit);
    final speedColor = _speedColor(context, zone);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar Local'),
        actions: [
          IconButton(
            onPressed: _driving ? null : _settings,
            tooltip: tr('Configuració', 'Configuración'),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _status.isEmpty
                              ? tr('Preparat', 'Preparado')
                              : _status,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            speed?.toString() ?? '—',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 84,
                              fontWeight: FontWeight.bold,
                              color: speedColor,
                            ),
                          ),
                          if (limit != null) ...[
                            const SizedBox(width: 16),
                            Semantics(
                              label: tr('Límit $limit', 'Límite $limit'),
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.red.shade700,
                                    width: 6,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '$limit',
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        'km/h',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (limit != null)
                        Text(
                          tr(
                            'Taronja: tolerància, no és una velocitat legal',
                            'Naranja: tolerancia, no es una velocidad legal',
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 28),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _alert == null
                              ? tr('Sense avisos', 'Sin avisos')
                              : '${_alert!.radar.kind == RadarKind.section
                                    ? tr('Radar de tram', 'Radar de tramo')
                                    : _alert!.radar.kind == RadarKind.redLight
                                    ? tr('Radar de semàfor', 'Radar de semáforo')
                                    : _alert!.radar.kind == RadarKind.phone || _alert!.radar.kind == RadarKind.lineStop
                                    ? tr('Càmera de control', 'Cámara de control')
                                    : tr('Radar', 'Radar')} · ${_alert!.distanceMeters.round()} m',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      const Spacer(),
                      if (_pendingUpdate)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _applyPendingNow,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(60),
                            ),
                            icon: const Icon(Icons.restart_alt),
                            label: Text(
                              tr(
                                'Aplica radars i reinicia avisos',
                                'Aplicar radares y reiniciar avisos',
                              ),
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : (_driving ? _stop : _start),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(72),
                              ),
                              icon: Icon(
                                _driving ? Icons.stop : Icons.play_arrow,
                              ),
                              label: Text(
                                _driving
                                    ? tr('Atura', 'Detener')
                                    : tr('Inicia', 'Iniciar'),
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _driving
                                  ? _markProposal
                                  : _openProposals,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(72),
                              ),
                              icon: const Icon(Icons.add_location_alt),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _driving
                                      ? tr(
                                          'Marca possible radar',
                                          'Marcar posible radar',
                                        )
                                      : tr(
                                          'Proposa un radar',
                                          'Proponer un radar',
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data == null
                            ? '…'
                            : tr(
                                '${data.radars.length} radars locals · ${sourceLabel(data)}',
                                '${data.radars.length} radares locales · ${sourceLabel(data)}',
                              ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(
    this.settings, {
    required this.onDownload,
    required this.onImport,
    super.key,
  });
  final AppSettings settings;
  final Future<void> Function() onDownload;
  final Future<bool> Function() onImport;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url = TextEditingController(
    text: widget.settings.updateUrl,
  );
  bool get va => widget.settings.language == 'va';
  String tr(String a, String b) => va ? a : b;
  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Configuració', 'Configuración'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<String>(
          initialValue: widget.settings.language,
          decoration: InputDecoration(labelText: tr('Idioma', 'Idioma')),
          items: const [
            DropdownMenuItem(value: 'va', child: Text('Valencià / català')),
            DropdownMenuItem(value: 'es', child: Text('Castellano')),
          ],
          onChanged: (v) async {
            if (v != null) {
              await widget.settings.setLanguage(v);
              setState(() {});
            }
          },
        ),
        SwitchListTile(
          title: Text(tr('Avisos de veu', 'Avisos de voz')),
          value: widget.settings.voice,
          onChanged: (v) async {
            await widget.settings.setVoice(v);
            setState(() {});
          },
        ),
        SwitchListTile(
          title: Text(tr('So d’avís', 'Sonido de aviso')),
          value: widget.settings.sound,
          onChanged: (v) async {
            await widget.settings.setSound(v);
            setState(() {});
          },
        ),
        SwitchListTile(
          title: Text(
            tr(
              'Inicia automàticament en obrir',
              'Iniciar automáticamente al abrir',
            ),
          ),
          subtitle: Text(
            tr(
              'Demana ubicació i comença a escoltar el GPS',
              'Pide ubicación y empieza a escuchar el GPS',
            ),
          ),
          value: widget.settings.autoStart,
          onChanged: (v) async {
            await widget.settings.setAutoStart(v);
            setState(() {});
          },
        ),
        SwitchListTile(
          title: Text(
            tr('Mantén la pantalla encesa', 'Mantén la pantalla encendida'),
          ),
          subtitle: Text(
            tr(
              'Només mentre la conducció està activa',
              'Solo mientras la conducción está activa',
            ),
          ),
          value: widget.settings.keepScreenOn,
          onChanged: (v) async {
            await widget.settings.setKeepScreenOn(v);
            setState(() {});
          },
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: tr('URL HTTPS de dades', 'URL HTTPS de datos'),
            helperText: tr(
              'Font de GitHub per defecte; pots escriure una altra URL',
              'Fuente de GitHub por defecto; puedes escribir otra URL',
            ),
          ),
          onChanged: (v) => widget.settings.setUpdateUrl(v),
        ),
        TextButton.icon(
          onPressed: () async {
            await widget.settings.setUpdateUrl('');
            _url.text = defaultRadarUpdateUrl;
            if (mounted) setState(() {});
          },
          icon: const Icon(Icons.restore),
          label: Text(
            tr(
              'Restaura la font per defecte',
              'Restaurar fuente predeterminada',
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            await widget.settings.setUpdateUrl(_url.text.trim());
            await widget.onDownload();
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.download),
          label: Text(tr('Actualitza ara', 'Actualizar ahora')),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              final imported = await widget.onImport();
              if (imported && context.mounted) Navigator.of(context).pop();
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      tr(
                        'No s’ha pogut importar el JSON: $error',
                        'No se pudo importar el JSON: $error',
                      ),
                    ),
                  ),
                );
              }
            }
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
          ),
          icon: const Icon(Icons.file_open),
          label: Text(tr('Importa dades JSON', 'Importar datos JSON')),
        ),
        SwitchListTile(
          title: Text(
            tr(
              'Actualització automàtica setmanal',
              'Actualización automática semanal',
            ),
          ),
          subtitle: Text(
            tr(
              'Es pot descarregar en ruta; s’activarà en acabar',
              'Puede descargarse en ruta; se activará al terminar',
            ),
          ),
          value: widget.settings.automaticUpdates,
          onChanged: (v) async {
            await widget.settings.setAutomaticUpdates(v);
            setState(() {});
          },
        ),
        const Divider(height: 32),
        Text(
          tr('Colors de velocitat', 'Colores de velocidad'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            'Verd: dins del límit. Taronja: marge de tolerància, no és una velocitat legal. Roig: multa probable.',
            'Verde: dentro del límite. Naranja: margen de tolerancia, no es una velocidad legal. Rojo: multa probable.',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            'Els límits de la DGT són estimats a partir d’OpenStreetMap; els de Catalunya i Madrid són oficials.',
            'Los límites de la DGT son estimados a partir de OpenStreetMap; los de Cataluña y Madrid son oficiales.',
          ),
        ),
        const SizedBox(height: 20),
        Text(
          tr(
            'El GPS es processa al dispositiu. No hi ha analítica ni servidor de l’app.',
            'El GPS se procesa en el dispositivo. No hay analítica ni servidor de la app.',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr(
            'Dades: DGT, IGN/CartoCiudad, Tachwire i OpenStreetMap (ODbL 1.0), incloses les càmeres de cinturó i mòbil; Ajuntament de Madrid (CC BY 4.0); Servei Català de Trànsit. Vegeu DATA_SOURCES.md.',
            'Datos: DGT, IGN/CartoCiudad, Tachwire y OpenStreetMap (ODbL 1.0), incluidas las cámaras de cinturón y móvil; Ayuntamiento de Madrid (CC BY 4.0); Servei Català de Trànsit. Consulta DATA_SOURCES.md.',
          ),
        ),
      ],
    ),
  );
}
