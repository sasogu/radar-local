import 'package:flutter/foundation.dart';

/// Immutable view of the driving state that the Android Auto screen renders.
///
/// The phone UI owns the language and the formatting; the car screen only
/// presents these strings, so this model stays free of Flutter widgets and
/// platform plugins.
@immutable
class CarSnapshot {
  const CarSnapshot({
    required this.language,
    required this.driving,
    required this.speed,
    required this.limit,
    required this.alert,
    required this.section,
    required this.status,
    required this.base,
  });

  final String language;
  final bool driving;
  final String speed;
  final String limit;
  final String alert;
  final String section;
  final String status;
  final String base;

  static const empty = CarSnapshot(
    language: 'va',
    driving: false,
    speed: '—',
    limit: '—',
    alert: '',
    section: '',
    status: '',
    base: '',
  );

  bool get isCatalan => language == 'va';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CarSnapshot &&
          other.language == language &&
          other.driving == driving &&
          other.speed == speed &&
          other.limit == limit &&
          other.alert == alert &&
          other.section == section &&
          other.status == status &&
          other.base == base;

  @override
  int get hashCode => Object.hash(
    language,
    driving,
    speed,
    limit,
    alert,
    section,
    status,
    base,
  );
}

/// Shared driving state and callbacks used by the Android Auto bridge.
///
/// [HomeScreen] publishes snapshots and binds the start/stop actions; the car
/// screen listens to the notifier and invokes those actions from the car.
class CarDriveState {
  CarDriveState._();

  static final instance = CarDriveState._();

  final ValueNotifier<CarSnapshot> snapshot = ValueNotifier<CarSnapshot>(
    CarSnapshot.empty,
  );

  Future<void> Function()? onStart;
  Future<void> Function()? onStop;

  void publish(CarSnapshot value) {
    if (snapshot.value == value) return;
    snapshot.value = value;
  }
}
