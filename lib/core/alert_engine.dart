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
    required this.traveledMeters,
    required this.elapsedSeconds,
    this.lengthMeters,
    this.averageKmh,
    this.neededAverageKmh,
  });
  final Radar radar;

  /// Remaining distance: official length minus GPS travel when known.
  final double remainingMeters;

  /// Position along the start–end chord, 0 at the start and 1 at the end.
  final double fraction;

  /// GPS distance accumulated since the interpolated entry.
  final double traveledMeters;

  final double elapsedSeconds;

  /// Official DGT length in metres, when available.
  final double? lengthMeters;

  /// Estimated average since entering, once there is enough distance/time.
  final double? averageKmh;

  /// Average needed over the remaining distance to end at the limit.
  final double? neededAverageKmh;
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
  final Set<String> _approached = {};
  Radar? _passedRadar;
  SectionProgress? _sectionProgress;
  double _lastEndDistance = double.infinity;
  DateTime? _sectionStartedAt;
  double _sectionTraveled = 0;
  Point? _sectionLastPoint;
  DateTime? _sectionLastTime;
  bool _sectionAverageWarned = false;

  SectionProgress? get sectionProgress => _sectionProgress;

  /// Radar the vehicle has just passed during the last [evaluate] call.
  Radar? get passedRadar => _passedRadar;

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
      if (radar.direction != null) {
        if (bearingDifference(fix.heading, radar.direction!) > 35) continue;
      } else if (bearingDifference(
            fix.heading,
            bearingDegrees(radar.start, end),
          ) >
          50) {
        continue;
      }
      final progress = SectionProgress(
        radar,
        remainingMeters: distanceMeters(fix.point, end),
        fraction: projection.fraction,
        traveledMeters: 0,
        elapsedSeconds: 0,
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
    _sectionLastTime = null;
    _sectionAverageWarned = false;
  }

  static Point _lerpPoint(Point a, Point b, double t) => Point(
    a.lat + (b.lat - a.lat) * t,
    a.lon + (b.lon - a.lon) * t,
  );

  static DateTime _lerpTime(DateTime a, DateTime b, double t) => a.add(
    Duration(
      microseconds: (b.difference(a).inMicroseconds * t).round(),
    ),
  );

  double? _neededAverage(
    Radar radar,
    double traveled,
    double remaining,
    double elapsed,
    double? average,
  ) {
    final limit = radar.speedLimit;
    if (limit == null || average == null || average <= limit) return null;
    final total = radar.length?.toDouble() ?? (traveled + remaining);
    if (total <= 0) return null;
    final remainingRoad = math.max(0, total - traveled);
    final budget = total / (limit / 3.6) - elapsed;
    if (budget <= 0 || remainingRoad <= 0) return 0;
    return remainingRoad / budget * 3.6;
  }

  double _remainingFor(Radar radar, double traveled, GpsFix fix) {
    final distanceToEnd = distanceMeters(fix.point, radar.end!);
    final length = radar.length;
    if (length == null) return distanceToEnd;
    // GPS distance can overestimate over long sections; never show less than
    // the straight-line distance to the end.
    return math.max(math.max(0, length - traveled), distanceToEnd);
  }

  /// Interpolates the crossing of the section start between the last accepted
  /// fix and the current one, so the average does not lose the first metres.
  void _startSection(SectionProgress found, GpsFix fix, GpsFix? previous) {
    var startedAt = fix.time;
    var entryPoint = fix.point;
    final end = found.radar.end!;
    if (previous != null && fix.time.isAfter(previous.time)) {
      final before = projectOnSegment(previous.point, found.radar.start, end);
      if (before.fraction < 0 && found.fraction >= 0) {
        final span = found.fraction - before.fraction;
        if (span > 0) {
          final t = (-before.fraction / span).clamp(0.0, 1.0);
          entryPoint = _lerpPoint(previous.point, fix.point, t);
          startedAt = _lerpTime(previous.time, fix.time, t);
        }
      }
    }
    _activeSection = found.radar;
    _sectionStartedAt = startedAt;
    _sectionTraveled = distanceMeters(entryPoint, fix.point);
    _sectionLastPoint = fix.point;
    _sectionLastTime = fix.time;
    _sectionAverageWarned = false;
    _lastEndDistance = distanceMeters(fix.point, end);
    _sectionProgress = SectionProgress(
      found.radar,
      remainingMeters: _remainingFor(
        found.radar,
        _sectionTraveled,
        fix,
      ),
      fraction:
          (found.radar.length == null
                  ? found.fraction
                  : _sectionTraveled / found.radar.length!)
              .clamp(0.0, 1.0),
      traveledMeters: _sectionTraveled,
      elapsedSeconds: 0,
      lengthMeters: found.radar.length?.toDouble(),
    );
  }

  /// Tracks the active section and returns one-off end or average alerts.
  RadarAlert? _updateSection(GpsFix fix, GpsFix? previous) {
    final active = _activeSection;
    if (active == null) {
      final found = _sectionAt(fix);
      if (found != null) _startSection(found, fix, previous);
      return null;
    }
    final end = active.end!;
    final startedAt = _sectionStartedAt;
    final lastPoint = _sectionLastPoint;
    final lastTime = _sectionLastTime;
    final step = lastPoint == null ? 0.0 : distanceMeters(lastPoint, fix.point);
    final before = _sectionTraveled;
    final traveled = before + (step <= 300 ? step : 0);
    final distanceToEnd = distanceMeters(fix.point, end);
    final startDistance = distanceMeters(fix.point, active.start);
    final endBehind =
        bearingDifference(fix.heading, bearingDegrees(fix.point, end)) > 120;
    final crossed =
        projectOnSegment(fix.point, active.start, end).fraction >= 1.0;
    final passed =
        (crossed && distanceToEnd <= 60) ||
        distanceToEnd <= 10 ||
        (_lastEndDistance < 150 && distanceToEnd > _lastEndDistance + 2) ||
        (endBehind && startDistance > 300);
    final elapsed = startedAt == null
        ? 0.0
        : math.max(
            0.0,
            fix.time.difference(startedAt).inMilliseconds / 1000,
          );
    if (passed) {
      var exitTraveled = traveled;
      var exitElapsed = elapsed;
      if (lastPoint != null && lastTime != null) {
        final t = projectOnSegment(end, lastPoint, fix.point).fraction.clamp(
          0.0,
          1.0,
        );
        final exitPoint = _lerpPoint(lastPoint, fix.point, t);
        final exitTime = _lerpTime(lastTime, fix.time, t);
        final exitStep = distanceMeters(lastPoint, exitPoint);
        exitTraveled = before + (exitStep <= 300 ? exitStep : 0);
        if (startedAt != null && exitTime.isAfter(startedAt)) {
          exitElapsed = exitTime.difference(startedAt).inMilliseconds / 1000;
        }
      }
      final finalDistance = active.length?.toDouble() ?? exitTraveled;
      final finalAverage = exitElapsed >= 3
          ? finalDistance / exitElapsed * 3.6
          : _averageKmh(fix);
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
          averageKmh: finalAverage,
        );
      }
      _activeSection = null;
      _sectionProgress = null;
      _lastEndDistance = double.infinity;
      _resetSectionTracking();
      return alert;
    }
    _sectionTraveled = traveled;
    _sectionLastPoint = fix.point;
    _sectionLastTime = fix.time;
    _lastEndDistance = distanceToEnd;
    final average = _averageKmh(fix);
    final remaining = _remainingFor(active, traveled, fix);
    final needed = _neededAverage(
      active,
      traveled,
      remaining,
      elapsed,
      average,
    );
    _sectionProgress = SectionProgress(
      active,
      remainingMeters: remaining,
      fraction:
          (active.length == null
                  ? (_sectionAt(fix)?.fraction ?? _sectionProgress?.fraction ?? 0)
                  : traveled / active.length!)
              .clamp(0.0, 1.0),
      traveledMeters: traveled,
      elapsedSeconds: elapsed,
      lengthMeters: active.length?.toDouble(),
      averageKmh: average,
      neededAverageKmh: needed,
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

  RadarAlert? evaluate(GpsFix fix) {
    _passedRadar = null;
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
    for (final radar in _index.near(fix.point, 120)) {
      if (!_approached.contains(radar.id) ||
          radar.kind == RadarKind.section) {
        continue;
      }
      if (distanceMeters(fix.point, radar.start) > 70) continue;
      if (bearingDifference(
            fix.heading,
            bearingDegrees(fix.point, radar.start),
          ) <=
          90) {
        continue;
      }
      _approached.remove(radar.id);
      _passedRadar = radar;
      break;
    }
    final sectionEnd = _updateSection(fix, previous);
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
    _approached.add(alert.radar.id);
    _lastAlert = alert;
    _lastAlertAt = fix.time;
    _announced.removeWhere(
      (_, at) => fix.time.difference(at) > const Duration(hours: 1),
    );
    return alert;
  }
}
