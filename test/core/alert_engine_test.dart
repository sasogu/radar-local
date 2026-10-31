import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_local/core/alert_engine.dart';
import 'package:radar_local/core/geo.dart';
import 'package:radar_local/core/radar.dart';

void main() {
  final radar = Radar(
    id: 'A',
    kind: RadarKind.fixed,
    start: const Point(39.47, -0.37),
    direction: 0,
  );
  final dataset = RadarDataset(
    [radar],
    source: 'test',
    updatedAt: DateTime.utc(2026),
  );
  GpsFix fix({
    double lat = 39.4675,
    double lon = -0.37,
    double heading = 0,
    double accuracy = 8,
    double speed = 20,
    DateTime? time,
  }) => GpsFix(
    point: Point(lat, lon),
    time: time ?? DateTime.now(),
    accuracy: accuracy,
    speed: speed,
    heading: heading,
    speedAccuracy: 1,
    headingAccuracy: 5,
  );

  test('distance, bearing, and grid lookup', () {
    expect(
      distanceMeters(const Point(39.465, -0.37), radar.start),
      closeTo(556, 5),
    );
    expect(
      bearingDegrees(const Point(39.465, -0.37), radar.start),
      closeTo(0, 1),
    );
    expect(RadarIndex([radar]).near(const Point(39.465, -0.37), 600).length, 1);
    expect(RadarIndex([radar]).near(const Point(39.465, -0.37), 400).length, 0);
  });
  test('warns once on reliable approach', () {
    final engine = AlertEngine(dataset);
    final first = fix();
    expect(engine.evaluate(first)?.radar.id, 'A');
    expect(
      engine.evaluate(fix(time: first.time.add(const Duration(seconds: 2)))),
      isNull,
    );
  });
  test('rejects opposite travel, poor accuracy, stationary fixes', () {
    expect(AlertEngine(dataset).evaluate(fix(heading: 180)), isNull);
    expect(AlertEngine(dataset).evaluate(fix(accuracy: 80)), isNull);
    expect(AlertEngine(dataset).evaluate(fix(speed: 0)), isNull);
  });
  test('section start wins priority', () {
    final section = Radar(
      id: 'S',
      kind: RadarKind.section,
      start: const Point(39.4702, -0.37),
      end: const Point(39.49, -0.37),
      direction: 0,
    );
    final engine = AlertEngine(
      RadarDataset([radar, section], source: 'test', updatedAt: DateTime.now()),
    );
    expect(engine.evaluate(fix())?.radar.id, 'S');
  });
  test('finds the speed limit ahead', () {
    final limited = Radar(
      id: 'L',
      kind: RadarKind.fixed,
      start: radar.start,
      direction: 0,
      speedLimit: 90,
    );
    final engine = AlertEngine(
      RadarDataset([limited], source: 'test', updatedAt: DateTime.now()),
    );
    expect(engine.limitAhead(fix())?.speedLimit, 90);
  });
  test('ignores limits behind or without a limit', () {
    final behind = Radar(
      id: 'B',
      kind: RadarKind.fixed,
      start: radar.start,
      direction: 180,
      speedLimit: 90,
    );
    final unlimited = Radar(
      id: 'U',
      kind: RadarKind.fixed,
      start: radar.start,
      direction: 0,
    );
    expect(
      AlertEngine(
        RadarDataset([behind], source: 'test', updatedAt: DateTime.now()),
      ).limitAhead(fix()),
      isNull,
    );
    expect(
      AlertEngine(
        RadarDataset([unlimited], source: 'test', updatedAt: DateTime.now()),
      ).limitAhead(fix()),
      isNull,
    );
  });
  test('alerts on a phone control camera', () {
    final phone = Radar(
      id: 'P',
      kind: RadarKind.phone,
      start: const Point(39.47, -0.37),
      direction: 0,
    );
    final engine = AlertEngine(
      RadarDataset([phone], source: 'test', updatedAt: DateTime.now()),
    );
    expect(engine.evaluate(fix())?.radar.kind, RadarKind.phone);
    expect(RadarKind.values.byName('phone'), RadarKind.phone);
  });
  test('does not repeat an alert at the same site', () {
    final phone = Radar(
      id: 'P',
      kind: RadarKind.phone,
      start: radar.start,
      direction: 0,
    );
    final engine = AlertEngine(
      RadarDataset([radar, phone], source: 'test', updatedAt: DateTime.now()),
    );
    final first = fix();
    expect(engine.evaluate(first), isNotNull);
    expect(
      engine.evaluate(fix(time: first.time.add(const Duration(seconds: 2)))),
      isNull,
    );
  });
  test('imminent fixed radar wins over section', () {
    final section = Radar(
      id: 'S',
      kind: RadarKind.section,
      start: const Point(39.472, -0.37),
      end: const Point(39.49, -0.37),
      direction: 0,
    );
    final engine = AlertEngine(
      RadarDataset([radar, section], source: 'test', updatedAt: DateTime.now()),
    );
    expect(engine.evaluate(fix(lat: 39.4695))?.radar.id, 'A');
  });
  test('tracks a section and announces its end once', () {
    final section = Radar(
      id: 'S',
      kind: RadarKind.section,
      start: const Point(39.4700, -0.37),
      end: const Point(39.4709, -0.37),
      direction: 0,
      speedLimit: 90,
    );
    final engine = AlertEngine(
      RadarDataset([section], source: 'test', updatedAt: DateTime.now()),
    );
    final now = DateTime.now();
    engine.evaluate(fix(lat: 39.4701, time: now.add(const Duration(seconds: 2))));
    expect(engine.sectionProgress?.radar.id, 'S');
    expect(engine.sectionProgress!.remainingMeters, closeTo(89, 15));
    expect(engine.sectionProgress!.radar.speedLimit, 90);
    final end = engine.evaluate(
      fix(lat: 39.4710, time: now.add(const Duration(seconds: 4))),
    );
    expect(end?.phase, AlertPhase.sectionEnd);
    expect(engine.sectionProgress, isNull);
    expect(
      engine.evaluate(
        fix(lat: 39.4711, time: now.add(const Duration(seconds: 6))),
      ),
      isNull,
    );
  });
  test('estimates the section average and warns only once', () {
    final section = Radar(
      id: 'S',
      kind: RadarKind.section,
      start: const Point(39.4700, -0.37),
      end: const Point(39.4850, -0.37),
      direction: 0,
      speedLimit: 60,
    );
    final engine = AlertEngine(
      RadarDataset([section], source: 'test', updatedAt: DateTime.now()),
    );
    final now = DateTime.now();
    var lat = 39.4701;
    engine.evaluate(fix(lat: lat, time: now.add(const Duration(seconds: 2))));
    AlertPhase? warning;
    for (var i = 4; i <= 14; i += 2) {
      lat += 0.00036;
      final alert = engine.evaluate(
        fix(lat: lat, time: now.add(Duration(seconds: i))),
      );
      if (alert?.phase == AlertPhase.sectionAverage) warning = alert!.phase;
    }
    expect(engine.sectionProgress, isNotNull);
    expect(engine.sectionProgress!.averageKmh, closeTo(72, 3));
    expect(warning, AlertPhase.sectionAverage);
    lat += 0.00036;
    final later = engine.evaluate(
      fix(lat: lat, time: now.add(const Duration(seconds: 15))),
    );
    expect(later?.phase, isNot(AlertPhase.sectionAverage));
  });
  test('does not track a section in the opposite direction', () {
    final section = Radar(
      id: 'S',
      kind: RadarKind.section,
      start: const Point(39.4700, -0.37),
      end: const Point(39.4900, -0.37),
      direction: 0,
    );
    final engine = AlertEngine(
      RadarDataset([section], source: 'test', updatedAt: DateTime.now()),
    );
    engine.evaluate(fix(lat: 39.475, heading: 180));
    expect(engine.sectionProgress, isNull);
  });
  test('validates dataset and duplicate ids', () {
    expect(
      () => RadarDataset.parse('{"schema":2,"radars":[]}'),
      throwsFormatException,
    );
    final duplicate = RadarDataset(
      [radar, radar],
      source: 'test',
      updatedAt: DateTime.now(),
    ).encode();
    expect(() => RadarDataset.parse(duplicate), throwsFormatException);
    expect(RadarDataset.parse(dataset.encode()).radars.single.id, 'A');
  });
  test('skips radar kinds from newer app versions', () {
    final parsed = RadarDataset.parse(
      jsonEncode({
        'schema': 1,
        'source': 'test',
        'updated_at': '2026-10-30T00:00:00Z',
        'radars': [
          radar.toJson(),
          {
            'id': 'F',
            'kind': 'futureKind',
            'start': {'lat': 39.47, 'lon': -0.37},
          },
        ],
      }),
    );
    expect(parsed.radars.single.id, 'A');
  });
  test('alerts on solid-line and stop cameras', () {
    final camera = Radar(
      id: 'L',
      kind: RadarKind.lineStop,
      start: const Point(39.47, -0.37),
      direction: 0,
    );
    final engine = AlertEngine(
      RadarDataset([camera], source: 'test', updatedAt: DateTime.now()),
    );
    expect(engine.evaluate(fix())?.radar.kind, RadarKind.lineStop);
    expect(RadarKind.values.byName('lineStop'), RadarKind.lineStop);
  });
}
