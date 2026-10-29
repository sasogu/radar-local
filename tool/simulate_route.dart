import 'dart:convert';
import 'dart:io';
import 'package:radar_local/core/alert_engine.dart';
import 'package:radar_local/core/radar.dart';

/// Usage: dart run tool/simulate_route.dart radars.json route.json
/// Route JSON: [{"lat":39.4,"lon":-0.3,"speed":20,"heading":0,
///               "accuracy":8,"seconds":0}, ...]
void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/simulate_route.dart radars.json route.json',
    );
    exitCode = 64;
    return;
  }
  final dataset = RadarDataset.parse(File(args[0]).readAsStringSync());
  final points = jsonDecode(File(args[1]).readAsStringSync()) as List<dynamic>;
  final engine = AlertEngine(dataset);
  final start = DateTime.now();
  for (final row in points.cast<Map<String, dynamic>>()) {
    final fix = GpsFix(
      point: Point(
        (row['lat'] as num).toDouble(),
        (row['lon'] as num).toDouble(),
      ),
      time: start.add(Duration(seconds: (row['seconds'] as num).toInt())),
      speed: (row['speed'] as num).toDouble(),
      heading: (row['heading'] as num).toDouble(),
      accuracy: (row['accuracy'] as num).toDouble(),
      speedAccuracy: (row['speed_accuracy'] as num?)?.toDouble() ?? 1,
      headingAccuracy: (row['heading_accuracy'] as num?)?.toDouble() ?? 5,
    );
    final alert = engine.evaluate(fix);
    if (alert != null) {
      stdout.writeln(
        '${row['seconds']}s ${alert.radar.id} ${alert.distanceMeters.round()}m',
      );
    }
  }
}
