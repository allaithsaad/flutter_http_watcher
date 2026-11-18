import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_http_watcher/src/core/watcher_web_server.dart';

Future<int> _getStatus(String url) async {
  final client = HttpClient();
  try {
    // The pairing page: answers 200 without a session.
    final req = await client.getUrl(Uri.parse(url).resolve('/'));
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    client.close(force: true);
  }
}

/// Real socket I/O, so wait in real time for [done] instead of a fixed delay.
Future<void> _waitFor(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late WatcherWebServer server;
  var changes = 0;

  setUp(() async {
    server = WatcherWebServer(firstPort: 9800);
    changes = 0;
    await server.start(() => const [], onChanged: () => changes++);
    expect(server.isRunning, isTrue, reason: server.lastError);
  });

  tearDown(() => server.stop());

  test('keeps serving after clients hang up mid-request', () async {
    final uri = Uri.parse(server.url!);
    for (var i = 0; i < 20; i++) {
      final socket = await Socket.connect(uri.host, uri.port);
      socket.write('GET /api/logs HTTP/1.1\r\nHost: x\r\n\r\n');
      socket.destroy();
    }

    expect(await _getStatus(server.url!), 200);
    expect(server.isRunning, isTrue);
    expect(changes, 0);
  });

  test('rebinds the same port when its socket dies', () async {
    final port = server.port;
    await server.debugServer!.close(force: true);
    await _waitFor(() => changes > 0);

    expect(changes, 1);
    expect(server.isRunning, isTrue);
    expect(server.port, port);
    expect(await _getStatus(server.url!), 200);
  });

  test('stop() does not restart the server', () async {
    await server.stop();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(server.isRunning, isFalse);
    expect(changes, 0);
  });

  test('stop() during a restart keeps the server stopped', () async {
    var hookRan = false;
    server.debugBeforeRebind = () async {
      hookRan = true;
      await server.stop();
    };
    await server.debugServer!.close(force: true);
    await _waitFor(() => hookRan);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(hookRan, isTrue);
    expect(server.isRunning, isFalse);
    expect(server.url, isNull);
    expect(server.debugServer, isNull);
    expect(changes, 0);
  });

  test('gives up when the socket dies again right after a restart', () async {
    await server.debugServer!.close(force: true);
    await _waitFor(() => changes > 0);
    await server.debugServer!.close(force: true);
    await _waitFor(() => changes > 1);

    expect(changes, 2);
    expect(server.isRunning, isFalse);
    expect(server.url, isNull);
    expect(server.lastError, startsWith('Web viewer stopped'));
  });
}
