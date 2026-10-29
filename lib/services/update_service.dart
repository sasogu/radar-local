import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/radar.dart';
import 'data_store.dart';

class UpdateService {
  UpdateService(this.store);
  final DataStore store;

  Future<RadarDataset> download(String address) async {
    final data = await fetch(address);
    return store.replace(data.encode());
  }

  Future<RadarDataset> fetch(String address) async {
    final uri = Uri.tryParse(address);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('HTTPS URL required');
    }
    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      request.followRedirects = false;
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (streamed.statusCode != 200) {
        throw HttpException('HTTP ${streamed.statusCode}');
      }
      var bytes = 0;
      final chunks = <int>[];
      await for (final chunk in streamed.stream.timeout(
        const Duration(seconds: 20),
      )) {
        bytes += chunk.length;
        if (bytes > 10 * 1024 * 1024) {
          throw const FormatException('Dataset too large');
        }
        chunks.addAll(chunk);
      }
      return RadarDataset.parse(utf8.decode(chunks));
    } finally {
      client.close();
    }
  }
}

class HttpException implements Exception {
  const HttpException(this.message);
  final String message;
  @override
  String toString() => message;
}
