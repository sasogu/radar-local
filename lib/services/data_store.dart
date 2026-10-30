import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../core/radar.dart';

/// Parses a dataset off the UI isolate; large files would otherwise jank.
Future<RadarDataset> parseDataset(String raw) =>
    Isolate.run(() => RadarDataset.parse(raw));

class DataStore {
  DataStore({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  /// Whether the last [load] discarded an unreadable stored dataset and fell
  /// back to the bundled copy.
  bool recoveredFromCorruption = false;

  Future<File> get _file async => File(
    '${(_directory ?? await getApplicationSupportDirectory()).path}/radars.json',
  );

  Future<RadarDataset> load() async {
    recoveredFromCorruption = false;
    final file = await _file;
    if (await file.exists()) {
      try {
        return await parseDataset(await file.readAsString());
      } catch (_) {
        // Keep the damaged file for inspection and never start without data.
        recoveredFromCorruption = true;
        await file.rename('${file.path}.corrupt');
      }
    }
    return parseDataset(
      await rootBundle.loadString('assets/data/spain-radars.json'),
    );
  }

  Future<RadarDataset> replace(RadarDataset data) async {
    final file = await _file;
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(data.encode(), flush: true);
    await temp.rename(file.path);
    final pending = File('${file.path}.pending');
    if (await pending.exists()) await pending.delete();
    return data;
  }

  Future<RadarDataset> stage(RadarDataset data) async {
    final file = await _file;
    final pending = File('${file.path}.pending');
    final temp = File('${pending.path}.tmp');
    await temp.writeAsString(data.encode(), flush: true);
    await temp.rename(pending.path);
    return data;
  }

  Future<RadarDataset?> applyPending() async {
    final file = await _file;
    final pending = File('${file.path}.pending');
    if (!await pending.exists()) return null;
    final RadarDataset parsed;
    try {
      parsed = await parseDataset(await pending.readAsString());
    } catch (_) {
      // A damaged staged update must not replace the active dataset.
      if (await pending.exists()) await pending.delete();
      return null;
    }
    try {
      await pending.rename(file.path);
    } on FileSystemException {
      // Another activation may have renamed the same pending file.
      if (await pending.exists()) rethrow;
    }
    return parsed;
  }
}
