import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_local/core/radar.dart';
import 'package:radar_local/services/dataset_signature.dart';

void main() {
  // Fails when the published dataset changes without `tool/sign_dataset.sh`.
  test('published dataset carries a valid signature', () async {
    final data = File('assets/data/spain-radars.json').readAsBytesSync();
    final signature = File(
      'assets/data/spain-radars.json.sig',
    ).readAsStringSync();
    expect(await verifyDatasetSignature(data, signature), isTrue);
    final tampered = [...data]..[data.length ~/ 2] ^= 1;
    expect(await verifyDatasetSignature(tampered, signature), isFalse);
    expect(await verifyDatasetSignature(data, 'not base64!'), isFalse);
  });

  test('suspicious replacements are rejected', () {
    Radar radar(int i) => Radar(
      id: '$i',
      kind: RadarKind.fixed,
      start: Point(39 + i / 1000, -0.37),
    );
    final current = RadarDataset(
      List.generate(10, radar),
      source: 'test',
      updatedAt: DateTime.utc(2026, 10, 30),
    );
    final shrunk = RadarDataset(
      List.generate(7, radar),
      source: 'test',
      updatedAt: DateTime.utc(2026, 11, 1),
    );
    final older = RadarDataset(
      List.generate(10, radar),
      source: 'test',
      updatedAt: DateTime.utc(2026, 10, 1),
    );
    final newer = RadarDataset(
      List.generate(9, radar),
      source: 'test',
      updatedAt: DateTime.utc(2026, 11, 1),
    );
    expect(() => shrunk.checkReplaces(current), throwsFormatException);
    expect(() => older.checkReplaces(current), throwsFormatException);
    newer.checkReplaces(current);
    expect(
      () => RadarDataset.parse(
        '{"schema":1,"source":"x","updated_at":"2026-10-30T00:00:00Z","radars":[]}',
      ),
      throwsFormatException,
    );
  });
}
