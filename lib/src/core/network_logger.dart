import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../model/network_log.dart';
import 'watcher_web_server.dart';

/// Current network connectivity state.
enum NetworkStatus {
  /// Device has an active internet connection.
  online,

  /// Device has no internet connection.
  offline,

  /// Connectivity has not been determined yet.
  unknown,
}

/// Central store for all captured HTTP logs.
///
/// Access the singleton via [HttpWatcherLogger.instance].
/// Call [logRequest] after every HTTP response.
/// Wrap your app with [HttpWatcherOverlay] to display the floating button.
///
/// ```dart
/// HttpWatcherLogger.instance.logRequest(
///   method: 'GET',
///   url: 'https://api.example.com/users',
///   statusCode: 200,
///   responseBody: responseBody,
///   startTime: start,
/// );
/// ```
class HttpWatcherLogger extends ChangeNotifier {
  HttpWatcherLogger._() {
    if (!kIsWeb) _startConnectivityPolling();
  }

  /// The global singleton instance.
  static final HttpWatcherLogger instance = HttpWatcherLogger._();

  final List<NetworkLog> _logs = [];
  final _webServer = WatcherWebServer();
  int _counter = 0;
  Timer? _connectivityTimer;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Current network connectivity status.
  NetworkStatus networkStatus = NetworkStatus.unknown;

  /// Set to `false` to pause logging without removing the overlay.
  bool enabled = true;

  /// Whether the inspector UI uses dark mode. Defaults to `true`.
  bool isDark = true;

  /// Maximum number of log entries kept in memory. Defaults to 300.
  int maxEntries = 300;

  /// All captured logs, newest first. Returns an unmodifiable view.
  List<NetworkLog> get logs => List.unmodifiable(_logs);

  /// Count of error responses: 4xx, 5xx, network failures, or status 0.
  /// Requests still in flight (pending) are not counted.
  int get errorCount => _logs.where((l) {
        if (l.pending) return false;
        final s = l.statusCode;
        return s == null || s == 0 || s >= 400;
      }).length;

  /// Dispatches a change notification off the current call stack.
  ///
  /// Logging calls come from wherever the app makes its HTTP requests, which
  /// includes `initState`, `build`, and controller `onInit` — all of which run
  /// while the framework is building the widget tree. Notifying synchronously
  /// from there would call `setState` on the overlay mid-build and trip
  /// "setState() or markNeedsBuild() called during build".
  ///
  /// A build scope is always synchronous, so a microtask is guaranteed to run
  /// after it has fully unwound. Bursts of logs collapse into one notification.
  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _startConnectivityPolling() {
    _checkConnectivity();
    _connectivityTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkConnectivity(),
    );
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      final isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      _updateStatus(isOnline ? NetworkStatus.online : NetworkStatus.offline);
    } catch (_) {
      _updateStatus(NetworkStatus.offline);
    }
  }

  void _updateStatus(NetworkStatus status) {
    if (networkStatus == status) return;
    networkStatus = status;
    notifyListeners();
  }

  /// Log a completed HTTP request/response pair.
  ///
  /// No-op when [enabled] is `false`.
  ///
  /// [method] should be an uppercase HTTP verb (GET, POST, etc.).
  /// [startTime] is when the request was initiated; duration is computed automatically.
  void logRequest({
    required String method,
    required String url,
    Map<String, String>? headers,
    dynamic body,
    required int statusCode,
    required String responseBody,
    required DateTime startTime,
  }) {
    if (!enabled) return;
    _logs.insert(
      0,
      NetworkLog(
        id: '${++_counter}',
        method: method.toUpperCase(),
        url: url,
        requestHeaders: headers,
        requestBody: body,
        statusCode: statusCode,
        responseBody: responseBody,
        timestamp: startTime,
        durationMs: DateTime.now().difference(startTime).inMilliseconds,
      ),
    );
    if (_logs.length > maxEntries) _logs.removeLast();
    _scheduleNotify();
  }

  /// Log the **start** of an HTTP request, before the response arrives.
  ///
  /// The entry appears immediately in the inspector marked as *pending*. Pass
  /// the returned id to [logResponse] (or [failRequest]) once the request
  /// completes to fill in the status, body, and duration.
  ///
  /// Returns the new log's id, or `null` when [enabled] is `false`.
  ///
  /// ```dart
  /// final id = HttpWatcherLogger.instance.logRequestStart(
  ///   method: 'GET',
  ///   url: uri.toString(),
  /// );
  /// final res = await http.get(uri);
  /// HttpWatcherLogger.instance.logResponse(
  ///   id: id!,
  ///   statusCode: res.statusCode,
  ///   responseBody: res.body,
  /// );
  /// ```
  String? logRequestStart({
    required String method,
    required String url,
    Map<String, String>? headers,
    dynamic body,
    DateTime? startTime,
  }) {
    if (!enabled) return null;
    final id = '${++_counter}';
    _logs.insert(
      0,
      NetworkLog(
        id: id,
        method: method.toUpperCase(),
        url: url,
        requestHeaders: headers,
        requestBody: body,
        timestamp: startTime ?? DateTime.now(),
        pending: true,
      ),
    );
    if (_logs.length > maxEntries) _logs.removeLast();
    _scheduleNotify();
    return id;
  }

  /// Complete a pending request previously created by [logRequestStart].
  ///
  /// Fills in the response and computes the duration from the entry's start
  /// time. No-op if no pending entry with [id] exists (it may have been cleared
  /// or evicted). Pass `statusCode: null` for a failed request.
  void logResponse({
    required String id,
    int? statusCode,
    String? responseBody,
  }) {
    final log = _logByIdOrNull(id);
    if (log == null) return;
    log.statusCode = statusCode;
    log.responseBody = responseBody;
    log.durationMs = DateTime.now().difference(log.timestamp).inMilliseconds;
    log.pending = false;
    _scheduleNotify();
  }

  /// Mark a pending request as failed (no status code), e.g. on a network
  /// exception. Convenience wrapper over [logResponse].
  void failRequest({required String id, String? error}) {
    logResponse(id: id, statusCode: null, responseBody: error);
  }

  NetworkLog? _logByIdOrNull(String id) {
    for (final l in _logs) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Toggle request logging on/off.
  void toggleEnabled() {
    enabled = !enabled;
    notifyListeners();
  }

  /// Toggle between dark and light inspector theme.
  void toggleTheme() {
    isDark = !isDark;
    notifyListeners();
  }

  /// Remove all stored logs.
  void clear() {
    _logs.clear();
    notifyListeners();
  }

  /// Whether the web viewer server is currently running.
  bool get webServerRunning => _webServer.isRunning;

  /// Local network URL of the web viewer, or `null` if not started.
  String? get webServerUrl => _webServer.url;

  /// True if the server started on loopback (127.0.0.1) — not reachable from other devices.
  bool get webServerIsLoopback => _webServer.isLoopback;

  /// The last error from [startWebServer], or `null` if it succeeded.
  String? get webServerLastError => _webServer.lastError;

  /// Starts the web viewer server and returns its URL, or `null` on failure.
  Future<String?> startWebServer() async {
    final url = await _webServer.start(() => _logs);
    notifyListeners();
    return url;
  }

  /// Stops the web viewer server.
  Future<void> stopWebServer() async {
    await _webServer.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connectivityTimer?.cancel();
    super.dispose();
  }
}
