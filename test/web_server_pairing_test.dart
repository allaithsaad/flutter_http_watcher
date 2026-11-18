import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_http_watcher/src/core/watcher_web_server.dart';
import 'package:flutter_http_watcher/src/model/network_log.dart';

class _Response {
  _Response(this.status, this.body, this.cookies, this.location);
  final int status;
  final String body;
  final List<Cookie> cookies;
  final String? location;
}

/// One browser: keeps the cookies the server sets, like a real one would.
class _Browser {
  _Browser(this.base);
  final Uri base;
  final List<Cookie> cookies = [];

  Future<_Response> get(String path) => _send('GET', path);

  Future<_Response> pair(String code) =>
      _send('POST', '/pair', form: 'code=${Uri.encodeQueryComponent(code)}');

  Future<_Response> _send(String method, String path, {String? form}) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, base.resolve(path));
      req.followRedirects = false;
      req.cookies.addAll(cookies);
      if (form != null) {
        req.headers.contentType =
            ContentType('application', 'x-www-form-urlencoded');
        req.write(form);
      }
      final res = await req.close();
      final body = await res.transform(const SystemEncoding().decoder).join();
      cookies.addAll(res.cookies);
      return _Response(res.statusCode, body, res.cookies,
          res.headers.value(HttpHeaders.locationHeader));
    } finally {
      client.close(force: true);
    }
  }
}

/// Real socket I/O, so wait in real time for [done] instead of a fixed delay.
Future<void> _waitFor(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

String _wrong(String code) =>
    ((int.parse(code) + 1) % 1000000).toString().padLeft(6, '0');

void main() {
  late WatcherWebServer server;
  late _Browser browser;
  var changes = 0;
  final log = NetworkLog(
    id: '1',
    method: 'GET',
    url: 'https://api.example.com/me',
    timestamp: DateTime(2026),
    requestHeaders: const {'Authorization': 'Bearer top-secret-token'},
  );

  setUp(() async {
    server = WatcherWebServer(firstPort: 9850)..wrongCodeDelay = Duration.zero;
    changes = 0;
    await server.start(() => [log], onChanged: () => changes++);
    expect(server.isRunning, isTrue, reason: server.lastError);
    browser = _Browser(Uri.parse(server.url!));
  });

  tearDown(() => server.stop());

  test('the link is the plain address and the code is 6 digits', () {
    expect(Uri.parse(server.url!).path, isEmpty);
    expect(server.pairingCode, matches(RegExp(r'^\d{6}$')));
  });

  test('an unpaired browser gets the code form and no logs', () async {
    final page = await browser.get('/');
    expect(page.status, 200);
    expect(page.body, contains('action="/pair"'));
    expect(page.body, isNot(contains('/api/logs')));

    final logs = await browser.get('/api/logs');
    expect(logs.status, 401);
    expect(logs.body, isEmpty);

    for (final path in ['/index.html', '/api', '/pair', '/x/api/logs']) {
      final res = await browser.get(path);
      expect(res.status, 404, reason: path);
      expect(res.body, isEmpty, reason: path);
    }
  });

  test('a wrong code is refused and sets no cookie', () async {
    final res = await browser.pair(_wrong(server.pairingCode!));
    expect(res.status, 401);
    expect(res.body, contains('Wrong code'));
    expect(res.cookies, isEmpty);
    expect((await browser.get('/api/logs')).status, 401);
  });

  test('the right code pairs the browser and shows the full logs', () async {
    final res = await browser.pair(server.pairingCode!);
    expect(res.status, 303);
    expect(res.location, '/');
    expect(res.cookies, hasLength(1));
    final setCookie = res.cookies.single;
    expect(setCookie.httpOnly, isTrue);

    final page = await browser.get('/');
    expect(page.body, contains('/api/logs')); // the viewer, not the form

    final logs = await browser.get('/api/logs');
    expect(logs.status, 200);
    expect(logs.body, contains('top-secret-token'));
  });

  test('the code may be typed with a space, as the phone shows it', () async {
    final code = server.pairingCode!;
    final res = await browser.pair('${code.substring(0, 3)} ${code.substring(3)}');
    expect(res.status, 303);
  });

  test('each browser pairs on its own', () async {
    await browser.pair(server.pairingCode!);
    final other = _Browser(browser.base);
    expect((await other.get('/api/logs')).status, 401);
  });

  test('a forged session cookie is refused', () async {
    browser.cookies.add(Cookie('hw_session_${server.port}', 'A' * 22));
    expect((await browser.get('/api/logs')).status, 401);
  });

  test('after a wrong code, attempts are refused for a moment', () async {
    server.wrongCodeDelay = const Duration(seconds: 5);
    await browser.pair(_wrong(server.pairingCode!));
    // Even the right code, so guesses can't go faster than one per delay.
    final res = await browser.pair(server.pairingCode!);
    expect(res.status, 429);
    expect(res.cookies, isEmpty);
  });

  test('5 wrong codes lock out that client but keep the code', () async {
    final code = server.pairingCode!;
    server.lockoutDelay = const Duration(seconds: 30);
    for (var i = 0; i < WatcherWebServer.maxWrongCodes; i++) {
      await browser.pair(_wrong(code));
    }
    expect(server.pairingCode, code); // the developer's code still works
    expect(changes, 0);
    final res = await browser.pair(code);
    expect(res.status, 429); // even the right code, from the locked client
    expect(res.cookies, isEmpty);
  });

  test('many wrong codes overall replace a random code and notify', () async {
    final first = server.pairingCode!;
    server.lockoutDelay = Duration.zero;
    for (var i = 0; i < WatcherWebServer.maxWrongCodesPerCode; i++) {
      await browser.pair(_wrong(first));
    }
    expect(server.pairingCode, isNot(first));
    expect(changes, 1);
    expect((await browser.pair(first)).status, 401);
    expect((await browser.pair(server.pairingCode!)).status, 303);
  });

  group('requests for another host name (DNS rebinding)', () {
    Future<String> rawStatus(String host, String path) async {
      final base = Uri.parse(server.url!);
      final s = await Socket.connect(base.host, base.port);
      s.write('GET $path HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n');
      final head = await s.cast<List<int>>().transform(const SystemEncoding().decoder).join();
      s.destroy();
      return head.split('\r\n').first;
    }

    test('get a bare 404, even with the code off', () async {
      server.setRequiresCode(false);
      final port = server.port;
      expect(await rawStatus('evil.example:$port', '/api/logs'), contains('404'));
      expect(await rawStatus('evil.example:$port', '/'), contains('404'));
      expect(await rawStatus('evil.example', '/'), contains('404'));
    });

    test('the device address and loopback names are accepted', () async {
      server.setRequiresCode(false);
      final uri = Uri.parse(server.url!);
      expect(await rawStatus('${uri.host}:${uri.port}', '/api/logs'), contains('200'));
      // adb forward may use any local port.
      expect(await rawStatus('localhost:1234', '/api/logs'), contains('200'));
      expect(await rawStatus('127.0.0.1:${uri.port}', '/api/logs'), contains('200'));
    });
  });

  test('a code posted from another site is refused', () async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(server.url!).resolve('/pair'));
      req.followRedirects = false;
      req.headers
        ..contentType = ContentType('application', 'x-www-form-urlencoded')
        ..set('origin', 'https://evil.example');
      req.write('code=${server.pairingCode}');
      final res = await req.close();
      await res.drain<void>();
      expect(res.statusCode, 403);
      expect(res.cookies, isEmpty);
    } finally {
      client.close(force: true);
    }
  });

  test('a code posted from the viewer page itself is accepted', () async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(server.url!).resolve('/pair'));
      req.followRedirects = false;
      req.headers
        ..contentType = ContentType('application', 'x-www-form-urlencoded')
        ..set('origin', server.url!);
      req.write('code=${server.pairingCode}');
      final res = await req.close();
      await res.drain<void>();
      expect(res.statusCode, 303);
    } finally {
      client.close(force: true);
    }
  });

  test('outside debug builds the code cannot be turned off', () {
    server.debugAllowCodeOff = false;
    expect(server.setRequiresCode(false), isFalse);
    expect(server.requiresCode, isTrue);
  });

  test('this-device-only mode listens on 127.0.0.1', () async {
    await server.stop();
    server.setLocalOnly(true);
    await server.start(() => [log]);
    expect(Uri.parse(server.url!).host, '127.0.0.1');
    final local = _Browser(Uri.parse('http://localhost:${server.port}'));
    expect((await local.pair(server.pairingCode!)).status, 303);
    expect((await local.get('/api/logs')).status, 200);
  });

  group('choosing the address to listen on', () {
    String pick(List<(String, String)> ifaces) => WatcherWebServer.pickAddress(
        [for (final (n, a) in ifaces) (name: n, address: a)]);

    test('prefers Wi-Fi over mobile data listed first', () {
      expect(pick([('rmnet_data0', '100.64.1.2'), ('wlan0', '192.168.1.5')]),
          '192.168.1.5');
    });

    test('never uses mobile data or VPN, falls back to loopback', () {
      expect(pick([('rmnet_data0', '100.64.1.2'), ('tun0', '10.8.0.2')]),
          '127.0.0.1');
      expect(pick([('ccmni1', '10.1.1.1')]), '127.0.0.1');
    });

    test('accepts other non-mobile interfaces (e.g. desktop adapters)', () {
      expect(pick([('vEthernet (WSL)', '172.30.96.1')]), '172.30.96.1');
      expect(pick([('Ethernet', '10.0.0.4'), ('vEthernet', '172.30.96.1')]),
          '10.0.0.4');
    });
  });

  test('a new start has a new code and forgets paired browsers', () async {
    await browser.pair(server.pairingCode!);
    final first = server.pairingCode;
    await server.stop();
    await server.start(() => [log]);

    expect(server.pairingCode, isNot(first));
    final again = _Browser(Uri.parse(server.url!))..cookies.addAll(browser.cookies);
    expect((await again.get('/api/logs')).status, 401);
  });

  group('custom code', () {
    test('replaces the random code and signs out paired browsers', () async {
      await browser.pair(server.pairingCode!);
      server.setCode('Kafarat-2026');

      expect(server.pairingCode, 'Kafarat-2026');
      expect(server.hasCustomCode, isTrue);
      expect((await browser.get('/api/logs')).status, 401);
      final page = await browser.get('/');
      expect(page.body, contains('type="password"'));
      expect((await browser.pair('Kafarat-2026')).status, 303);
      expect((await browser.get('/api/logs')).status, 200);
    });

    test('is kept across a new start', () async {
      server.setCode('abcdef');
      await server.stop();
      await server.start(() => [log]);
      expect(server.pairingCode, 'abcdef');
    });

    test('can be set while stopped and is used on start', () async {
      await server.stop();
      server.setCode('before-start');
      await server.start(() => [log]);
      expect(server.pairingCode, 'before-start');
    });

    test('null goes back to a random 6-digit code', () async {
      server.setCode('abcdef');
      server.setCode(null);
      expect(server.hasCustomCode, isFalse);
      expect(server.pairingCode, matches(RegExp(r'^\d{6}$')));
    });

    test('rejects codes that are too short, too long or have spaces', () {
      for (final bad in ['abcde', 'a' * 65, 'ab cd', '']) {
        expect(WatcherWebServer.validateCode(bad), isNotNull, reason: bad);
        expect(() => server.setCode(bad), throwsArgumentError, reason: bad);
      }
      expect(WatcherWebServer.validateCode('abcdef'), isNull);
    });

    test('5 wrong tries lock it for a while instead of replacing it',
        () async {
      server.setCode('abcdef');
      server.lockoutDelay = const Duration(seconds: 30);
      for (var i = 0; i < WatcherWebServer.maxWrongCodes; i++) {
        await browser.pair('uvwxyz');
      }
      expect(server.pairingCode, 'abcdef');
      expect(changes, 0);
      final res = await browser.pair('abcdef');
      expect(res.status, 429);
      expect(res.cookies, isEmpty);
    });
  });

  group('code turned off', () {
    test('any browser sees the viewer and the logs', () async {
      server.setRequiresCode(false);
      expect((await browser.get('/')).body, contains('/api/logs'));
      final logs = await browser.get('/api/logs');
      expect(logs.status, 200);
      expect(logs.body, contains('top-secret-token'));
      expect((await browser.pair('anything')).status, 303);
    });

    test('turning it back on locks unpaired browsers out again', () async {
      server.setRequiresCode(false);
      server.setRequiresCode(true);
      expect((await browser.get('/api/logs')).status, 401);
    });

    test('is kept across a new start', () async {
      server.setRequiresCode(false);
      await server.stop();
      await server.start(() => [log]);
      expect(server.requiresCode, isFalse);
      final fresh = _Browser(Uri.parse(server.url!));
      expect((await fresh.get('/api/logs')).status, 200);
    });
  });

  test('a rebind keeps the code and the paired browsers', () async {
    await browser.pair(server.pairingCode!);
    final code = server.pairingCode;
    await server.debugServer!.close(force: true);
    await _waitFor(() => changes > 0);

    expect(server.isRunning, isTrue);
    expect(server.pairingCode, code);
    final again = _Browser(Uri.parse(server.url!))..cookies.addAll(browser.cookies);
    expect((await again.get('/api/logs')).status, 200);
  });
}
