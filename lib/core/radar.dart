import 'dart:convert';

enum RadarKind { fixed, redLight, section, phone }

class Point {
  const Point(this.lat, this.lon);
  final double lat;
  final double lon;

  factory Point.fromJson(Map<String, dynamic> json) =>
      Point((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble());
  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};
}

class Radar {
  const Radar({
    required this.id,
    required this.kind,
    required this.start,
    this.end,
    this.direction,
    this.speedLimit,
    this.name = '',
  });
  final String id;
  final RadarKind kind;
  final Point start;
  final Point? end;

  /// Direction of vehicle travel in degrees clockwise from north.
  final double? direction;
  final int? speedLimit;
  final String name;

  factory Radar.fromJson(Map<String, dynamic> json) {
    final kind = RadarKind.values.byName(json['kind'] as String);
    final radar = Radar(
      id: json['id'] as String,
      kind: kind,
      start: Point.fromJson(json['start'] as Map<String, dynamic>),
      end: json['end'] == null
          ? null
          : Point.fromJson(json['end'] as Map<String, dynamic>),
      direction: (json['direction'] as num?)?.toDouble(),
      speedLimit: (json['speed_limit'] as num?)?.toInt(),
      name: (json['name'] as String?) ?? '',
    );
    radar.validate();
    return radar;
  }

  void validate() {
    if (id.trim().isEmpty ||
        id.length > 120 ||
        name.length > 200 ||
        start.lat.abs() > 90 ||
        start.lon.abs() > 180 ||
        !start.lat.isFinite ||
        !start.lon.isFinite ||
        (end != null &&
            (end!.lat.abs() > 90 ||
                end!.lon.abs() > 180 ||
                !end!.lat.isFinite ||
                !end!.lon.isFinite)) ||
        (kind == RadarKind.section && end == null) ||
        (direction != null &&
            (!direction!.isFinite || direction! < 0 || direction! >= 360)) ||
        (speedLimit != null && (speedLimit! < 10 || speedLimit! > 180))) {
      throw const FormatException('Invalid radar entry');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'start': start.toJson(),
    if (end != null) 'end': end!.toJson(),
    if (direction != null) 'direction': direction,
    if (speedLimit != null) 'speed_limit': speedLimit,
    if (name.isNotEmpty) 'name': name,
  };
}

class RadarDataset {
  const RadarDataset(
    this.radars, {
    required this.source,
    required this.updatedAt,
  });
  final List<Radar> radars;
  final String source;
  final DateTime updatedAt;

  factory RadarDataset.parse(String raw) {
    if (utf8.encode(raw).length > 10 * 1024 * 1024) {
      throw const FormatException('Dataset too large');
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['schema'] != 1) throw const FormatException('Unsupported schema');
    final entries = json['radars'] as List<dynamic>;
    if (entries.length > 100000) throw const FormatException('Too many radars');
    final radars = entries
        .map((e) => Radar.fromJson(e as Map<String, dynamic>))
        .toList();
    if (radars.map((e) => e.id).toSet().length != radars.length) {
      throw const FormatException('Duplicate radar IDs');
    }
    return RadarDataset(
      radars,
      source: json['source'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  String encode() => jsonEncode({
    'schema': 1,
    'source': source,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'radars': radars.map((r) => r.toJson()).toList(),
  });
}
