## 1.0.4

* Remove debug-only restriction — overlay and logging now work in all build modes.
* Visibility is controlled solely by the `show` parameter on `HttpWatcherOverlay`.

## 1.0.3

* Resize demo GIF display size in README.

## 1.0.2

* Fix demo GIF not showing on pub.dev (use absolute raw GitHub URL).

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
* `show` flag controls visibility.
