## 1.0.0

* Initial release of `flutter_http_watcher`.
* `NetworkInspectorOverlay` — draggable floating button overlay with live connectivity dot.
* `NetworkLogger` — singleton ChangeNotifier log store with pause/resume support.
* `NetworkInspectorHttpClient` — automatic `http` package adapter.
* Manual `logRequest` API for any HTTP client.
* Share button in the detail screen — shares the full request/response as plain text.
* Copy button on every section (summary, headers, body).
* `navigatorKey` is required — works correctly above the Navigator (GetX, go_router, etc.).
* Debug-only: zero overhead in release builds.
