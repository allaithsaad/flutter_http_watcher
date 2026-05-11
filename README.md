# network_inspector

A lightweight in-app network inspector for Flutter.  
Shows a draggable floating button that opens a full request/response viewer — no external dependencies beyond `http`, debug-only, zero setup.

---

## Features

- Draggable floating button showing live request count
- Color-coded by HTTP method (GET / POST / PUT / DELETE)
- Color-coded status codes (green 2xx · orange 4xx · red 5xx)
- Full request & response viewer with JSON pretty-printing
- One-tap copy to clipboard
- Hide button from within the inspector
- Built-in `NetworkInspectorHttpClient` for automatic logging
- Manual `logRequest` API for any HTTP client
- **Zero overhead in release builds** — logging and UI are stripped automatically

---

## Installation

```yaml
dependencies:
  network_inspector: ^0.1.0
```

---

## Setup

### 1 — Wrap your app

```dart
import 'package:network_inspector/network_inspector.dart';

// Inside MaterialApp / GetMaterialApp builder:
builder: (context, child) {
  return NetworkInspectorOverlay(
    show: true,  // set false to hide (e.g. via a feature flag)
    child: child!,
  );
},
```

### 2a — Automatic logging (http package)

```dart
import 'package:network_inspector/network_inspector.dart';

final client = NetworkInspectorHttpClient();
final response = await client.get(Uri.parse('https://api.example.com/users'));
// Every request/response is logged automatically.
```

### 2b — Manual logging (any HTTP client)

```dart
final start = DateTime.now();
final response = await myClient.get(uri);

NetworkLogger.instance.logRequest(
  method: 'GET',
  url: uri.toString(),
  statusCode: response.statusCode,
  responseBody: response.body,
  startTime: start,
);
```

---

## Configuration

```dart
// Show/hide button via a constant:
NetworkInspectorOverlay(show: AppConstants.showNetworkInspector, child: child!)

// Disable logging at runtime (e.g. from a settings screen):
NetworkLogger.instance.enabled = false;

// Change maximum entries kept in memory (default: 300):
NetworkLogger.instance.maxEntries = 100;
```

---

## Release builds

The overlay widget returns `child` unchanged and `logRequest` is a no-op when
`kDebugMode` is `false`. No inspector code runs in production.

---

## License

MIT
