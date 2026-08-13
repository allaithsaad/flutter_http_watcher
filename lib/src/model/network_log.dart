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

  /// HTTP response status code, or `null` while [pending] or if the request
  /// failed with an exception.
  int? statusCode;

  /// Raw response body string. `null` until the response arrives.
  String? responseBody;

  /// When the request was initiated.
  final DateTime timestamp;

  /// Total round-trip time in milliseconds. `0` while still [pending].
  int durationMs;

  /// `true` while the request is in flight — logged at start, awaiting a
  /// response. Set to `false` once a response or error is recorded.
  bool pending;

  NetworkLog({
    required this.id,
    required this.method,
    required this.url,
    this.requestHeaders,
    this.requestBody,
    this.statusCode,
    this.responseBody,
    required this.timestamp,
    this.durationMs = 0,
    this.pending = false,
  });

  /// `true` while the request is in flight and no response has arrived yet.
  bool get isPending => pending;

  /// `true` when [statusCode] is in the 200–299 range.
  bool get isSuccess =>
      !pending && statusCode != null && statusCode! >= 200 && statusCode! < 300;

  /// `true` when [statusCode] is in the 400–499 range.
  bool get isClientError =>
      !pending && statusCode != null && statusCode! >= 400 && statusCode! < 500;

  /// `true` when [statusCode] is 500 or above.
  bool get isServerError =>
      !pending && statusCode != null && statusCode! >= 500;

  /// `true` when the request failed with an exception (no status code) after
  /// completing. A [pending] request is not considered failed.
  bool get isFailed => !pending && statusCode == null;
}
