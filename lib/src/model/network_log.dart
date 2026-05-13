/// A single captured HTTP request/response pair.
class NetworkLog {
  /// Unique sequential ID for this log entry.
  final String id;

  /// Uppercase HTTP method: GET, POST, PUT, DELETE, etc.
  final String method;

  /// Full request URL including query parameters.
  final String url;

  /// Request headers sent with the call, if available.
  final Map<String, String>? requestHeaders;

  /// Request body (for POST / PUT / PATCH). May be a [String] or [Map].
  final dynamic requestBody;

  /// HTTP response status code, or `null` if the request failed with an exception.
  final int? statusCode;

  /// Raw response body string.
  final String? responseBody;

  /// When the request was initiated.
  final DateTime timestamp;

  /// Total round-trip time in milliseconds.
  final int durationMs;

  NetworkLog({
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

  /// `true` when [statusCode] is in the 200–299 range.
  bool get isSuccess =>
      statusCode != null && statusCode! >= 200 && statusCode! < 300;

  /// `true` when [statusCode] is in the 400–499 range.
  bool get isClientError =>
      statusCode != null && statusCode! >= 400 && statusCode! < 500;

  /// `true` when [statusCode] is 500 or above.
  bool get isServerError => statusCode != null && statusCode! >= 500;

  /// `true` when the request failed with an exception (no status code).
  bool get isFailed => statusCode == null;
}
