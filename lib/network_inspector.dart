/// A lightweight in-app network inspector for Flutter.
///
/// ## Quick start
///
/// **1. Wrap your app (pass your app's navigatorKey):**
/// ```dart
/// builder: (context, child) => HttpWatcherOverlay(
///   navigatorKey: navigatorKey, // GlobalKey<NavigatorState> — required
///   child: child!,
/// ),
/// ```
///
/// **2a. Use the built-in HTTP client (automatic logging):**
/// ```dart
/// final client = HttpWatcherClient();
/// final response = await client.get(Uri.parse('https://api.example.com'));
/// ```
///
/// **2b. Or log manually from any HTTP client:**
/// ```dart
/// final start = DateTime.now();
/// final response = await http.get(uri);
/// HttpWatcherLogger.instance.logRequest(
///   method: 'GET',
///   url: uri.toString(),
///   statusCode: response.statusCode,
///   responseBody: response.body,
///   startTime: start,
/// );
/// ```
///
/// **2c. Or show the request immediately, then fill in the response:**
/// ```dart
/// final id = HttpWatcherLogger.instance.logRequestStart(
///   method: 'GET',
///   url: uri.toString(),
/// );
/// final response = await http.get(uri);
/// HttpWatcherLogger.instance.logResponse(
///   id: id!,
///   statusCode: response.statusCode,
///   responseBody: response.body,
/// );
/// ```
///
/// **3. Control visibility via a flag:**
/// ```dart
/// HttpWatcherOverlay(show: AppConstants.showNetworkInspector, child: child!)
/// ```
library flutter_http_watcher;

export 'src/core/network_logger.dart';
export 'src/model/network_log.dart';
export 'src/ui/inspector_overlay.dart';
export 'src/ui/inspector_stats.dart';
