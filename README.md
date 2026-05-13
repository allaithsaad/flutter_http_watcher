# flutter_http_watcher

A lightweight in-app network inspector for Flutter.  
Shows a draggable floating button that opens a full request/response viewer — no external dependencies beyond `http`, debug-only, zero setup.

<p align="center">
  <img src="https://raw.githubusercontent.com/allaithsaad/flutter_http_watcher/main/doc/demo.gif" width="250"/>
</p>

---

## Features

- Draggable floating button with live request count
- **Live connectivity dot** — green (online) · red (offline) · grey (unknown)
- Color-coded by HTTP method (GET / POST / PUT / DELETE)
- Color-coded status codes (green 2xx · orange 4xx · red 5xx)
- Full request & response viewer with JSON pretty-printing
- One-tap copy to clipboard
- Pause / resume logging from within the inspector
- Built-in `HttpWatcherClient` for the `http` package
- Manual `logRequest` API for any HTTP client
- **Zero overhead in release builds** — logging and UI are stripped automatically

---

## Installation

```yaml
dependencies:
  flutter_http_watcher: ^1.0.0
```

---

## Setup

### 1 — Wrap your app

```dart
import 'package:flutter_http_watcher/network_inspector.dart';

// Declare a navigator key in your app (or use Get.key for GetX):
final navigatorKey = GlobalKey<NavigatorState>();

// Pass it to both MaterialApp and HttpWatcherOverlay:
MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) {
    return HttpWatcherOverlay(
      navigatorKey: navigatorKey, // required
      show: true,                 // set false to hide (e.g. via a feature flag)
      child: child!,
    );
  },
);
```

> **Using GetX?** Pass `Get.key` as the `navigatorKey`.
>
> ```dart
> GetMaterialApp(
>   builder: (context, child) {
>     return HttpWatcherOverlay(
>       navigatorKey: Get.key,
>       child: child!,
>     );
>   },
> );
> ```

### 2a — Automatic logging (`http` package)

```dart
import 'package:flutter_http_watcher/network_inspector.dart';

final client = HttpWatcherClient();
final response = await client.get(Uri.parse('https://api.example.com/users'));
// Every request/response is logged automatically.
```

Or wrap an existing client:

```dart
final client = HttpWatcherClient(myExistingClient);
```

### 2b — Manual logging (any HTTP client)

```dart
final start = DateTime.now();
final response = await myClient.get(uri);

HttpWatcherLogger.instance.logRequest(
  method: 'GET',
  url: uri.toString(),
  statusCode: response.statusCode,
  responseBody: response.body,
  startTime: start,
);
```

---

## Inspector screen

Open by tapping the floating button. From the app bar you can:

| Button | Action |
|--------|--------|
| Pause / Play | Stop or resume capturing new requests |
| Delete | Clear all logged requests |

Tap any row to see the full request headers, body, response body, status code, and duration.

---

## Connectivity indicator

The floating button shows a small dot reflecting the current network status, checked every 5 seconds:

| Color | Meaning |
|-------|---------|
| 🟢 Green | Device is online |
| 🔴 Red | Device is offline |
| ⚪ Grey | Status not yet determined |

---

## Configuration

```dart
// Show/hide the button via a constant:
HttpWatcherOverlay(show: AppConstants.showNetworkInspector, child: child!)

// Disable logging at runtime:
HttpWatcherLogger.instance.enabled = false;

// Toggle logging on/off:
HttpWatcherLogger.instance.toggleEnabled();

// Change maximum entries kept in memory (default: 300):
HttpWatcherLogger.instance.maxEntries = 100;
```

---

## Release builds

The overlay widget returns `child` unchanged and `logRequest` is a no-op when
`kDebugMode` is `false`. No inspector code runs in production.

---

## License

MIT
