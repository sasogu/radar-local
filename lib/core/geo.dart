import 'dart:math' as math;
import 'radar.dart';

const _earthRadius = 6371000.0;
double _radians(double degrees) => degrees * math.pi / 180;

double distanceMeters(Point a, Point b) {
  final dLat = _radians(b.lat - a.lat);
  final dLon = _radians(b.lon - a.lon);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radians(a.lat)) *
          math.cos(_radians(b.lat)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadius * math.asin(math.min(1, math.sqrt(h)));
}

double bearingDegrees(Point a, Point b) {
  final lat1 = _radians(a.lat);
  final lat2 = _radians(b.lat);
  final dLon = _radians(b.lon - a.lon);
  final y = math.sin(dLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

double bearingDifference(double a, double b) =>
    ((a - b + 540) % 360 - 180).abs();

class SegmentProjection {
  const SegmentProjection(this.distanceMeters, this.fraction);

  /// Distance from the point to the closest point on the segment.
  final double distanceMeters;

  /// Position along the segment: 0 at [a], 1 at [b]. Not clamped, so values
  /// outside 0..1 mean the point lies before the start or past the end.
  final double fraction;
}

/// Projects [p] onto the segment [a]–[b] using a local flat approximation.
SegmentProjection projectOnSegment(Point p, Point a, Point b) {
  final latRef = (a.lat + b.lat) / 2;
  final kx = 111320 * math.cos(_radians(latRef));
  const ky = 110540.0;
  final bx = (b.lon - a.lon) * kx;
  final by = (b.lat - a.lat) * ky;
  final px = (p.lon - a.lon) * kx;
  final py = (p.lat - a.lat) * ky;
  final lengthSquared = bx * bx + by * by;
  final fraction = lengthSquared == 0 ? 0.0 : (px * bx + py * by) / lengthSquared;
  final t = fraction.clamp(0.0, 1.0);
  final dx = px - bx * t;
  final dy = py - by * t;
  return SegmentProjection(math.sqrt(dx * dx + dy * dy), fraction);
}

/// A coarse grid. Exact distance is still checked after lookup.
class RadarIndex {
  RadarIndex(Iterable<Radar> radars) {
    for (final radar in radars) {
      final key = _key(radar.start);
      _cells.putIfAbsent(key, () => []).add(radar);
    }
  }
  final Map<String, List<Radar>> _cells = {};
  static const cellDegrees = 0.01;
  String _key(Point p) =>
      '${(p.lat / cellDegrees).floor()}:${(p.lon / cellDegrees).floor()}';

  Iterable<Radar> near(Point p, double radiusMeters) sync* {
    final latSpan = radiusMeters / 111000;
    final lonSpan =
        radiusMeters / (111000 * math.max(0.05, math.cos(_radians(p.lat))));
    final minLat = ((p.lat - latSpan) / cellDegrees).floor();
    final maxLat = ((p.lat + latSpan) / cellDegrees).floor();
    final minLon = ((p.lon - lonSpan) / cellDegrees).floor();
    final maxLon = ((p.lon + lonSpan) / cellDegrees).floor();
    for (var lat = minLat; lat <= maxLat; lat++) {
      for (var lon = minLon; lon <= maxLon; lon++) {
        for (final radar in _cells['$lat:$lon'] ?? const <Radar>[]) {
          if (distanceMeters(p, radar.start) <= radiusMeters) yield radar;
        }
      }
    }
  }
}
