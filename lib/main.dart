import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'core/alert_engine.dart';
import 'core/geo.dart';
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
  final _beep = AudioPlayer(playerId: 'radar-alert');
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
  SectionProgress? _section;
  bool _busy = false;
  bool _updating = false;
  bool _pendingUpdate = false;
  bool _driving = false;
  bool _voiceReady = true;
  bool _voiceNeedsNetwork = false;
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
    // Beeps are navigation prompts: duck other audio and keep playing in
    // the background (Android usage + iOS playback session).
    unawaited(
      AudioPlayer.global
          .setAudioContext(
            AudioContext(
              android: const AudioContextAndroid(
                contentType: AndroidContentType.sonification,
                usageType: AndroidUsageType.assistanceNavigationGuidance,
                audioFocus: AndroidAudioFocus.gainTransientMayDuck,
              ),
              iOS: AudioContextIOS(
                category: AVAudioSessionCategory.playback,
                options: const {AVAudioSessionOptions.duckOthers},
              ),
            ),
          )
          .catchError((_) {}),
    );
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
        if (_store.recoveredFromCorruption) {
          _status = tr(
            'La base guardada estava malmesa; s’usa la inclosa en l’app',
            'La base guardada estaba dañada; se usa la incluida en la app',
          );
        }
      });
      _maybeAutomaticUpdate();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (!await _ensureDisclaimer()) {
          if (!mounted) return;
          setState(
            () => _status = tr(
              'Cal acceptar l’avís per iniciar la conducció',
              'Debes aceptar el aviso para iniciar la conducción',
            ),
          );
          return;
        }
        if (widget.settings.autoStart) unawaited(_start());
      });
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    }
  }

  void _maybeAutomaticUpdate() {
    final last = widget.settings.lastUpdateCheck;
    if (mounted &&
        !_updating &&
        widget.settings.automaticUpdates &&
        widget.settings.updateUrlTrusted &&
        (last == null ||
            DateTime.now().difference(last) > const Duration(days: 7))) {
      unawaited(_download(automatic: true));
    }
  }

  Future<bool> _ensureDisclaimer() async {
    if (widget.settings.disclaimerAccepted) return true;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        var checked = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(tr('Avís important', 'Aviso importante')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_disclaimerBody(_va)),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: checked,
                    onChanged: (value) =>
                        setDialogState(() => checked = value ?? false),
                    title: Text(
                      tr(
                        'He llegit i entenc l’avís',
                        'He leído y entiendo el aviso',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(tr('No accepte', 'No acepto')),
              ),
              FilledButton(
                onPressed: checked
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: Text(tr('Continuar', 'Continuar')),
              ),
            ],
          ),
        );
      },
    );
    if (accepted == true) {
      await widget.settings.setDisclaimerAccepted(true);
      return true;
    }
    return false;
  }

  Future<void> _start() async {
    if (_driving || _busy) return;
    if (!await _ensureDisclaimer()) return;
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
      // Voice setup must never block or break GPS start.
      try {
        await _configureVoice().timeout(const Duration(seconds: 4));
      } catch (_) {
        _voiceReady = true;
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
                // Keeps the CPU awake with the screen off so GPS fixes,
                // beeps and speech keep flowing in the background.
                enableWakeLock: true,
              ),
            )
          : Platform.isIOS
          ? AppleSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 15,
              activityType: ActivityType.automotiveNavigation,
              pauseLocationUpdatesAutomatically: false,
              allowBackgroundLocationUpdates: true,
              showBackgroundLocationIndicator: true,
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

  static String _normLocale(Object? locale) =>
      '${locale ?? ''}'.toLowerCase().replaceAll('_', '-');

  /// Picks a TTS voice for the current language and routes speech as
  /// navigation audio so it keeps playing with the app in the background.
  /// Prefers an installed offline voice; falls back to a network voice or
  /// to the engine default for the language before giving up.
  Future<void> _configureVoice() async {
    final language = _va ? 'ca-ES' : 'es-ES';
    final prefix = _va ? 'ca' : 'es';
    _voiceReady = false;
    _voiceNeedsNetwork = false;
    if (!widget.settings.voice) return;
    try {
      if (Platform.isAndroid) {
        await _tts.setAudioAttributesForNavigation();
      } else if (Platform.isIOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions
                .interruptSpokenAudioAndMixWithOthers,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      }
      await _tts.setLanguage(language);
      final voices = ((await _tts.getVoices) as List?) ?? const [];
      final candidates = voices.whereType<Map>().where((voice) {
        final locale = _normLocale(voice['locale']);
        return (locale == prefix || locale.startsWith('$prefix-')) &&
            !'${voice['features'] ?? ''}'.contains('not_installed');
      }).toList();
      int score(Map voice) =>
          ('${voice['network_required']}' == '1' ? 2 : 0) +
          (_normLocale(voice['locale']) == language.toLowerCase() ? 0 : 1);
      candidates.sort((a, b) => score(a).compareTo(score(b)));
      if (candidates.isNotEmpty) {
        final voice = candidates.first;
        final ok = await _tts.setVoice({
          'name': '${voice['name']}',
          'locale': '${voice['locale']}',
        });
        _voiceReady = true;
        _voiceNeedsNetwork =
            ok == 1 && '${voice['network_required']}' == '1';
      } else {
        final available = await _tts.isLanguageAvailable(language);
        _voiceReady = available == true || available == 1;
      }
      if (_voiceReady) await _tts.setSpeechRate(0.48);
    } catch (_) {
      _voiceReady = false;
    }
  }

  String _voiceStatus() => tr(
    'Veu catalana no instal·lada: només so. Instal·la-la en Ajustos > Text a veu',
    'Voz en castellano no instalada: solo sonido. Instálala en Ajustes > Texto a voz',
  );

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
    final section = _engine?.sectionProgress;
    final limit =
        section?.radar.speedLimit ?? _engine?.limitAhead(fix)?.speedLimit;
    setState(() {
      _speed = position.speed * 3.6;
      _speedLimit = limit;
      _section = section;
      _status = widget.settings.voice && !_voiceReady
          ? _voiceStatus()
          : fix.reliable && _voiceNeedsNetwork
          ? tr(
              'GPS actiu · veu en línia (descarrega la veu offline)',
              'GPS activo · voz en línea (descarga la voz offline)',
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
    if (alert != null) {
      unawaited(_announce(alert));
    } else if (_engine?.passedRadar != null && widget.settings.sound) {
      unawaited(_playBeep(asset: 'audio/passed.wav'));
    }
  }

  Future<void> _playBeep({String asset = 'audio/beep.wav'}) async {
    try {
      await _beep.stop();
      final completed = _beep.onPlayerComplete.first;
      await _beep.play(AssetSource(asset));
      await completed.timeout(const Duration(seconds: 2), onTimeout: () {});
    } catch (_) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _announce(RadarAlert alert) async {
    final average = alert.averageKmh?.round();
    if (alert.phase == AlertPhase.sectionAverage &&
        !widget.settings.sectionAverageWarning) {
      return;
    }
    if (widget.settings.sound) await _playBeep();
    if (!widget.settings.voice || !_voiceReady) return;
    if (alert.phase == AlertPhase.sectionEnd) {
      await _tts.speak(
        average == null
            ? tr('Fi de tram', 'Fin de tramo')
            : tr(
                'Fi de tram. Mitjana $average quilòmetres per hora',
                'Fin de tramo. Media $average kilómetros por hora',
              ),
      );
      return;
    }
    if (alert.phase == AlertPhase.sectionAverage) {
      final limit = alert.radar.speedLimit;
      await _tts.speak(
        tr(
          'Mitjana del tram $average quilòmetres per hora${limit == null ? '' : ', límit $limit'}',
          'Media del tramo $average kilómetros por hora${limit == null ? '' : ', límite $limit'}',
        ),
      );
      return;
    }
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
    final limit = alert.radar.speedLimit;
    final suffix = limit == null ? '' : tr(', límit $limit', ', límite $limit');
    await _tts.speak(
      tr('$kind a $metres metres$suffix', '$kind a $metres metros$suffix'),
    );
  }

  String _alertLabel(RadarAlert alert) => switch (alert.radar.kind) {
    RadarKind.section => tr('Radar de tram', 'Radar de tramo'),
    RadarKind.redLight => tr('Radar de semàfor', 'Radar de semáforo'),
    RadarKind.phone || RadarKind.lineStop => tr(
      'Càmera de control',
      'Cámara de control',
    ),
    RadarKind.fixed => tr('Radar', 'Radar'),
  };

  String _neededAverageText(double needed) {
    if (needed > 160) {
      return tr(
        'Ja no es pot compensar amb seguretat',
        'Ya no se puede compensar con seguridad',
      );
    }
    if (needed <= 0) {
      return tr(
        'Ja vas per davall de la mitjana del límit',
        'Ya vas por debajo de la media del límite',
      );
    }
    return tr(
      'Per acabar dins del límit: ≤ ${needed.round()} km/h',
      'Para acabar dentro del límite: ≤ ${needed.round()} km/h',
    );
  }

  String _distanceText(double metres) {
    if (metres >= 1000) {
      final km = (metres / 100).round() / 10;
      return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
    }
    return '${(metres / 10).round() * 10} m';
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
        _section = null;
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
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return false;
    const maxBytes = 10 * 1024 * 1024;
    // Check the size before reading so a huge file is never loaded.
    if ((await file.length() ?? 0) > maxBytes) {
      throw const FormatException('Dataset too large');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) {
      throw const FormatException('Dataset too large');
    }
    final candidate = await parseDataset(utf8.decode(bytes));
    if (!mounted || !await _confirmImport(candidate)) return false;
    final data = await _store.replace(candidate);
    await widget.settings.clearUpdateCheck();
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

  Future<bool> _confirmImport(RadarDataset candidate) async {
    final current = _dataset;
    final fewer =
        current != null &&
        candidate.radars.length < current.radars.length * 0.8;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Substituir la base?', '¿Sustituir la base?')),
        content: Text(
          [
            tr(
              '${candidate.radars.length} avisos (ara ${current?.radars.length ?? 0})',
              '${candidate.radars.length} avisos (ahora ${current?.radars.length ?? 0})',
            ),
            '${tr('Font', 'Fuente')}: ${candidate.source}',
            '${tr('Data', 'Fecha')}: ${candidate.updatedAt.toLocal().toString().substring(0, 10)}',
            if (fewer)
              tr(
                'Atenció: té molts menys avisos que la base actual.',
                'Atención: tiene muchos menos avisos que la base actual.',
              ),
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel·la', 'Cancelar')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Substituix', 'Sustituir')),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _download({bool automatic = false}) async {
    if (_updating || (!automatic && (_driving || _busy))) return;
    _updating = true;
    if (!automatic) setState(() => _busy = true);
    try {
      final sourceUrl = widget.settings.updateUrl;
      if (!widget.settings.updateUrlTrusted) {
        throw const FormatException('Unconfirmed update URL');
      }
      final fetched = await UpdateService().fetch(sourceUrl);
      if (widget.settings.updateUrl != sourceUrl) return;
      final active = _pendingDataset ?? _dataset;
      if (widget.settings.lastUpdateCheck != null && active != null) {
        fetched.checkReplaces(active);
      }
      final data = automatic
          ? await _store.stage(fetched)
          : await _store.replace(fetched);
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
    // Language or voice may have changed: reconfigure TTS while driving.
    if (_driving) await _configureVoice();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _positions?.cancel();
    _tts.stop();
    _beep.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _dataset;
    final speed = _speed?.round();
    final limit = _speedLimit;
    final average = _section?.averageKmh;
    final averageColor = average == null || limit == null
        ? null
        : _speedColor(context, SpeedLimit.zone(average.round(), limit));
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
                              : _alert!.phase == AlertPhase.sectionEnd
                              ? _alert!.averageKmh == null
                                    ? tr('Fi de tram', 'Fin de tramo')
                                    : tr(
                                        'Fi de tram · mitjana ${_alert!.averageKmh!.round()} km/h',
                                        'Fin de tramo · media ${_alert!.averageKmh!.round()} km/h',
                                      )
                              : _alert!.phase == AlertPhase.sectionAverage
                              ? tr(
                                  'Mitjana ${_alert!.averageKmh?.round() ?? 0} km/h · límit ${_alert!.radar.speedLimit ?? '—'}',
                                  'Media ${_alert!.averageKmh?.round() ?? 0} km/h · límite ${_alert!.radar.speedLimit ?? '—'}',
                                )
                              : '${_alertLabel(_alert!)} · ${_alert!.distanceMeters.round()} m',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      if (_section != null)
                        Text(
                          tr(
                            'Tram actiu · queden ${_distanceText(_section!.remainingMeters)}',
                            'Tramo activo · quedan ${_distanceText(_section!.remainingMeters)}',
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      if (average != null)
                        Text(
                          tr(
                            'Mitjana del tram · ${average.round()} km/h',
                            'Media del tramo · ${average.round()} km/h',
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                averageColor ??
                                Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      if (_section?.neededAverageKmh != null)
                        Text(
                          _neededAverageText(_section!.neededAverageKmh!),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (_alert != null &&
                          _alert!.phase == AlertPhase.approach &&
                          _alert!.radar.kind == RadarKind.section &&
                          _alert!.radar.end != null)
                        Text(
                          tr(
                            'Tram de ${_distanceText(distanceMeters(_alert!.radar.start, _alert!.radar.end!))}',
                            'Tramo de ${_distanceText(distanceMeters(_alert!.radar.start, _alert!.radar.end!))}',
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
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

  Future<bool> _confirmCustomUrl() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Font no verificada', 'Fuente no verificada')),
        content: Text(
          tr(
            'Només la font de GitHub per defecte porta la signatura de Radar Local. Les dades d’aquesta URL no es poden verificar: si són incorrectes, l’app pot deixar d’avisar. Vols fer-la servir?',
            'Solo la fuente de GitHub predeterminada lleva la firma de Radar Local. Los datos de esta URL no se pueden verificar: si son incorrectos, la app puede dejar de avisar. ¿Quieres usarla?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel·la', 'Cancelar')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Fes-la servir', 'Usarla')),
          ),
        ],
      ),
    );
    return confirmed ?? false;
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
              'Avís de veu si la mitjana del tram supera el límit',
              'Aviso de voz si la media del tramo supera el límite',
            ),
          ),
          subtitle: Text(
            tr(
              'Un sol avís per tram, quan ja hi ha prou recorregut',
              'Un solo aviso por tramo, cuando ya hay suficiente recorrido',
            ),
          ),
          value: widget.settings.sectionAverageWarning,
          onChanged: (v) async {
            await widget.settings.setSectionAverageWarning(v);
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
            if (!widget.settings.updateUrlTrusted) {
              if (!await _confirmCustomUrl()) return;
              await widget.settings.confirmUpdateUrl();
            }
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
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.gavel),
          title: Text(
            tr('Avís legal i responsabilitat', 'Aviso legal y responsabilidad'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => LegalScreen(widget.settings),
            ),
          ),
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

String _disclaimerBody(bool va) => va
    ? 'Radar Local és una ajuda orientativa per a la conducció. No és un '
          'sistema oficial de seguretat ni substitueix la senyalització, el '
          'velocímetre ni les normes de trànsit.\n\n'
          '- Les dades poden estar incompletes, desactualitzades o ser '
          'incorrectes. Els límits de la DGT són estimats; la mitjana del '
          'tram també és una estimació.\n'
          '- L’app pot fallar, retardar-se o perdre el senyal GPS. No '
          'garantix que s’eviten sancions.\n'
          '- No manipules el telèfon mentre conduïx.\n'
          '- La responsabilitat de conduir dins dels límits i de respectar '
          'les normes és del conductor.\n\n'
          'El GPS es processa al dispositiu. No hi ha servidor ni analítica '
          'de l’app.'
    : 'Radar Local es una ayuda orientativa para la conducción. No es un '
          'sistema oficial de seguridad ni sustituye la señalización, el '
          'velocímetro ni las normas de tráfico.\n\n'
          '- Los datos pueden estar incompletos, desactualizados o ser '
          'incorrectos. Los límites de la DGT son estimados; la media del '
          'tramo también es una estimación.\n'
          '- La app puede fallar, retrasarse o perder la señal GPS. No '
          'garantiza evitar sanciones.\n'
          '- No manipules el teléfono mientras conduces.\n'
          '- La responsabilidad de conducir dentro de los límites y de '
          'respetar las normas es del conductor.\n\n'
          'El GPS se procesa en el dispositivo. No hay servidor ni analítica '
          'de la app.';

class LegalScreen extends StatelessWidget {
  const LegalScreen(this.settings, {super.key});
  final AppSettings settings;

  bool get va => settings.language == 'va';
  String tr(String a, String b) => va ? a : b;

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _body(BuildContext context, String text) => Text(
    text,
    style: Theme.of(context).textTheme.bodyMedium,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Avís legal', 'Aviso legal'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          tr('Avís important', 'Aviso importante'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        _body(context, _disclaimerBody(va)),
        _heading(context, tr('Privacitat', 'Privacidad')),
        _body(
          context,
          tr(
            'El GPS i les propostes es queden al dispositiu. L’app no envia '
                'la ubicació a cap servidor propi. Més detall a PRIVACY.md.',
            'El GPS y las propuestas se quedan en el dispositivo. La app no '
                'envía la ubicación a ningún servidor propio. Más detalle en '
                'PRIVACY.md.',
          ),
        ),
        _heading(
          context,
          tr('Llicències i atribucions', 'Licencias y atribuciones'),
        ),
        _body(
          context,
          tr(
            'El codi és MIT. Les dades provenen de la DGT, IGN/CartoCiudad, '
                'Tachwire i col·laboradors d’OpenStreetMap (ODbL 1.0), '
                'l’Ajuntament de Madrid (CC BY 4.0) i el Servei Català de '
                'Trànsit. Vegeu DATA_SOURCES.md.',
            'El código es MIT. Los datos provienen de la DGT, IGN/CartoCiudad, '
                'Tachwire y colaboradores de OpenStreetMap (ODbL 1.0), el '
                'Ayuntamiento de Madrid (CC BY 4.0) y el Servei Català de '
                'Trànsit. Consulta DATA_SOURCES.md.',
          ),
        ),
        _heading(
          context,
          tr('Limitació de responsabilitat', 'Limitación de responsabilidad'),
        ),
        _body(
          context,
          tr(
            'L’app es proporciona «tal qual», sense garanties expresses ni '
                'implícites de funcionament, exactitud o disponibilitat. En la '
                'mesura permesa per la llei, l’autor no respon de danys '
                'derivats de l’ús o de la impossibilitat d’usar l’app. Este '
                'avís no exclou les responsabilitats que la llei no permet '
                'excloure ni els drets que t’assistisquen com a consumidor.',
            'La app se proporciona «tal cual», sin garantías expresas ni '
                'implícitas de funcionamiento, exactitud o disponibilidad. En '
                'la medida permitida por la ley, el autor no responde de daños '
                'derivados del uso o de la imposibilidad de usar la app. Este '
                'aviso no excluye las responsabilidades que la ley no permite '
                'excluir ni los derechos que te asistan como consumidor.',
          ),
        ),
        _heading(context, tr('Contacte', 'Contacto')),
        _body(
          context,
          tr(
            'Incidències i suggeriments: github.com/sasogu/radar-local/issues',
            'Incidencias y sugerencias: github.com/sasogu/radar-local/issues',
          ),
        ),
      ],
    ),
  );
}
