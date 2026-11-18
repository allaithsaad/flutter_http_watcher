## 1.5.1

* Fix the `share_plus` lower bound: it is now `>=11.0.0`. Exports use `SharePlus.instance` and `ShareParams`, which don't exist in 10.x, so resolving the oldest allowed version failed to compile.
* The **Change code** and **Use random code** buttons in the Web Viewer dialog are green, matching the inspector theme.
* The package no longer ships the `doc/` screenshots and demo GIF (the README loads them from GitHub), so it downloads 89 KB instead of about 6 MB.
* New README screenshots and demo, including the pairing-code dialog and the browser side of the Web Viewer.

## 1.5.0

* **Security: the Web Viewer asks for a pairing code shown on the phone.** The server listens on the device's Wi-Fi address and the logs hold full headers and bodies (bearer tokens, session responses), so before this anyone on the same network could open `http://<phone-ip>:<port>` and read them. Now a browser that opens the URL gets a form asking for the 6-digit code shown in **⋮ → Web Viewer** (and printed to the debug console with the URL). The right code gives that browser a session cookie (`HttpOnly`, `SameSite=Strict`), so each browser pairs once; `/api/logs` answers `401` without it. Each start makes a new code and forgets paired browsers. After a wrong code, attempts are refused for a second, and 5 wrong codes in a row replace the code. An automatic restart after a dropped connection keeps the code and the paired browsers. New: `HttpWatcherLogger.webServerPairingCode`. The URL itself is unchanged and logged content is unchanged.
* **Change or turn off the Web Viewer code.** On the phone, **⋮ → Web Viewer** has **Change code** (your own code, 6–64 characters, no spaces), **Use random code**, and a **Require code** switch (turning it off asks for confirmation). From code: `HttpWatcherOverlay(webServerCode: ..., webServerRequiresCode: ...)`, or `HttpWatcherLogger.setWebServerCode(String?)` and `setWebServerRequiresCode(bool)`. Settings last for the app run. Changing the code signs out paired browsers. With the code off, the debug console and the dialog warn that anyone on the network can read the logs. The code can only be turned off in debug builds; elsewhere `setWebServerRequiresCode(false)` is ignored and returns `false`.
* **USB-only Web Viewer.** `HttpWatcherOverlay(webServerLocalOnly: true)`, `HttpWatcherLogger.setWebServerLocalOnly(bool)`, or **This device only (USB)** in the dialog makes the server listen on 127.0.0.1 only, so the logs never cross the network (the viewer is plain HTTP). Open it over USB with `adb forward tcp:<port> tcp:<port>` and `http://localhost:<port>`.
* **Security hardening from a review of the package:**
  * Requests whose `Host` isn't the phone's IP, `localhost` or `127.0.0.1` get a 404, which blocks DNS-rebinding attacks from websites.
  * Code posts from another website (`Origin` mismatch) get a 403.
  * Guessing limits are per device: one try per second, and 5 wrong codes lock that device out for 30 seconds without affecting others. A random code is replaced after 50 wrong codes overall.
  * The server listens on a Wi-Fi or Ethernet address and never on mobile data or a VPN interface. If neither is available, it falls back to 127.0.0.1.
  * The request method is HTML-escaped in the viewer.
  * Old HAR and text exports are deleted from the temp folder on the next launch.
  * The connectivity check (a DNS lookup every 5 s) runs only while a visible overlay is listening, no longer as soon as the logger is used, including in release builds.
* The logs endpoint no longer sends `Access-Control-Allow-Origin: *` (the page is same-origin) and sends `Cache-Control: no-store`.

## 1.4.1

* Fix the **Web Viewer dying on a dropped connection**. A connection aborted before the server accepted it (a Wi-Fi drop, or a client giving up) reached the zone as an unhandled `SocketException: Software caused connection abort`, and the port stopped answering while the overlay still showed the server as running. The server now catches errors on its socket and rebinds itself, on the same port when it is free, so an open viewer reconnects on its own. It looks up the device's address again before rebinding, since a Wi-Fi drop can change it; if the address changed, the viewer has to be reopened at the new URL. If the socket dies again within 2 seconds of a restart it gives up instead of looping; the server then shows as stopped, with the reason in `webServerLastError`.
* A client that hangs up mid-response no longer throws an unhandled exception.

## 1.4.0

* Add **`HttpWatcherOverlay(autoStartWebServer: true)`** — starts the Web Viewer as soon as the app launches, so logs can be opened in a browser without first going through **⋮ → Web Viewer**. It only takes effect in debug builds (`kDebugMode`) and while `show` is `true`; it is ignored in profile/release builds and on Flutter web. The URL is printed to the debug console. Defaults to `false`.
* A server you stop by hand is not restarted when the overlay rebuilds; it starts again on the next launch (or hot restart). Switching the option on during a hot reload starts it immediately.
* The floating button now shows a green **Web Viewer icon** while the server is running, whether it was started automatically or from the options sheet. It stays visible while logging is paused, since the server keeps serving.
* Fix the floating button sliding **under the system navigation bar** in landscape. It was positioned from the raw screen edge, so on Android in landscape the nav bar covered its right end — the request count, error badge, and server icon. The button now stays inside the safe area, including while dragging.

## 1.3.2

* Fix the inspector **always opening in dark mode**, regardless of the host app. `HttpWatcherLogger.instance.isDark` was hardcoded to `true` and the inspector never read the ambient `Theme`, so on a light app the options sheet, list, and detail screens all rendered with the dark palette. The inspector now follows the host app's brightness by default.
* New `HttpWatcherLogger.instance.themeMode` (`WatcherThemeMode.system` | `.light` | `.dark`), defaulting to `system`. Assigning `isDark` still works and now pins the inspector to that palette; `toggleTheme()` does the same. Call `followAppTheme()` — or long-press the theme row in the options sheet — to hand control back to the app.
* The theme row in the options sheet shows which mode is active.
* Fix HAR exports reporting a stale **`log.creator.version`** — it was hardcoded to `1.2.0` and never moved, so every `.har` produced since 1.2.0 misreported the version that generated it. The version now lives in one place (`kWatcherVersion`) and a test fails the build if it drifts from `pubspec.yaml`. The HAR spec version (`log.version: "1.2"`) is unchanged and was always correct.

## 1.3.1

* Fix **`setState() called during build`** crash introduced by two-phase logging in 1.3.0. `logRequestStart` notifies before the request is awaited, so calling it from `initState`, `build`, or a controller's `onInit` — anywhere a build scope is active — dispatched a notification mid-build and asserted inside `HttpWatcherOverlay`. Log notifications are now dispatched on a microtask, which is guaranteed to run after the (always synchronous) build scope unwinds. Log entries are still recorded synchronously, so `logs` is accurate the moment a call returns; only the listener notification defers, and bursts of logs now collapse into a single notification.
* `_refresh` listeners in the overlay and list check `mounted` before `setState`.

## 1.3.0

* Add **two-phase logging** — requests can now appear in the inspector the moment they start, then update in place when the response arrives. New `HttpWatcherLogger.instance.logRequestStart(...)` returns an id; pass it to `logResponse(id: ..., statusCode: ..., responseBody: ...)` (or `failRequest(id: ...)`) on completion. The existing one-shot `logRequest(...)` still works unchanged.
* Pending requests show a live spinner and `pending` label in the inspector list, detail screen, and web viewer; the detail screen updates automatically when the response lands.
* Pending requests are excluded from the error badge count and status filters until they complete — `isSuccess`, `isClientError`, `isServerError`, and `isFailed` all return `false` while a request is in flight. Note that `isFailed` previously returned `true` for any log without a status code; a pending log is no longer reported as failed.
* `NetworkLog` gains a `pending` field and an `isPending` getter. Its `statusCode`, `responseBody`, and `durationMs` fields are no longer `final` — a pending entry is updated in place rather than replaced, so a `NetworkLog` reference you hold can change after a response arrives. `durationMs` is now optional in the constructor and defaults to `0`.
* Web Viewer `/api/logs` responses include a `pending` boolean for each log.
* Example app now demonstrates the two-phase API — the dio interceptor logs on `onRequest` and completes on `onResponse`/`onError`, and new "slow" buttons on the dio and Manual tabs hold a request open so the pending state is visible.

## 1.2.5

* Web Viewer now auto-selects a free port — if `9742` is already in use (e.g. a second app instance is running), it scans upward (`9743`, `9744`, … up to `9761`) for the first available port, so multiple apps can run their viewers at once. Each instance binds its own socket (`shared: false`) and the chosen port is shown in the URL.

## 1.2.4

* Improve web server error reporting — failure snackbar now shows the actual exception instead of a generic message.
* Warn when web server binds to loopback (`127.0.0.1`) — a snackbar explains the server is only accessible on the current device.
* Show error and warning snackbars at the top of the screen instead of the bottom.

## 1.2.3

* Fix options bottom sheet appearing white in dark mode — background is now always rendered via `Material` so Flutter's Material 3 theme cannot override it.
* Fix Web Viewer button doing nothing when tapped — mounted check now uses the correct context, and a snackbar is shown if the server fails to start.
* Fix Web Viewer showing `127.0.0.1` without explanation — dialog now shows a warning when the device is not on WiFi.
* Fix Web Viewer Summary copy returning `undefined` — "Copy URL" replaced with "Copy" which copies the full summary block (URL, method, status, duration, time).

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
