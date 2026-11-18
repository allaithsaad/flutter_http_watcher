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

/// How the inspector UI chooses between its dark and light palettes.
enum WatcherThemeMode {
  /// Follow the host app's brightness. This is the default.
  system,

  /// Always use the light palette.
  light,

  /// Always use the dark palette.
  dark,
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
  HttpWatcherLogger._();

  // The connectivity check (a DNS lookup every 5 s) only runs while something
  // shows it, such as a visible overlay, not merely because the app logs.
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _syncConnectivityPolling();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _syncConnectivityPolling();
  }

  /// Whether the connectivity check is running, for tests.
  @visibleForTesting
  bool get debugConnectivityPolling => _connectivityTimer != null;

  void _syncConnectivityPolling() {
    if (kIsWeb || _disposed) return;
    if (hasListeners) {
      if (_connectivityTimer == null) _startConnectivityPolling();
    } else {
      _connectivityTimer?.cancel();
      _connectivityTimer = null;
    }
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

  /// How the inspector picks its palette.
  ///
  /// Defaults to [WatcherThemeMode.system], which follows the brightness of
  /// the host app's [ThemeData] — so the inspector matches the app instead of
  /// always opening dark.
  WatcherThemeMode themeMode = WatcherThemeMode.system;

  /// Brightness of the host app, refreshed by the inspector screens on build.
  /// Only consulted while [themeMode] is [WatcherThemeMode.system].
  Brightness _hostBrightness = Brightness.light;

  /// Records the host app's brightness. Called by the inspector UI during
  /// build, so it must not notify synchronously.
  void syncHostBrightness(Brightness brightness) {
    if (_hostBrightness == brightness) return;
    _hostBrightness = brightness;
    if (themeMode == WatcherThemeMode.system) _scheduleNotify();
  }

  /// Whether the inspector UI is currently dark.
  ///
  /// Resolved from [themeMode]; under [WatcherThemeMode.system] it mirrors the
  /// host app. Assigning to it pins the inspector to that palette, leaving
  /// [WatcherThemeMode.system] behind.
  bool get isDark => switch (themeMode) {
        WatcherThemeMode.dark => true,
        WatcherThemeMode.light => false,
        WatcherThemeMode.system => _hostBrightness == Brightness.dark,
      };

  set isDark(bool value) {
    themeMode = value ? WatcherThemeMode.dark : WatcherThemeMode.light;
    notifyListeners();
  }

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

  bool _lookupInFlight = false;

  Future<void> _checkConnectivity() async {
    // A lookup still unanswered from the previous tick (5 s) counts as
    // offline. This avoids a timeout timer, which would outlive the overlay.
    if (_lookupInFlight) {
      _updateStatus(NetworkStatus.offline);
      return;
    }
    _lookupInFlight = true;
    try {
      final result = await InternetAddress.lookup('google.com');
      final isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      _updateStatus(isOnline ? NetworkStatus.online : NetworkStatus.offline);
    } catch (_) {
      _updateStatus(NetworkStatus.offline);
    } finally {
      _lookupInFlight = false;
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
  ///
  /// Pins [themeMode] to the chosen palette; call [followAppTheme] to hand
  /// control back to the host app.
  void toggleTheme() => isDark = !isDark;

  /// Return to following the host app's brightness.
  void followAppTheme() {
    themeMode = WatcherThemeMode.system;
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
    final wasRunning = _webServer.isRunning;
    final url = await _webServer.start(() => _logs, onChanged: _onWebServerChanged);
    if (!wasRunning) _printWebServerState();
    notifyListeners();
    return url;
  }

  String? _printedWebServerState;

  /// The code a browser enters to open the Web Viewer, or `null` while it is
  /// stopped. By default 6 random digits that change on every start and after
  /// 5 wrong tries; see [setWebServerCode] to choose your own.
  String? get webServerPairingCode => _webServer.pairingCode;

  /// Whether browsers must enter [webServerPairingCode]. On by default.
  bool get webServerRequiresCode => _webServer.requiresCode;

  /// Whether [webServerPairingCode] was set with [setWebServerCode].
  bool get webServerHasCustomCode => _webServer.hasCustomCode;

  /// Why [code] can't be used with [setWebServerCode], or `null` if it can.
  static String? validateWebServerCode(String code) =>
      WatcherWebServer.validateCode(code);

  /// Uses [code] (4–64 characters, no spaces) as the Web Viewer code for the
  /// rest of this app run, or goes back to random codes when it is `null`.
  /// Browsers that were paired must enter the new code. Throws [ArgumentError]
  /// when [validateWebServerCode] rejects [code].
  void setWebServerCode(String? code) {
    _webServer.setCode(code);
    _webServerSettingsChanged();
  }

  /// Turns the code off (`false`) or back on for the rest of this app run.
  /// While it is off, anyone on the same network can open the Web Viewer and
  /// read every logged header and body, including auth tokens.
  ///
  /// Only debug builds can turn it off; in profile and release builds `false`
  /// is ignored and this returns `false`.
  bool setWebServerRequiresCode(bool required) {
    final applied = _webServer.setRequiresCode(required);
    if (!applied) {
      debugPrint('[HttpWatcher] The Web Viewer code can only be turned off '
          'in debug builds; it stays on.');
      return false;
    }
    _webServerSettingsChanged();
    return true;
  }

  /// Whether [setWebServerRequiresCode] can turn the code off in this build.
  bool get webServerCanTurnOffCode => _webServer.canTurnOffCode;

  /// Whether the Web Viewer listens only on this device (127.0.0.1).
  bool get webServerLocalOnly => _webServer.localOnly;

  /// With [on], the Web Viewer listens only on 127.0.0.1, so nothing crosses
  /// the network: connect the phone by USB, run
  /// `adb forward tcp:9742 tcp:9742` and open `http://localhost:9742`.
  /// A running server restarts so the change takes effect (with a new code
  /// unless a custom one is set). Lasts for the rest of this app run.
  Future<void> setWebServerLocalOnly(bool on) async {
    if (_webServer.localOnly == on) return;
    _webServer.setLocalOnly(on);
    if (_webServer.isRunning) {
      await _webServer.stop();
      await startWebServer();
    } else {
      _scheduleNotify();
    }
  }

  void _webServerSettingsChanged() {
    if (_webServer.isRunning) _printWebServerState();
    // Deferred: the overlay applies its parameters during a build.
    _scheduleNotify();
  }

  void _onWebServerChanged() {
    // A rebind to a new port or address, or a new code after wrong guesses:
    // print the current link and code.
    if (_webServerState() != _printedWebServerState) _printWebServerState();
    _scheduleNotify();
  }

  String _webServerState() =>
      '${_webServer.url} ${_webServer.pairingCode} ${_webServer.requiresCode}';

  void _printWebServerState() {
    _printedWebServerState = _webServerState();
    final url = _webServer.url;
    if (url == null) {
      debugPrint('[HttpWatcher] Web Viewer not running: '
          '${_webServer.lastError ?? 'unknown error'}');
      return;
    }
    final port = _webServer.port;
    final where = _webServer.localOnly
        ? ' (this device only — over USB run `adb forward tcp:$port '
            'tcp:$port`, then open http://localhost:$port)'
        : _webServer.isLoopback
            ? ' (loopback only — not reachable from other devices)'
            : '';
    final access = _webServer.requiresCode
        ? 'pairing code ${_webServer.pairingCode}'
        : 'NO CODE: anyone on this network can read the logs';
    debugPrint('[HttpWatcher] Web Viewer running at $url$where — $access');
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
