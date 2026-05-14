## 1.2.2

* Fix dependency conflict — widen `share_plus` constraint to `>=10.0.0 <14.0.0` so the package is compatible with `file_picker` and other packages that depend on `win32 ^5.x`.

## 1.2.1

* Update screenshots and demo GIF in README.

## 1.2.0

* Add **HAR export** — export all logs as a `.har` file (importable in Postman, Charles, browser DevTools).
* Add **error badge** — red badge on the floating button showing 4xx / 5xx / failed request count.
* Add **custom icon** — pass any `IconData` to `HttpWatcherOverlay(icon: ...)` to replace the default button icon.
* Add **Web Viewer** — start a local server and open live logs in any browser on the same WiFi network.
* Options bottom sheet — all inspector actions moved to a single ⋮ menu.

## 1.1.1

* Add screenshots to README.

## 1.1.0

* Add **cURL export** — copy any request as a `curl` command from the detail screen.
* Add **request replay** — re-send any logged request with one tap.
* Add **status code filter chips** — filter by 2xx / 4xx / 5xx / Error alongside method chips.
* Add `topics` to pubspec for better pub.dev discoverability.
* Full API documentation on all public classes and methods.
* Comprehensive unit tests for `HttpWatcherLogger` and `NetworkLog`.

## 1.0.9

* Add dark/light theme toggle — tap the sun/moon icon in the inspector app bar.
* All inspector screens (list, detail, stats) respect the selected theme.

## 1.0.8

* Add search bar — filter logs by URL, method, or status code.
* Add method filter chips — quickly show only GET / POST / PUT / DELETE.
* Add stats screen — success rate, avg duration, by-method breakdown, top hosts, slowest requests.
* Add save to file — export all logs as a `.txt` file via the share sheet.

## 1.0.7

* Example app updated with three tabs: `http`, `dio`, and manual logging.

## 1.0.6

* Remove `http` and `dio` dependencies — package now has zero HTTP dependencies.
* Works with any HTTP client (`http`, `dio`, `retrofit`, `graphql`, etc.) via `logRequest`.
* README updated with copy-paste adapter snippets for `http` and `dio`.

## 1.0.5

* Add `HttpWatcherDioInterceptor` — automatic logging for `dio` with one line.

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
