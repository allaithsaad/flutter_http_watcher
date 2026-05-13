import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/network_logger.dart';

/// An [http.BaseClient] that automatically logs every request to [HttpWatcherLogger].
///
/// ```dart
/// final client = HttpWatcherClient();
/// final response = await client.get(Uri.parse('https://api.example.com/users'));
/// ```
///
/// Or wrap an existing client:
/// ```dart
/// final client = HttpWatcherClient(http.Client());
/// ```
class HttpWatcherClient extends http.BaseClient {
  final http.Client _inner;

  HttpWatcherClient([http.Client? inner]) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final start = DateTime.now();
    String? requestBody;
    if (request is http.Request) {
      requestBody = request.body;
    }

    final streamed = await _inner.send(request);

    // Buffer response bytes so we can log the body and still return a valid stream.
    final bytes = await streamed.stream.toBytes();
    final responseBody = utf8.decode(bytes, allowMalformed: true);

    HttpWatcherLogger.instance.logRequest(
      method: request.method,
      url: request.url.toString(),
      headers: Map<String, String>.from(request.headers),
      body: requestBody,
      statusCode: streamed.statusCode,
      responseBody: responseBody,
      startTime: start,
    );

    return http.StreamedResponse(
      Stream.value(bytes),
      streamed.statusCode,
      headers: streamed.headers,
      reasonPhrase: streamed.reasonPhrase,
      request: streamed.request,
      contentLength: bytes.length,
    );
  }

  @override
  void close() => _inner.close();
}
