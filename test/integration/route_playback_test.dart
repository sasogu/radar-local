import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_local/core/alert_engine.dart';
import 'package:radar_local/core/radar.dart';

void main() {
  test('bundled official Madrid snapshot validates', () {
    final dataset = RadarDataset.parse(
      File('assets/data/madrid-radars.json').readAsStringSync(),
    );
    expect(dataset.radars.length, 36);
    expect(dataset.radars.where((r) => r.kind == RadarKind.section).length, 9);
  });
  test('JSON dataset and GPS route produce one alert', () {
    final dataset = RadarDataset.parse(
      File('assets/data/example-radars.json').readAsStringSync(),
    );
    final route =
        (jsonDecode(File('assets/data/example-route.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();
    final engine = AlertEngine(dataset);
    final start = DateTime.now();
    final alerts = <String>[];
    for (final row in route) {
      final fix = GpsFix(
        point: Point(
          (row['lat'] as num).toDouble(),
          (row['lon'] as num).toDouble(),
        ),
        time: start.add(Duration(seconds: (row['seconds'] as num).toInt())),
        speed: (row['speed'] as num).toDouble(),
        heading: (row['heading'] as num).toDouble(),
        accuracy: (row['accuracy'] as num).toDouble(),
        speedAccuracy: 1,
        headingAccuracy: 5,
      );
      final alert = engine.evaluate(fix);
      if (alert != null) alerts.add(alert.radar.id);
    }
    expect(alerts, ['example-1']);
  });
}
