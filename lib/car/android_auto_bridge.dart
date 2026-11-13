import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_carplay/flutter_carplay.dart';

import 'car_pane.dart';
import 'car_state.dart';

/// Bridges the phone driving state to the Android Auto car screen.
///
/// The bridge is deliberately small: it installs one pane when Android Auto
/// connects and refreshes it only when the published snapshot changes. GPS,
/// alerts, TTS and data loading stay in the existing phone code.
class AndroidAutoBridge {
  AndroidAutoBridge._();

  static final instance = AndroidAutoBridge._();

  static const _paneId = 'radar-local-car-pane';
  static const _refresh = Duration(seconds: 2);

  FlutterAndroidAuto? _controller;
  Timer? _timer;
  bool _connected = false;
  bool _installed = false;
  bool _needsInstall = false;
  bool _installing = false;
  bool _updating = false;
  bool _dirty = true;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  CarSnapshot _lastSnapshot = CarSnapshot.empty;

  void initialize() {
    if (!Platform.isAndroid || _controller != null) return;
    try {
      _controller = FlutterAndroidAuto()
        ..addListenerOnConnectionChange(_onConnection);
      CarDriveState.instance.snapshot.addListener(_onSnapshot);
      _timer?.cancel();
      _timer = Timer.periodic(_refresh, (_) => unawaited(_pushIfNeeded()));
      if (FlutterAndroidAuto.connectionStatus ==
          ConnectionStatusTypes.connected.name) {
        _onConnection(ConnectionStatusTypes.connected);
      }
    } catch (error) {
      debugPrint('Android Auto no disponible: $error');
      _controller = null;
    }
  }

  void _onConnection(ConnectionStatusTypes status) {
    final connected = status == ConnectionStatusTypes.connected;
    if (connected == _connected) return;
    _connected = connected;
    _installed = false;
    _needsInstall = connected;
    _dirty = true;
    if (connected) unawaited(_installRoot());
  }

  void _onSnapshot() {
    _dirty = true;
    if (_connected && _installed) unawaited(_pushIfNeeded());
  }

  void _run(Future<void> Function()? action) {
    if (action == null) return;
    unawaited(
      action().catchError((Object error) {
        debugPrint('Android Auto action failed: $error');
      }),
    );
  }

  Future<void> _installRoot() async {
    if (!_connected || _installing || _updating) return;
    _installing = true;
    try {
      final snapshot = CarDriveState.instance.snapshot.value;
      await FlutterAndroidAuto.setRootTemplate(
        template: buildCarPane(
          snapshot: snapshot,
          id: _paneId,
          onStart: () => _run(CarDriveState.instance.onStart),
          onStop: () => _run(CarDriveState.instance.onStop),
        ),
      );
      if (!_connected) return;
      _installed = true;
      _needsInstall = false;
      _lastSnapshot = snapshot;
      _lastPush = DateTime.now();
      _dirty = CarDriveState.instance.snapshot.value != snapshot;
    } catch (error) {
      debugPrint('Android Auto root failed: $error');
      _installed = false;
      _needsInstall = true;
    } finally {
      _installing = false;
    }
  }

  Future<void> _pushIfNeeded() async {
    if (!_connected || _updating) return;
    if (_needsInstall) {
      await _installRoot();
      if (!_installed) return;
    }
    if (!_installed) return;
    final snapshot = CarDriveState.instance.snapshot.value;
    if (!_dirty && snapshot == _lastSnapshot) return;
    final now = DateTime.now();
    if (now.difference(_lastPush) < _refresh) return;
    _updating = true;
    try {
      final updated = await FlutterAndroidAuto.updatePaneTemplate(
        template: buildCarPane(
          snapshot: snapshot,
          id: _paneId,
          onStart: () => _run(CarDriveState.instance.onStart),
          onStop: () => _run(CarDriveState.instance.onStop),
        ),
      );
      if (updated) {
        _lastSnapshot = snapshot;
        _lastPush = now;
        _dirty = CarDriveState.instance.snapshot.value != snapshot;
      } else {
        _installed = false;
        _needsInstall = true;
      }
    } catch (error) {
      debugPrint('Android Auto update failed: $error');
      _installed = false;
      _needsInstall = true;
    } finally {
      _updating = false;
    }
  }
}
