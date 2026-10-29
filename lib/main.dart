import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/alert_engine.dart';
import 'core/radar.dart';
import 'services/data_store.dart';
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
  RadarDataset? _dataset;
  AlertEngine? _engine;
  StreamSubscription<Position>? _positions;
  String _status = '';
  RadarAlert? _alert;
  DateTime? _alertAt;
  double? _speed;
  bool _busy = false;
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _store.load();
      if (!mounted) return;
      setState(() {
        _dataset = data;
        _engine = AlertEngine(data);
      });
      final last = widget.settings.lastUpdateCheck;
      if (widget.settings.automaticUpdates &&
          widget.settings.updateUrl.isNotEmpty &&
          (last == null ||
              DateTime.now().difference(last) > const Duration(days: 7))) {
        await _download();
      }
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
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
        _status = tr('Escoltant GPS', 'Escuchando GPS');
      });
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onPosition(Position position) {
    if (!mounted || !_driving) return;
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
    setState(() {
      _speed = position.speed * 3.6;
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
          : tr('radar fix', 'radar fijo');
      final metres = (alert.distanceMeters / 50).round() * 50;
      await _tts.speak(tr('$kind a $metres metres', '$kind a $metres metros'));
    }
  }

  Future<void> _stop() async {
    await _positions?.cancel();
    _positions = null;
    await _tts.stop();
    if (mounted) {
      setState(() {
        _driving = false;
        _speed = null;
        _alert = null;
        _alertAt = null;
        _status = tr('Conducció finalitzada', 'Conducción finalizada');
      });
    }
  }

  Future<void> _import() async {
    if (_driving) return;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) throw const FormatException('Cannot read file');
      if (bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('Dataset too large');
      }
      final data = await _store.replace(utf8.decode(bytes));
      if (mounted) {
        setState(() {
          _dataset = data;
          _engine = AlertEngine(data);
          _status = tr(
            '${data.radars.length} radars importats',
            '${data.radars.length} radares importados',
          );
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    }
  }

  Future<void> _download() async {
    if (_driving || _busy) return;
    setState(() => _busy = true);
    try {
      final data = await UpdateService(
        _store,
      ).download(widget.settings.updateUrl);
      await widget.settings.markUpdateCheck();
      if (mounted) {
        setState(() {
          _dataset = data;
          _engine = AlertEngine(data);
          _status = tr(
            '${data.radars.length} radars actualitzats',
            '${data.radars.length} radares actualizados',
          );
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(widget.settings, onDownload: _download),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _positions?.cancel();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _dataset;
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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  _status.isEmpty ? tr('Preparat', 'Preparado') : _status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Spacer(),
              Text(
                _speed == null ? '—' : '${_speed!.round()}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 84,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'km/h',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 28),
              Semantics(
                liveRegion: true,
                child: Text(
                  _alert == null
                      ? tr('Sense avisos', 'Sin avisos')
                      : '${_alert!.radar.kind == RadarKind.section ? tr('Radar de tram', 'Radar de tramo') : tr('Radar', 'Radar')} · ${_alert!.distanceMeters.round()} m',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _busy ? null : (_driving ? _stop : _start),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(72),
                ),
                icon: Icon(_driving ? Icons.stop : Icons.play_arrow),
                label: Text(
                  _driving ? tr('Atura', 'Detener') : tr('Inicia', 'Iniciar'),
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(height: 12),
              if (!_driving)
                OutlinedButton.icon(
                  onPressed: _import,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                  ),
                  icon: const Icon(Icons.file_open),
                  label: Text(tr('Importa dades JSON', 'Importar datos JSON')),
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
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(this.settings, {required this.onDownload, super.key});
  final AppSettings settings;
  final Future<void> Function() onDownload;
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
        const SizedBox(height: 20),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: tr('URL HTTPS de dades', 'URL HTTPS de datos'),
          ),
          onChanged: (v) => widget.settings.setUpdateUrl(v.trim()),
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
        SwitchListTile(
          title: Text(
            tr(
              'Actualització automàtica setmanal',
              'Actualización automática semanal',
            ),
          ),
          subtitle: Text(
            tr(
              'Només en obrir l’app, abans de conduir',
              'Solo al abrir la app, antes de conducir',
            ),
          ),
          value: widget.settings.automaticUpdates,
          onChanged: (v) async {
            await widget.settings.setAutomaticUpdates(v);
            setState(() {});
          },
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
            'Dades: DGT, IGN/CartoCiudad, Tachwire i OpenStreetMap (ODbL 1.0); Ajuntament de Madrid (CC BY 4.0); Servei Català de Trànsit. Vegeu DATA_SOURCES.md.',
            'Datos: DGT, IGN/CartoCiudad, Tachwire y OpenStreetMap (ODbL 1.0); Ayuntamiento de Madrid (CC BY 4.0); Servei Català de Trànsit. Consulta DATA_SOURCES.md.',
          ),
        ),
      ],
    ),
  );
}
