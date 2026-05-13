import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../model/network_log.dart';

enum NetworkStatus { online, offline, unknown }

/// Central store for all captured network logs.
///
/// Access via [HttpWatcherLogger.instance]. Call [logRequest] after every HTTP
/// response. Wrap your app with [NetworkInspectorOverlay] to display the
/// floating debug button.
class HttpWatcherLogger extends ChangeNotifier {
  HttpWatcherLogger._() {
    if (kDebugMode && !kIsWeb) _startConnectivityPolling();
  }

  static final HttpWatcherLogger instance = HttpWatcherLogger._();

  final List<NetworkLog> _logs = [];
  int _counter = 0;
  Timer? _connectivityTimer;

  /// Current network connectivity status.
  NetworkStatus networkStatus = NetworkStatus.unknown;

  /// Set to `false` to disable logging without removing the overlay.
  bool enabled = true;

  /// Whether the inspector UI uses dark mode. Defaults to `true`.
  bool isDark = true;

  /// Maximum number of entries kept in memory. Defaults to 300.
  int maxEntries = 300;

  /// All captured logs, newest first.
  List<NetworkLog> get logs => List.unmodifiable(_logs);

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
  /// No-op in release builds or when [enabled] is `false`.
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

  /// Toggle between dark and light inspector theme.
  void toggleTheme() {
    isDark = !isDark;
    notifyListeners();
  }

  /// Toggle request logging on/off.
  void toggleEnabled() {
    enabled = !enabled;
    notifyListeners();
  }

  /// Remove all stored logs.
  void clear() {
    _logs.clear();
    notifyListeners();
  }

  /// Stop the connectivity polling timer.
  @override
  void dispose() {
    _connectivityTimer?.cancel();
    super.dispose();
  }
}
