import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_local/core/radar.dart';
import 'package:radar_local/services/data_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'staged update does not replace the active dataset until applied',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'radar-local-test-',
      );
      try {
        final store = DataStore(directory: directory);
        final original = File(
          'assets/data/example-radars.json',
        ).readAsStringSync();
        final initialCount =
            ((jsonDecode(original) as Map<String, dynamic>)['radars'] as List)
                .length;
        await store.replace(RadarDataset.parse(original));
        final candidate = jsonDecode(original) as Map<String, dynamic>;
        (candidate['radars'] as List).add({
          'id': 'test-extra',
          'kind': 'fixed',
          'start': {'lat': 39.48, 'lon': -0.38},
        });
        await store.stage(RadarDataset.parse(jsonEncode(candidate)));
        expect((await store.load()).radars.length, initialCount);
        expect((await store.applyPending())?.radars.length, initialCount + 1);
        expect((await store.load()).radars.length, initialCount + 1);
        expect(await store.applyPending(), isNull);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('manual replacement discards an older staged update', () async {
    final directory = await Directory.systemTemp.createTemp(
      'radar-local-test-',
    );
    try {
      final store = DataStore(directory: directory);
      final original = File(
        'assets/data/example-radars.json',
      ).readAsStringSync();
      final dataset = RadarDataset.parse(original);
      await store.stage(dataset);
      await store.replace(dataset);
      expect(await store.applyPending(), isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('damaged stored data falls back to the bundled dataset', () async {
    final directory = await Directory.systemTemp.createTemp(
      'radar-local-test-',
    );
    try {
      File('${directory.path}/radars.json').writeAsStringSync('{"schema":');
      File('${directory.path}/radars.json.pending').writeAsStringSync('[]');
      final store = DataStore(directory: directory);
      expect(await store.applyPending(), isNull);
      expect(File('${directory.path}/radars.json.pending').existsSync(), false);
      expect((await store.load()).radars.length, greaterThan(1000));
      expect(store.recoveredFromCorruption, isTrue);
      expect(File('${directory.path}/radars.json.corrupt').existsSync(), true);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
