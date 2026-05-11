/// A single captured HTTP request and its response.
class NetworkLog {
  /// Unique ID for this log entry.
  final String id;

  /// HTTP method: GET, POST, PUT, DELETE, etc.
  final String method;

  /// Full request URL.
  final String url;

  /// Request headers sent with the call.
  final Map<String, String>? requestHeaders;

  /// Request body (for POST / PUT / DELETE).
  final dynamic requestBody;

  /// HTTP response status code, or null if the request failed.
  final int? statusCode;

  /// Raw response body string.
  final String? responseBody;

  /// When the request was initiated.
  final DateTime timestamp;

  /// Round-trip time in milliseconds.
  final int durationMs;

  const NetworkLog({
    required this.id,
    required this.method,
    required this.url,
    this.requestHeaders,
    this.requestBody,
    this.statusCode,
    this.responseBody,
    required this.timestamp,
    required this.durationMs,
  });

  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 300;
  bool get isClientError => statusCode != null && statusCode! >= 400 && statusCode! < 500;
  bool get isServerError => statusCode != null && statusCode! >= 500;
  bool get isFailed => statusCode == null;
}
