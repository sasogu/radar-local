import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_local/services/data_store.dart';

void main() {
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
        await store.replace(original);
        final candidate = jsonDecode(original) as Map<String, dynamic>;
        (candidate['radars'] as List).add({
          'id': 'test-extra',
          'kind': 'fixed',
          'start': {'lat': 39.48, 'lon': -0.38},
        });
        await store.stage(jsonEncode(candidate));
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
      await store.stage(original);
      await store.replace(original);
      expect(await store.applyPending(), isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
