# flutter_http_watcher

A lightweight in-app network inspector for Flutter.  
Works with **any** HTTP client — `http`, `dio`, `retrofit`, `graphql`, or your own. Zero HTTP dependencies.

<p align="center">
  <img src="https://raw.githubusercontent.com/allaithsaad/flutter_http_watcher/main/doc/demo.gif" width="250"/>
</p>

---

## Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/allaithsaad/flutter_http_watcher/main/doc/1.jpg" width="200"/>
  <img src="https://raw.githubusercontent.com/allaithsaad/flutter_http_watcher/main/doc/2.jpg" width="200"/>
  <img src="https://raw.githubusercontent.com/allaithsaad/flutter_http_watcher/main/doc/3.jpg" width="200"/>
  <img src="https://raw.githubusercontent.com/allaithsaad/flutter_http_watcher/main/doc/4.jpg" width="200"/>
</p>

---

## Features

- Draggable floating button with live request count
- **Live connectivity dot** — green (online) · red (offline) · grey (unknown)
- Color-coded by HTTP method (GET / POST / PUT / DELETE)
- Color-coded status codes (green 2xx · orange 4xx · red 5xx)
- Search bar + method & status code filter chips
- Full request & response viewer with JSON pretty-printing
- **cURL export** — copy any request as a `curl` command
- **Request replay** — re-send any logged request with one tap
- **Stats screen** — success rate, avg duration, top hosts, slowest requests
- **Export logs** — save as `.txt` or export as `.har` (Postman / Charles / DevTools compatible)
- **Error badge** — red badge on the floating button shows 4xx / 5xx / failed count
- **Custom icon** — replace the default button icon via `HttpWatcherOverlay(icon: ...)`
- Dark / light theme toggle
- One-tap copy · share full request as text
- Pause / resume logging
- Works with **any** HTTP client — zero HTTP dependencies
- Controlled entirely by the `show` flag — use in debug, release, or staging

---

## Installation

```yaml
dependencies:
  flutter_http_watcher: ^1.2.0
```

---

## Setup

### 1 — Wrap your app

```dart
import 'package:flutter_http_watcher/network_inspector.dart';

final navigatorKey = GlobalKey<NavigatorState>();

MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) {
    return HttpWatcherOverlay(
      navigatorKey: navigatorKey,
      show: true, // set false to hide
      child: child!,
    );
  },
);
```

> **Using GetX?** Pass `Get.key` as the `navigatorKey`.

---

### 2 — Log requests

#### `http` package

Copy this wrapper into your project:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_http_watcher/network_inspector.dart';

class WatcherHttpClient extends http.BaseClient {
  final http.Client _inner;
  WatcherHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final start = DateTime.now();
    final streamed = await _inner.send(request);
    final bytes = await streamed.stream.toBytes();
    HttpWatcherLogger.instance.logRequest(
      method: request.method,
      url: request.url.toString(),
      headers: Map<String, String>.from(request.headers),
      body: request is http.Request ? request.body : null,
      statusCode: streamed.statusCode,
      responseBody: utf8.decode(bytes, allowMalformed: true),
      startTime: start,
    );
    return http.StreamedResponse(Stream.value(bytes), streamed.statusCode,
        headers: streamed.headers, contentLength: bytes.length);
  }

  @override
  void close() => _inner.close();
}
```

#### `dio`

Add this interceptor to your `Dio` instance:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_http_watcher/network_inspector.dart';

class WatcherDioInterceptor extends Interceptor {
  final _starts = <int, DateTime>{};

  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    _starts[o.hashCode] = DateTime.now();
    h.next(o);
  }

  @override
  void onResponse(Response r, ResponseInterceptorHandler h) {
    final start = _starts.remove(r.requestOptions.hashCode) ?? DateTime.now();
    HttpWatcherLogger.instance.logRequest(
      method: r.requestOptions.method,
      url: r.requestOptions.uri.toString(),
      headers: r.requestOptions.headers.map((k, v) => MapEntry(k, v.toString())),
      body: r.requestOptions.data,
      statusCode: r.statusCode ?? 0,
      responseBody: r.data?.toString() ?? '',
      startTime: start,
    );
    h.next(r);
  }

  @override
  void onError(DioException e, ErrorInterceptorHandler h) {
    final start = _starts.remove(e.requestOptions.hashCode) ?? DateTime.now();
    HttpWatcherLogger.instance.logRequest(
      method: e.requestOptions.method,
      url: e.requestOptions.uri.toString(),
      headers: e.requestOptions.headers.map((k, v) => MapEntry(k, v.toString())),
      body: e.requestOptions.data,
      statusCode: e.response?.statusCode ?? 0,
      responseBody: e.response?.data?.toString() ?? e.message ?? '',
      startTime: start,
    );
    h.next(e);
  }
}
```

#### Any other client (manual)

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
| Stats | Success rate, avg duration, top hosts, slowest requests |
| Export | Save logs as `.txt` or export as `.har` (Postman / Charles / DevTools) |
| Theme | Toggle dark / light mode |
| Clear | Remove all logged requests |
| Pause / Play | Stop or resume capturing new requests |

Tap any row to see the full request headers, body, response body, status code, and duration.  
From the detail screen you can **copy as cURL**, **replay** the request, share, or copy any section.

---

## Connectivity indicator

| Color | Meaning |
|-------|---------|
| 🟢 Green | Device is online |
| 🔴 Red | Device is offline |
| ⚪ Grey | Status not yet determined |

---

## Configuration

```dart
// Disable logging at runtime:
HttpWatcherLogger.instance.enabled = false;

// Toggle logging on/off:
HttpWatcherLogger.instance.toggleEnabled();

// Change maximum entries kept in memory (default: 300):
HttpWatcherLogger.instance.maxEntries = 100;

// Read the current error count (4xx / 5xx / failed):
final errors = HttpWatcherLogger.instance.errorCount;
```

### Custom icon

Pass any `IconData` to replace the default floating button icon:

```dart
HttpWatcherOverlay(
  navigatorKey: navigatorKey,
  icon: Icons.bug_report_outlined, // any IconData
  child: child!,
)
```

### Error badge

A red badge appears automatically on the floating button whenever there are 4xx, 5xx, or failed requests. It clears when you tap **Clear** inside the inspector.

---

## License

MIT
