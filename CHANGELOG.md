## 1.0.1

* Rename public API to match package name:
  * `NetworkInspectorOverlay` → `HttpWatcherOverlay`
  * `NetworkInspectorHttpClient` → `HttpWatcherClient`
  * `NetworkLogger` → `HttpWatcherLogger`

## 1.0.0

* Initial release of `flutter_http_watcher`.
* `HttpWatcherOverlay` — draggable floating button overlay with live connectivity dot.
* `NetworkLogger` — singleton ChangeNotifier log store with pause/resume support.
* `HttpWatcherClient` — automatic `http` package adapter.
* Manual `logRequest` API for any HTTP client.
* Share button in the detail screen — shares the full request/response as plain text.
* Copy button on every section (summary, headers, body).
* `navigatorKey` is required — works correctly above the Navigator (GetX, go_router, etc.).
* Debug-only: zero overhead in release builds.
