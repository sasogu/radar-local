import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../core/radar.dart';

class DataStore {
  Future<File> get _file async =>
      File('${(await getApplicationSupportDirectory()).path}/radars.json');

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
    return parsed;
  }
}
