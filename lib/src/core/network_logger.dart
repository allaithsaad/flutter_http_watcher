import 'package:flutter/foundation.dart';
import '../model/network_log.dart';

/// Central store for all captured network logs.
///
/// Access via [NetworkLogger.instance]. Call [logRequest] after every HTTP
/// response. Wrap your app with [NetworkInspectorOverlay] to display the
/// floating debug button.
class NetworkLogger extends ChangeNotifier {
  NetworkLogger._();

  static final NetworkLogger instance = NetworkLogger._();

  final List<NetworkLog> _logs = [];
  int _counter = 0;

  /// Set to `false` to disable logging without removing the overlay.
  /// Automatically disabled in release builds.
  bool enabled = true;

  /// Maximum number of entries kept in memory. Defaults to 300.
  int maxEntries = 300;

  /// All captured logs, newest first.
  List<NetworkLog> get logs => List.unmodifiable(_logs);

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
    if (!kDebugMode || !enabled) return;
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

  /// Remove all stored logs.
  void clear() {
    _logs.clear();
    notifyListeners();
  }
}
