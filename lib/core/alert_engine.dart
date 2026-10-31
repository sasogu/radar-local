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

enum AlertPhase { approach, sectionEnd, sectionAverage }

class RadarAlert {
  const RadarAlert(
    this.radar,
    this.distanceMeters, {
    this.phase = AlertPhase.approach,
    this.averageKmh,
  });
  final Radar radar;
  final double distanceMeters;
  final AlertPhase phase;

  /// Average speed over the section when the alert refers to it.
  final double? averageKmh;
}

class SectionProgress {
  const SectionProgress(
    this.radar, {
    required this.remainingMeters,
    required this.fraction,
    this.averageKmh,
  });
  final Radar radar;

  /// Straight-line distance to the section end.
  final double remainingMeters;

  /// Position along the start–end chord, 0 at the start and 1 at the end.
  final double fraction;

  /// Estimated average since entering, once there is enough distance/time.
  final double? averageKmh;
}

class AlertEngine {
  AlertEngine(RadarDataset dataset)
    : _index = RadarIndex(dataset.radars),
      _sections = dataset.radars
          .where((r) => r.kind == RadarKind.section && r.end != null)
          .toList();
  final RadarIndex _index;
  final List<Radar> _sections;
  final Map<String, DateTime> _announced = {};
  GpsFix? _previous;
  RadarAlert? _lastAlert;
  DateTime? _lastAlertAt;
  Radar? _activeSection;
  SectionProgress? _sectionProgress;
  double _lastEndDistance = double.infinity;
  DateTime? _sectionStartedAt;
  double _sectionTraveled = 0;
  Point? _sectionLastPoint;
  bool _sectionAverageWarned = false;

  SectionProgress? get sectionProgress => _sectionProgress;

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

  /// Finds the section the fix is currently travelling through, if any.
  SectionProgress? _sectionAt(GpsFix fix) {
    final corridor = math.max(50.0, fix.accuracy * 2).clamp(50.0, 120.0);
    SectionProgress? best;
    for (final radar in _sections) {
      final end = radar.end!;
      final projection = projectOnSegment(fix.point, radar.start, end);
      if (projection.fraction < 0 || projection.fraction > 1) continue;
      if (projection.distanceMeters > corridor) continue;
      if (radar.direction != null &&
          bearingDifference(fix.heading, radar.direction!) > 35) {
        continue;
      }
      if (bearingDifference(fix.heading, bearingDegrees(radar.start, end)) >
          50) {
        continue;
      }
      final progress = SectionProgress(
        radar,
        remainingMeters: distanceMeters(fix.point, end),
        fraction: projection.fraction,
      );
      if (best == null || progress.fraction > best.fraction) best = progress;
    }
    return best;
  }

  /// Estimated average over the active section: accumulated GPS distance
  /// divided by elapsed time. Null until there is enough of both.
  double? _averageKmh(GpsFix fix) {
    final startedAt = _sectionStartedAt;
    if (startedAt == null || !fix.time.isAfter(startedAt)) return null;
    final elapsed = fix.time.difference(startedAt).inMilliseconds / 1000;
    if (elapsed < 10 || _sectionTraveled < 200) return null;
    return _sectionTraveled / elapsed * 3.6;
  }

  void _resetSectionTracking() {
    _sectionStartedAt = null;
    _sectionTraveled = 0;
    _sectionLastPoint = null;
    _sectionAverageWarned = false;
  }

  /// Tracks the active section and returns one-off end or average alerts.
  RadarAlert? _updateSection(GpsFix fix) {
    final active = _activeSection;
    if (active != null) {
      final lastPoint = _sectionLastPoint;
      if (lastPoint != null) {
        final step = distanceMeters(lastPoint, fix.point);
        if (step <= 300) _sectionTraveled += step;
      }
      _sectionLastPoint = fix.point;
      final average = _averageKmh(fix);
      final end = active.end!;
      final remaining = distanceMeters(fix.point, end);
      final startDistance = distanceMeters(fix.point, active.start);
      final endBehind =
          bearingDifference(fix.heading, bearingDegrees(fix.point, end)) > 120;
      final passed =
          remaining <= 60 ||
          (endBehind && startDistance > 300) ||
          (_lastEndDistance < 250 &&
              remaining > _lastEndDistance &&
              startDistance > remaining);
      if (passed) {
        RadarAlert? alert;
        final key = '${active.id}:end';
        final last = _announced[key];
        if (last == null ||
            fix.time.difference(last) >= const Duration(minutes: 5)) {
          _announced[key] = fix.time;
          alert = RadarAlert(
            active,
            0,
            phase: AlertPhase.sectionEnd,
            averageKmh: average,
          );
        }
        _activeSection = null;
        _sectionProgress = null;
        _lastEndDistance = double.infinity;
        _resetSectionTracking();
        return alert;
      }
      _lastEndDistance = remaining;
      _sectionProgress = SectionProgress(
        active,
        remainingMeters: remaining,
        fraction: _sectionAt(fix)?.fraction ?? _sectionProgress?.fraction ?? 0,
        averageKmh: average,
      );
      final limit = active.speedLimit;
      if (!_sectionAverageWarned &&
          average != null &&
          limit != null &&
          average > limit) {
        _sectionAverageWarned = true;
        return RadarAlert(
          active,
          0,
          phase: AlertPhase.sectionAverage,
          averageKmh: average,
        );
      }
      return null;
    }
    final found = _sectionAt(fix);
    if (found != null) {
      _activeSection = found.radar;
      _sectionProgress = found;
      _lastEndDistance = found.remainingMeters;
      _sectionStartedAt = fix.time;
      _sectionTraveled = 0;
      _sectionLastPoint = fix.point;
      _sectionAverageWarned = false;
    }
    return null;
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
    final sectionEnd = _updateSection(fix);
    if (sectionEnd != null) {
      _lastAlert = sectionEnd;
      _lastAlertAt = fix.time;
      return sectionEnd;
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
