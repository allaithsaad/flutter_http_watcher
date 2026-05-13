/// A lightweight in-app network inspector for Flutter.
///
/// ## Quick start
///
/// **1. Wrap your app (pass your app's navigatorKey):**
/// ```dart
/// builder: (context, child) => NetworkInspectorOverlay(
///   navigatorKey: navigatorKey, // GlobalKey<NavigatorState> — required
///   child: child!,
/// ),
/// ```
///
/// **2a. Use the built-in HTTP client (automatic logging):**
/// ```dart
/// final client = NetworkInspectorHttpClient();
/// final response = await client.get(Uri.parse('https://api.example.com'));
/// ```
///
/// **2b. Or log manually from any HTTP client:**
/// ```dart
/// final start = DateTime.now();
/// final response = await http.get(uri);
/// NetworkLogger.instance.logRequest(
///   method: 'GET',
///   url: uri.toString(),
///   statusCode: response.statusCode,
///   responseBody: response.body,
///   startTime: start,
/// );
/// ```
///
/// **3. Control visibility via a flag:**
/// ```dart
/// NetworkInspectorOverlay(show: AppConstants.showNetworkInspector, child: child!)
/// ```
library flutter_http_watcher;

export 'src/core/network_logger.dart';
export 'src/model/network_log.dart';
export 'src/ui/inspector_overlay.dart';
export 'src/adapters/http_adapter.dart';
