import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/radar.dart';
import 'data_store.dart';
import 'dataset_signature.dart';
import 'settings.dart';

class UpdateService {
  /// Downloads a dataset. The default GitHub source must carry a valid
  /// Ed25519 signature in `<url>.sig`; user-configured URLs are trusted as
  /// the user confirmed them.
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
      final bytes = await _get(client, uri, 10 * 1024 * 1024);
      if (address == defaultRadarUpdateUrl) {
        final signature = await _get(client, Uri.parse('$address.sig'), 1024);
        if (!await verifyDatasetSignature(bytes, utf8.decode(signature))) {
          throw const FormatException('Invalid dataset signature');
        }
      }
      return parseDataset(utf8.decode(bytes));
    } finally {
      client.close();
    }
  }

  Future<List<int>> _get(http.Client client, Uri uri, int maxBytes) async {
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
      if (bytes > maxBytes) {
        throw const FormatException('Dataset too large');
      }
      chunks.addAll(chunk);
    }
    return chunks;
  }
}

class HttpException implements Exception {
  const HttpException(this.message);
  final String message;
  @override
  String toString() => message;
}
