import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../model/network_log.dart';

class WatcherWebServer {
  /// First port to try. If it is already in use (e.g. another app instance is
  /// already running a viewer), the server scans upward for a free one.
  static const int basePort = 9742;

  /// How many consecutive ports to try before giving up.
  static const int portRange = 20;

  /// A second failure within this window gives up instead of rebinding again,
  /// so a socket that fails on every bind can't spin in a restart loop.
  static const Duration restartWindow = Duration(seconds: 2);

  /// [firstPort] is [basePort] in the app. Test files that run in parallel
  /// pass their own, so they don't take each other's ports.
  WatcherWebServer({@visibleForTesting this.firstPort = basePort});

  final int firstPort;

  HttpServer? _server;
  String? _url;
  String? _lastError;
  int? _port;
  String? _ip;

  // Pairing. Logs carry auth tokens and session bodies, and the server listens
  // on the Wi-Fi address, so a browser sees them only after it enters the code
  // shown on the phone. It then gets a session cookie; each browser pairs once.

  // Guessing limits are per client (remote address), so one device sending
  // wrong codes locks out only itself, not the developer.

  /// Wrong codes in a row from one client before that client is locked out
  /// for [lockoutDelay].
  static const int maxWrongCodes = 5;

  /// Wrong codes from all clients together before a random code is replaced,
  /// which caps guessing from many addresses. A custom code is never replaced.
  static const int maxWrongCodesPerCode = 50;

  /// Shortest and longest custom code ([setCode]).
  static const int minCodeLength = 6;
  static const int maxCodeLength = 64;

  /// After a wrong code, that client's attempts are refused for this long.
  @visibleForTesting
  Duration wrongCodeDelay = const Duration(seconds: 1);

  /// How long a client is locked out after [maxWrongCodes] wrong attempts.
  @visibleForTesting
  Duration lockoutDelay = const Duration(seconds: 30);

  String? _code;
  String? _customCode;
  bool _requireCode = true;
  bool _localOnly = false;
  final List<String> _sessions = [];
  final Map<String, _Attempts> _attempts = {};
  int _wrongCodesForCode = 0;
  List<NetworkLog> Function()? _getLogs;
  VoidCallback? _onChanged;
  DateTime? _lastRestart;

  /// Bumped by [start] and [stop], so a restart in flight can tell that the
  /// server was stopped (or started afresh) while it was awaiting.
  int _generation = 0;

  /// Awaited by a restart just before it rebinds, so tests can call [stop]
  /// at exactly that point.
  @visibleForTesting
  Future<void> Function()? debugBeforeRebind;

  String? get url => _url;
  int? get port => _port;
  bool get isRunning => _server != null;
  String? get lastError => _lastError;
  bool get isLoopback => _url != null && _url!.contains('://127.0.0.1');

  /// The code a browser must enter, or `null` while stopped. Unless a custom
  /// one is set with [setCode], it is 6 random digits: new on every [start],
  /// kept across an automatic rebind, and replaced after
  /// [maxWrongCodesPerCode] wrong attempts (then [start]'s `onChanged` fires).
  String? get pairingCode => _code;

  /// Whether the server listens only on 127.0.0.1. See [setLocalOnly].
  bool get localOnly => _localOnly;

  /// With [on], the next [start] binds to 127.0.0.1 instead of the Wi-Fi
  /// address, so nothing is reachable over the network; the developer uses
  /// `adb forward tcp:<port> tcp:<port>` and opens `http://localhost:<port>`.
  /// A running server must be restarted for this to take effect.
  void setLocalOnly(bool on) => _localOnly = on;

  /// Whether a browser must enter [pairingCode]. See [setRequiresCode].
  bool get requiresCode => _requireCode;

  /// Whether [pairingCode] was set with [setCode] instead of being random.
  bool get hasCustomCode => _customCode != null;

  /// Why [code] can't be used as a custom code, or `null` if it can.
  static String? validateCode(String code) {
    if (code.length < minCodeLength) {
      return 'Use at least $minCodeLength characters.';
    }
    if (code.length > maxCodeLength) {
      return 'Use at most $maxCodeLength characters.';
    }
    if (code.contains(RegExp(r'\s'))) return 'Spaces are not allowed.';
    return null;
  }

  /// Uses [code] instead of a random one, for this and later starts, or goes
  /// back to random codes when it is `null`. Paired browsers must pair again.
  /// Throws [ArgumentError] when [validateCode] rejects [code].
  void setCode(String? code) {
    if (code != null) {
      final problem = validateCode(code);
      if (problem != null) throw ArgumentError.value(code, 'code', problem);
    }
    _customCode = code;
    if (_code == null) return; // Stopped: start() picks it up.
    _sessions.clear();
    _attempts.clear();
    _wrongCodesForCode = 0;
    _code = code ?? _newCode();
  }

  /// When [on] is `false`, any browser that can reach the server sees the
  /// logs, which include auth headers and bodies. Kept across starts.
  ///
  /// Only debug builds can turn the code off: outside [kDebugMode] this does
  /// nothing for `false` and returns `false`.
  bool setRequiresCode(bool on) {
    if (!on && !_allowCodeOff) return false;
    _requireCode = on;
    return true;
  }

  /// Whether [setRequiresCode] may turn the code off: debug builds only.
  bool get canTurnOffCode => _allowCodeOff;
  bool _allowCodeOff = kDebugMode;

  /// Lets tests act like a profile or release build.
  @visibleForTesting
  set debugAllowCodeOff(bool value) => _allowCodeOff = value;

  /// The live server, so tests can kill it the way a dropped socket does.
  @visibleForTesting
  HttpServer? get debugServer => _server;

  /// Starts the server. [onChanged] fires when the server restarts itself
  /// after its socket dies, or gives up, so the UI can show the new state.
  Future<String?> start(
    List<NetworkLog> Function() getLogs, {
    VoidCallback? onChanged,
  }) async {
    if (_server != null) return _url;
    _generation++;
    _getLogs = getLogs;
    _onChanged = onChanged;
    _lastError = null;
    _lastRestart = null;
    // New per start; a rebind in _recover keeps the code and the paired
    // browsers, so an open viewer reconnects without pairing again.
    _resetPairing();
    _code = _customCode ?? _newCode();
    try {
      _ip = await _bindAddress();
      final server = await _bindFreePort(_ip!);
      if (server == null) {
        _lastError =
            'No free port available in range $firstPort-${firstPort + portRange - 1}';
        return null;
      }
      _attach(server);
      return _url;
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  /// Tries [preferred] first (the port a restarted server had), then
  /// [firstPort] and each subsequent port, returning the first one that binds
  /// successfully. `shared: false` ensures each app instance gets its own
  /// socket instead of silently sharing the same port. Returns null if every
  /// port in the range is taken.
  Future<HttpServer?> _bindFreePort(String ip, {int? preferred}) async {
    final ports = [
      if (preferred != null) preferred,
      for (var p = firstPort; p < firstPort + portRange; p++)
        if (p != preferred) p,
    ];
    for (final p in ports) {
      try {
        return await HttpServer.bind(ip, p, shared: false);
      } on SocketException {
        // Port in use — try the next one.
        continue;
      }
    }
    return null;
  }

  Future<void> stop() async {
    // Detach first: closing ends the stream, and its onDone must see a server
    // that is no longer ours, or it would restart what we are stopping.
    _generation++;
    final server = _server;
    _server = null;
    _url = null;
    _port = null;
    _resetPairing();
    await server?.close(force: true);
  }

  void _attach(HttpServer server) {
    _server = server;
    _port = server.port;
    _url = 'http://$_ip:$_port';
    server.listen(
      _handle,
      // A connection aborted before accept (e.g. a Wi-Fi drop) surfaces here.
      // Unhandled, it reached the zone as an uncaught SocketException and left
      // the port dead while the overlay still said "running".
      onError: (Object e) => _recover(server, e),
      onDone: () => _recover(server, null),
    );
  }

  /// Replaces a server whose stream failed or ended without [stop], keeping
  /// the same port when it is free so an open viewer reconnects by itself.
  Future<void> _recover(HttpServer dead, Object? error) async {
    if (!identical(dead, _server)) return; // stopped, or already replaced
    final generation = _generation;
    // stop() or start() ran while we were awaiting: this recovery is stale.
    bool superseded() => generation != _generation;
    final port = _port;
    _server = null;
    if (error != null) _lastError = error.toString();
    try {
      await dead.close(force: true);
    } catch (_) {
      // Already closed.
    }

    final now = DateTime.now();
    final last = _lastRestart;
    final tooSoon = last != null && now.difference(last) < restartWindow;
    HttpServer? server;
    if (!tooSoon) {
      await debugBeforeRebind?.call();
      if (superseded()) return;
      // A Wi-Fi drop often hands the device a new address; binding to the old
      // one would fail on every port.
      _ip = await _bindAddress();
      if (superseded()) return;
      server = await _bindFreePort(_ip!, preferred: port);
    }
    if (superseded()) {
      await server?.close(force: true);
      return;
    }
    if (server == null) {
      _url = null;
      _port = null;
      _lastError = 'Web viewer stopped: ${_lastError ?? 'socket closed'}';
    } else {
      _lastRestart = now;
      _attach(server);
    }
    _onChanged?.call();
  }

  static final Random _random = Random.secure();

  /// Six random digits, zero-padded.
  static String _newCode() =>
      _random.nextInt(1000000).toString().padLeft(6, '0');

  /// A 128-bit random session token, base64url without padding.
  static String _newToken() => base64Url
      .encode(List<int>.generate(16, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  /// Compares in time that depends only on the length, which is public.
  static bool _matches(String given, String expected) {
    if (given.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < given.length; i++) {
      diff |= given.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }

  void _resetPairing() {
    _code = null;
    _sessions.clear();
    _attempts.clear();
    _wrongCodesForCode = 0;
  }

  /// Rejects requests addressed to another host name. Without this, a website
  /// could point its own domain at the phone (DNS rebinding) and read the
  /// logs from the developer's browser as a same-origin page.
  bool _hostAllowed(HttpRequest req) {
    final host = req.headers.value(HttpHeaders.hostHeader)?.toLowerCase();
    if (host == null) return false;
    if (host == '$_ip:$_port') return true;
    // Loopback names can't be produced by rebinding (the attacker's domain is
    // the Host), so allow any port: `adb forward` may use another local port.
    final colon = host.lastIndexOf(':');
    final name = colon == -1 ? host : host.substring(0, colon);
    return name == 'localhost' || name == '127.0.0.1';
  }

  /// Browsers send Origin on form posts. A post from another site (a page
  /// trying codes, or locking the developer out) is refused. Clients that
  /// send no Origin, like curl, are allowed.
  bool _originAllowed(HttpRequest req) {
    final origin = req.headers.value('origin');
    if (origin == null) return true;
    return origin.toLowerCase() ==
        'http://${req.headers.value(HttpHeaders.hostHeader)?.toLowerCase()}';
  }

  /// Per port, because browsers share cookies across ports of the same host:
  /// two apps on one phone must not overwrite each other's session.
  String get _cookieName => 'hw_session_$_port';

  bool _isPaired(HttpRequest req) {
    if (!_requireCode) return true;
    var paired = false;
    for (final c in req.cookies) {
      if (c.name != _cookieName) continue;
      // Check every session, so the time taken doesn't depend on which matched.
      for (final s in _sessions) {
        if (_matches(c.value, s)) paired = true;
      }
    }
    return paired;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final res = req.response;
      res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final path = req.uri.path;
      if (!_hostAllowed(req)) {
        res.statusCode = HttpStatus.notFound;
      } else if (path == '/pair' && req.method == 'POST') {
        await _pair(req);
      } else if (path == '/api/logs') {
        if (_isPaired(req)) {
          res
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(_logsJson()));
        } else {
          // The page reloads on this, which shows the pairing form.
          res.statusCode = HttpStatus.unauthorized;
        }
      } else if (path == '/') {
        res.headers.contentType = ContentType.html;
        res.write(_isPaired(req) ? _html : _pairHtml(null));
      } else {
        res.statusCode = HttpStatus.notFound;
      }
      await res.close();
    } on IOException {
      // The client hung up mid-response. Nothing to answer; the server lives on.
    }
  }

  Future<void> _pair(HttpRequest req) async {
    final res = req.response..headers.contentType = ContentType.html;

    if (!_requireCode) {
      res
        ..statusCode = HttpStatus.seeOther
        ..headers.set(HttpHeaders.locationHeader, '/');
      return;
    }

    if (!_originAllowed(req)) {
      res.statusCode = HttpStatus.forbidden;
      return;
    }

    final client = req.connectionInfo?.remoteAddress.address ?? '';
    final now = DateTime.now();
    final locked = _attempts[client]?.lockedUntil;
    if (locked != null && now.isBefore(locked)) {
      res
        ..statusCode = HttpStatus.tooManyRequests
        ..write(_pairHtml('Too many attempts. Wait a moment and try again.'));
      return;
    }

    // A short form field; anything much bigger isn't a real attempt.
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > 256) break;
    }
    String given = '';
    try {
      given = Uri.splitQueryString(utf8.decode(bytes, allowMalformed: true))['code']
              ?.replaceAll(RegExp(r'\s'), '') ??
          '';
    } on FormatException {
      // Treated as a wrong code below.
    }

    final code = _code;
    if (code != null && _matches(given, code)) {
      _attempts.remove(client);
      final token = _newToken();
      _sessions.add(token);
      res
        ..statusCode = HttpStatus.seeOther
        ..headers.set(HttpHeaders.locationHeader, '/')
        // HttpOnly: page scripts can't read it. SameSite=Strict: other sites
        // can't make requests that carry it.
        ..headers.add(HttpHeaders.setCookieHeader,
            '$_cookieName=$token; Path=/; HttpOnly; SameSite=Strict');
      return;
    }

    // Keep the table small: forget clients whose lock has run out.
    if (_attempts.length > 256) {
      _attempts.removeWhere((_, a) => !a.lockedUntil.isAfter(now));
    }
    final attempts = _attempts.putIfAbsent(client, () => _Attempts(now));
    attempts
      ..wrong += 1
      ..lockedUntil = now.add(wrongCodeDelay);
    _wrongCodesForCode++;
    var message = 'Wrong code. Check the code on the phone and try again.';
    if (attempts.wrong >= maxWrongCodes) {
      attempts
        ..wrong = 0
        ..lockedUntil = now.add(lockoutDelay);
      message = 'Too many wrong codes. Try again in '
          '${lockoutDelay.inSeconds} seconds.';
    }
    if (_customCode == null && _wrongCodesForCode >= maxWrongCodesPerCode) {
      // Many wrong codes overall (several devices guessing): replace it.
      _wrongCodesForCode = 0;
      _code = _newCode();
      message = 'Too many wrong codes, so the phone now shows a new one.';
      _onChanged?.call();
    }
    res
      ..statusCode = HttpStatus.unauthorized
      ..write(_pairHtml(message));
  }

  List<Map<String, Object?>> _logsJson() =>
      (_getLogs?.call() ?? const <NetworkLog>[])
          .map((l) => {
                'method': l.method,
                'url': l.url,
                'statusCode': l.statusCode,
                'pending': l.pending,
                'durationMs': l.durationMs,
                'timestamp': l.timestamp.toIso8601String(),
                'requestHeaders': l.requestHeaders,
                'requestBody': l.requestBody?.toString(),
                'responseBody': l.responseBody,
              })
          .toList();

  /// The page an unpaired browser gets. [error] comes only from this file,
  /// never from the request, so it is safe to put in the HTML as is.
  String _pairHtml(String? error) => '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>HTTP Watcher</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0d0d1a;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:16px}
form{background:#1a1a2e;border:1px solid #2a2a3e;border-radius:14px;padding:28px 24px;width:100%;max-width:360px;text-align:center}
h1{font-size:17px;font-weight:600;margin-bottom:8px}
p{color:#9a9ab0;font-size:13px;line-height:1.5;margin-bottom:20px}
input{width:100%;background:#0d0d1a;border:1px solid #3a3a52;border-radius:10px;color:#69f0ae;font:600 28px/1 ui-monospace,Menlo,Consolas,monospace;letter-spacing:10px;text-align:center;padding:14px 0 14px 10px}
input.custom{font-size:20px;letter-spacing:2px;padding:14px 10px}
input:focus{outline:none;border-color:#69f0ae}
button{margin-top:16px;width:100%;background:#69f0ae;color:#0d0d1a;border:0;border-radius:10px;font-size:15px;font-weight:600;padding:12px;cursor:pointer}
.err{color:#ff8a80;font-size:13px;margin:14px 0 0}
</style>
</head>
<body>
<form method="post" action="/pair">
<h1>HTTP Watcher</h1>
${_customCode == null ? '''<p>Enter the 6-digit code shown on the phone in <b>Network Inspector &rarr; &#8942; &rarr; Web Viewer</b>, or in the debug console.</p>
<input name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9 ]*" maxlength="7" required autofocus>''' : '''<p>Enter the Web Viewer code set in the app. It is shown on the phone in <b>Network Inspector &rarr; &#8942; &rarr; Web Viewer</b>.</p>
<input name="code" type="password" class="custom" autocomplete="current-password" maxlength="$maxCodeLength" required autofocus>'''}
<button type="submit">Open logs</button>
${error == null ? '' : '<p class="err">$error</p>'}
</form>
</body>
</html>''';

  Future<String> _bindAddress() async =>
      _localOnly ? '127.0.0.1' : await _localIp();

  Future<String> _localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      return pickAddress([
        for (final iface in interfaces)
          for (final addr in iface.addresses)
            if (!addr.isLoopback) (name: iface.name, address: addr.address),
      ]);
    } catch (_) {
      return '127.0.0.1';
    }
  }

  // Interfaces that face the local network (Wi-Fi, Ethernet, hotspot).
  static final _lanInterface = RegExp(
    r'^(wlan|swlan|wifi|wi-fi|wl|ap|en|eth|ethernet)',
    caseSensitive: false,
  );

  // Mobile data, VPN and tunnel interfaces. Binding there could expose the
  // viewer to the carrier's network or VPN peers, so they are never used.
  static final _nonLanInterface = RegExp(
    r'^(rmnet|ccmni|pdp|v4-|clat|wwan|tun|ppp|ipsec|utun|dummy|seth|qmi)',
    caseSensitive: false,
  );

  /// Picks the address to listen on: a Wi-Fi/Ethernet interface first, then
  /// any other interface that is not mobile data or a VPN, else 127.0.0.1.
  @visibleForTesting
  static String pickAddress(List<({String name, String address})> candidates) {
    for (final c in candidates) {
      if (_lanInterface.hasMatch(c.name)) return c.address;
    }
    for (final c in candidates) {
      if (!_nonLanInterface.hasMatch(c.name)) return c.address;
    }
    return '127.0.0.1';
  }

  // ignore: long-string
  static const _html = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>HTTP Watcher</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0d0d1a;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:13px}
header{background:#1a1a2e;padding:12px 16px;display:flex;align-items:center;gap:10px;position:sticky;top:0;z-index:10;border-bottom:1px solid #2a2a3e}
h1{font-size:15px;font-weight:600;flex:1}
#dot{width:8px;height:8px;border-radius:50%;background:#4caf50;flex-shrink:0}
#dot.off{background:#f44336}
#count{font-size:12px;color:rgba(255,255,255,.4);white-space:nowrap}
#filters{background:#1a1a2e;padding:10px 16px;border-bottom:1px solid #2a2a3e;display:flex;flex-direction:column;gap:8px;position:sticky;top:49px;z-index:9}
#search{background:#0d0d1a;border:1px solid #2a2a3e;border-radius:8px;padding:8px 12px;color:#fff;font-size:13px;width:100%;outline:none}
#search:focus{border-color:#61afef}
#search::placeholder{color:rgba(255,255,255,.3)}
.chips{display:flex;gap:6px;flex-wrap:wrap}
.chip{background:transparent;border:1px solid #2a2a3e;border-radius:20px;padding:4px 12px;color:rgba(255,255,255,.4);font-size:12px;cursor:pointer}
.chip:hover{border-color:rgba(255,255,255,.4);color:#fff}
.chip.on{color:#fff;background:rgba(97,175,239,.12);border-color:#61afef}
.mGET.on{border-color:#61afef;color:#61afef;background:rgba(97,175,239,.1)}
.mPOST.on{border-color:#98c379;color:#98c379;background:rgba(152,195,121,.1)}
.mPUT.on{border-color:#e5c07b;color:#e5c07b;background:rgba(229,192,123,.1)}
.mDELETE.on{border-color:#e06c75;color:#e06c75;background:rgba(224,108,117,.1)}
.s2xx.on{border-color:#4caf50;color:#4caf50;background:rgba(76,175,80,.1)}
.s4xx.on{border-color:#ff9800;color:#ff9800;background:rgba(255,152,0,.1)}
.s5xx.on{border-color:#f44336;color:#f44336;background:rgba(244,67,54,.1)}
.serr.on{border-color:#9e9e9e;color:#9e9e9e;background:rgba(158,158,158,.1)}
table{width:100%;border-collapse:collapse}
th{background:#1a1a2e;padding:9px 16px;text-align:left;font-weight:500;color:rgba(255,255,255,.4);border-bottom:1px solid #2a2a3e;white-space:nowrap}
td{padding:9px 16px;border-bottom:1px solid #1c1c2e;vertical-align:middle}
tr:hover td{background:#1a1a2e;cursor:pointer}
.m{font-weight:700;font-size:11px}
.GET{color:#61afef}.POST{color:#98c379}.PUT{color:#e5c07b}.DELETE{color:#e06c75}.OTHER{color:rgba(255,255,255,.5)}
.path{color:#fff}.host{color:rgba(255,255,255,.3);font-size:11px;margin-top:2px}
.st{font-weight:700}
.s2{color:#4caf50}.s4{color:#ff9800}.s5{color:#f44336}.se{color:#9e9e9e}.sp{color:#61afef}
.spin{display:inline-block;width:11px;height:11px;border:2px solid rgba(97,175,239,.3);border-top-color:#61afef;border-radius:50%;animation:sp .8s linear infinite}
@keyframes sp{to{transform:rotate(360deg)}}
.dur{color:rgba(255,255,255,.3);font-size:11px}
.empty{text-align:center;padding:80px 20px;color:rgba(255,255,255,.25)}
.modal{display:none;position:fixed;inset:0;background:rgba(0,0,0,.75);z-index:100;padding:20px;overflow-y:auto}
.modal.open{display:block}
.box{background:#1a1a2e;border-radius:12px;max-width:720px;width:100%;margin:0 auto}
.mhdr{padding:14px 18px;border-bottom:1px solid #2a2a3e;display:flex;align-items:center;gap:10px;position:sticky;top:0;background:#1a1a2e;z-index:1}
.mtitle{flex:1;font-size:13px;font-weight:600;word-break:break-all}
.xbtn{background:none;border:none;color:rgba(255,255,255,.4);cursor:pointer;font-size:18px;padding:4px;line-height:1}
.sec{border-bottom:1px solid #2a2a3e}
.sec:last-child{border-bottom:none}
.shdr{padding:10px 18px 6px;display:flex;align-items:center;gap:6px}
.slbl{font-size:10px;color:rgba(255,255,255,.35);text-transform:uppercase;letter-spacing:.8px;flex:1}
.cbtn{background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);border-radius:6px;padding:3px 10px;color:rgba(255,255,255,.5);font-size:11px;cursor:pointer;white-space:nowrap;transition:all .15s}
.cbtn:hover{background:rgba(255,255,255,.1);color:#fff}
.cbtn.ok{color:#4caf50!important;border-color:#4caf50!important}
pre{background:#0d0d1a;margin:0 18px 14px;border-radius:8px;padding:12px;font-size:12px;white-space:pre-wrap;word-break:break-all;color:#90ee90;max-height:280px;overflow:auto;line-height:1.5}
pre.curl{color:#61afef}
</style>
</head>
<body>
<header>
  <div id="dot"></div>
  <h1>HTTP Watcher</h1>
  <span id="count">0 requests</span>
</header>
<div id="filters">
  <input id="search" type="text" placeholder="Search URL, method, status…" oninput="applyF()">
  <div class="chips" id="mc">
    <button class="chip on" onclick="setM(null,this)">All</button>
    <button class="chip mGET" onclick="setM('GET',this)">GET</button>
    <button class="chip mPOST" onclick="setM('POST',this)">POST</button>
    <button class="chip mPUT" onclick="setM('PUT',this)">PUT</button>
    <button class="chip mDELETE" onclick="setM('DELETE',this)">DELETE</button>
  </div>
  <div class="chips" id="sc">
    <button class="chip on" onclick="setS(null,this)">All</button>
    <button class="chip s2xx" onclick="setS('2xx',this)">2xx</button>
    <button class="chip s4xx" onclick="setS('4xx',this)">4xx</button>
    <button class="chip s5xx" onclick="setS('5xx',this)">5xx</button>
    <button class="chip serr" onclick="setS('err',this)">Error</button>
  </div>
</div>
<div id="root"><div class="empty">Waiting for requests…</div></div>

<div class="modal" id="modal">
  <div class="box">
    <div class="mhdr">
      <div class="mtitle" id="mtitle"></div>
      <button class="xbtn" onclick="closeM()">&#x2715;</button>
    </div>
    <div id="mbody"></div>
  </div>
</div>

<script>
var all=[],logs=[],mf=null,sf=null;
var BS=String.fromCharCode(92),NL=String.fromCharCode(10);

function mc(m){return{GET:1,POST:1,PUT:1,DELETE:1}[m]?'m '+m:'m OTHER';}
function sc(s){if(!s||s===0)return'st se';if(s>=500)return'st s5';if(s>=400)return'st s4';if(s>=200)return'st s2';return'st se';}
function pj(s){try{return JSON.stringify(JSON.parse(s),null,2);}catch(e){return s||'';}}
function esc(s){return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}

function toCurl(l){
  var sep=' '+BS+NL+'  ';
  var c='curl -X '+l.method+' "'+l.url+'"';
  if(l.requestHeaders){for(var k in l.requestHeaders){c+=sep+'-H "'+k+': '+l.requestHeaders[k]+'"';}}
  if(l.requestBody){c+=sep+'-d \''+l.requestBody+'\'';}
  return c;
}

function copy(text,btn){
  var done=function(){var o=btn.textContent;btn.textContent='Copied!';btn.classList.add('ok');setTimeout(function(){btn.textContent=o;btn.classList.remove('ok');},1500);};
  if(navigator.clipboard){navigator.clipboard.writeText(text).then(done).catch(function(){fb(text);done();});}
  else{fb(text);done();}
}
function fb(t){var x=document.createElement('textarea');x.value=t;document.body.appendChild(x);x.select();document.execCommand('copy');document.body.removeChild(x);}

function setM(v,btn){mf=v;document.querySelectorAll('#mc .chip').forEach(function(b){b.classList.remove('on');});btn.classList.add('on');applyF();}
function setS(v,btn){sf=v;document.querySelectorAll('#sc .chip').forEach(function(b){b.classList.remove('on');});btn.classList.add('on');applyF();}
function applyF(){
  var q=document.getElementById('search').value.toLowerCase();
  logs=all.filter(function(l){
    if(mf&&l.method!==mf)return false;
    if(sf){
      if(l.pending)return false;
      var s=l.statusCode;
      if(sf==='2xx'&&!(s>=200&&s<300))return false;
      if(sf==='4xx'&&!(s>=400&&s<500))return false;
      if(sf==='5xx'&&!(s>=500))return false;
      if(sf==='err'&&(s&&s!==0))return false;
    }
    if(q&&!(l.url||'').toLowerCase().includes(q)&&!l.method.toLowerCase().includes(q)&&!String(l.statusCode||'').includes(q))return false;
    return true;
  });
  renderT();
}
function renderT(){
  var n=all.length,f=logs.length;
  document.getElementById('count').textContent=n+' request'+(n!==1?'s':'')+(f!==n?' ('+f+' shown)':'');
  if(!f){document.getElementById('root').innerHTML='<div class="empty">'+(n?'No matching requests':'No requests yet')+'</div>';return;}
  var t='<table><thead><tr><th>Method</th><th>URL</th><th>Status</th><th>Duration</th></tr></thead><tbody>';
  for(var i=0;i<f;i++){
    var l=logs[i],url=l.url||'',path=url,host='',idx=all.indexOf(l);
    try{var u=new URL(url);path=u.pathname+u.search;host=u.host;}catch(e){}
    t+='<tr onclick="show('+idx+')">';
    t+='<td><span class="'+mc(l.method)+'">'+esc(l.method)+'</span></td>';
    t+='<td><div class="path">'+esc(path)+'</div><div class="host">'+esc(host)+'</div></td>';
    if(l.pending){
      t+='<td><span class="spin"></span></td>';
      t+='<td><span class="dur">pending</span></td></tr>';
    }else{
      t+='<td><span class="'+sc(l.statusCode)+'">'+(l.statusCode||'ERR')+'</span></td>';
      t+='<td><span class="dur">'+l.durationMs+'ms</span></td></tr>';
    }
  }
  t+='</tbody></table>';
  document.getElementById('root').innerHTML=t;
}

function show(i){
  var l=all[i];if(!l)return;
  document.getElementById('mtitle').textContent=l.method+' '+l.url;
  var h='';
  var st=l.pending?'Pending…':(l.statusCode||'Error');
  var du=l.pending?'—':(l.durationMs+'ms');
  var sum='URL:      '+l.url+NL+'Method:   '+l.method+NL+'Status:   '+st+NL+'Duration: '+du+NL+'Time:     '+new Date(l.timestamp).toLocaleString();
  h+='<div class="sec"><div class="shdr"><span class="slbl">Summary</span>';
  h+='<button class="cbtn" onclick="copySum('+i+',this)">Copy</button>';
  h+='</div><pre>'+esc(sum)+'</pre></div>';
  h+='<div class="sec"><div class="shdr"><span class="slbl">cURL</span><button class="cbtn" onclick="copyCurl('+i+',this)">Copy</button></div><pre class="curl">'+esc(toCurl(l))+'</pre></div>';
  if(l.requestHeaders&&Object.keys(l.requestHeaders).length){
    var hs='';for(var k in l.requestHeaders){hs+=k+': '+l.requestHeaders[k]+NL;}
    h+='<div class="sec"><div class="shdr"><span class="slbl">Request Headers</span><button class="cbtn" onclick="copyRH('+i+',this)">Copy</button></div><pre>'+esc(hs.trim())+'</pre></div>';
  }
  if(l.requestBody){
    h+='<div class="sec"><div class="shdr"><span class="slbl">Request Body</span><button class="cbtn" onclick="copyRB('+i+',this)">Copy</button></div><pre>'+esc(pj(l.requestBody))+'</pre></div>';
  }
  var resp=l.pending?'(waiting for response…)':pj(l.responseBody||'');
  h+='<div class="sec"><div class="shdr"><span class="slbl">Response Body</span><button class="cbtn" onclick="copyResp('+i+',this)">Copy</button></div><pre>'+esc(resp)+'</pre></div>';
  document.getElementById('mbody').innerHTML=h;
  document.getElementById('modal').classList.add('open');
}
function copySum(i,btn){var l=all[i];var s='URL:      '+(l.url||'')+NL+'Method:   '+(l.method||'')+NL+'Status:   '+(l.statusCode||'Error')+NL+'Duration: '+(l.durationMs||0)+'ms'+NL+'Time:     '+new Date(l.timestamp).toLocaleString();copy(s,btn);}
function copyCurl(i,btn){copy(toCurl(all[i]),btn);}
function copyRH(i,btn){var l=all[i],s='';for(var k in l.requestHeaders){s+=k+': '+l.requestHeaders[k]+NL;}copy(s.trim(),btn);}
function copyRB(i,btn){copy(pj(all[i].requestBody),btn);}
function copyResp(i,btn){copy(pj(all[i].responseBody||''),btn);}
function closeM(){document.getElementById('modal').classList.remove('open');}
document.getElementById('modal').addEventListener('click',function(e){if(e.target===this)closeM();});

async function poll(){
  try{var r=await fetch('/api/logs');if(r.status===401){location.replace('/');return;}var d=await r.json();all=d;applyF();document.getElementById('dot').className='';}
  catch(e){document.getElementById('dot').className='off';}
}
poll();setInterval(poll,3000);
</script>
</body>
</html>''';
}

/// Wrong-code bookkeeping for one client address.
class _Attempts {
  _Attempts(this.lockedUntil);
  int wrong = 0;
  DateTime lockedUntil;
}
