import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../model/network_log.dart';

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
  int _counter = 0;
  Timer? _connectivityTimer;

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
  int get errorCount => _logs.where((l) {
        final s = l.statusCode;
        return s == null || s == 0 || s >= 400;
      }).length;

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
    notifyListeners();
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

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    super.dispose();
  }
}
