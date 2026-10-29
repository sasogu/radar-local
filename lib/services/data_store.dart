import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../core/radar.dart';

class DataStore {
  DataStore({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  Future<File> get _file async => File(
    '${(_directory ?? await getApplicationSupportDirectory()).path}/radars.json',
  );

  Future<RadarDataset> load() async {
    final file = await _file;
    if (!await file.exists()) {
      return RadarDataset.parse(
        await rootBundle.loadString('assets/data/spain-radars.json'),
      );
    }
    return RadarDataset.parse(await file.readAsString());
  }

  Future<RadarDataset> replace(String raw) async {
    final parsed = RadarDataset.parse(raw);
    final file = await _file;
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(parsed.encode(), flush: true);
    await temp.rename(file.path);
    final pending = File('${file.path}.pending');
    if (await pending.exists()) await pending.delete();
    return parsed;
  }

  Future<RadarDataset> stage(String raw) async {
    final parsed = RadarDataset.parse(raw);
    final file = await _file;
    final pending = File('${file.path}.pending');
    final temp = File('${pending.path}.tmp');
    await temp.writeAsString(parsed.encode(), flush: true);
    await temp.rename(pending.path);
    return parsed;
  }

  Future<RadarDataset?> applyPending() async {
    final file = await _file;
    final pending = File('${file.path}.pending');
    if (!await pending.exists()) return null;
    final parsed = RadarDataset.parse(await pending.readAsString());
    try {
      await pending.rename(file.path);
    } on FileSystemException {
      // Another activation may have renamed the same pending file.
      if (await pending.exists()) rethrow;
    }
    return parsed;
  }
}
