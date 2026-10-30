import 'dart:math' as math;
import 'geo.dart';
import 'radar.dart';

class GpsFix {
  const GpsFix({
    required this.point,
    required this.time,
    required this.accuracy,
    required this.speed,
    required this.heading,
    this.speedAccuracy = 0,
    this.headingAccuracy = 0,
  });
  final Point point;
  final DateTime time;
  final double accuracy;
  final double speed; // m/s
  final double heading;
  final double speedAccuracy;
  final double headingAccuracy;

  bool get reliable =>
      accuracy.isFinite &&
      accuracy <= 50 &&
      accuracy >= 0 &&
      speed.isFinite &&
      speed >= 0 &&
      speed <= 70 &&
      speedAccuracy >= 0 &&
      speedAccuracy <= 5 &&
      heading.isFinite &&
      heading >= 0 &&
      heading < 360 &&
      headingAccuracy >= 0 &&
      headingAccuracy <= 45;
}

class RadarAlert {
  const RadarAlert(this.radar, this.distanceMeters);
  final Radar radar;
  final double distanceMeters;
}

class AlertEngine {
  AlertEngine(RadarDataset dataset) : _index = RadarIndex(dataset.radars);
  final RadarIndex _index;
  final Map<String, DateTime> _announced = {};
  GpsFix? _previous;
  RadarAlert? _lastAlert;
  DateTime? _lastAlertAt;

  Radar? limitAhead(GpsFix fix, {double maxDistance = 1200}) {
    if (!fix.reliable) return null;
    Radar? best;
    var bestDistance = double.infinity;
    for (final radar in _index.near(fix.point, maxDistance)) {
      if (radar.speedLimit == null) continue;
      final distance = distanceMeters(fix.point, radar.start);
      if (distance > maxDistance ||
          distance <= math.max(35, fix.accuracy * 1.5) ||
          bearingDifference(
                fix.heading,
                bearingDegrees(fix.point, radar.start),
              ) >
              50 ||
          (radar.direction != null &&
              bearingDifference(fix.heading, radar.direction!) > 35)) {
        continue;
      }
      if (distance < bestDistance) {
        best = radar;
        bestDistance = distance;
      }
    }
    return best;
  }

  RadarAlert? evaluate(GpsFix fix) {
    if (!fix.reliable ||
        fix.speed < 3 ||
        DateTime.now().difference(fix.time).inSeconds.abs() > 15) {
      _previous = fix;
      return null;
    }
    final previous = _previous;
    _previous = fix;
    if (previous != null && fix.time.isAfter(previous.time)) {
      final dt = fix.time.difference(previous.time).inMilliseconds / 1000;
      final displacement = distanceMeters(previous.point, fix.point);
      if (dt < 0.5 ||
          (dt < 10 && displacement / dt > math.max(65, fix.speed * 2.5))) {
        return null;
      }
    }
    final radius = (fix.speed * 15 + fix.accuracy).clamp(180.0, 1200.0);
    final candidates = <RadarAlert>[];
    for (final radar in _index.near(fix.point, radius)) {
      final distance = distanceMeters(fix.point, radar.start);
      if (distance <= math.max(35, fix.accuracy * 1.5)) continue;
      if (bearingDifference(
            fix.heading,
            bearingDegrees(fix.point, radar.start),
          ) >
          50) {
        continue;
      }
      if (radar.direction != null &&
          bearingDifference(fix.heading, radar.direction!) > 35) {
        continue;
      }
      final last = _announced[radar.id];
      if (last != null &&
          fix.time.difference(last) < const Duration(minutes: 5)) {
        continue;
      }
      final lastAlert = _lastAlert;
      if (lastAlert != null &&
          _lastAlertAt != null &&
          fix.time.difference(_lastAlertAt!) < const Duration(minutes: 5) &&
          distanceMeters(radar.start, lastAlert.radar.start) < 80) {
        continue;
      }
      candidates.add(RadarAlert(radar, distance));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      // A section start gets a small lead, but an imminent fixed radar wins.
      final aSeconds =
          a.distanceMeters / fix.speed -
          (a.radar.kind == RadarKind.section ? 3 : 0);
      final bSeconds =
          b.distanceMeters / fix.speed -
          (b.radar.kind == RadarKind.section ? 3 : 0);
      return aSeconds.compareTo(bSeconds);
    });
    final alert = candidates.first;
    _announced[alert.radar.id] = fix.time;
    _lastAlert = alert;
    _lastAlertAt = fix.time;
    _announced.removeWhere(
      (_, at) => fix.time.difference(at) > const Duration(hours: 1),
    );
    return alert;
  }
}
