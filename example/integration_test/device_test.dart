// Runs the package's widget tests on a real device, plus checks that only mean
// something on one — the Web Viewer serving over the device's actual network.
//
//   cd example
//   flutter test integration_test -d <device-id>
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_http_watcher/network_inspector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/build_phase_notify_test.dart' as build_phase_notify;
import '../../test/kp_network_inspector_test.dart' as logger;
import '../../test/theme_follows_app_test.dart' as theme_follows_app;
import '../../test/web_server_auto_start_test.dart' as web_server_auto_start;
// test/version_test.dart is host-only: it reads pubspec.yaml from disk.

Future<String> _get(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final res = await (await client.getUrl(Uri.parse(url))).close();
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('logger', logger.main);
  group('build phase notify', build_phase_notify.main);
  group('theme follows app', theme_follows_app.main);
  group('web server auto start', web_server_auto_start.main);

  group('on device', () {
    tearDown(() => HttpWatcherLogger.instance.stopWebServer());

    testWidgets('auto-started Web Viewer serves logs on the LAN address',
        (tester) async {
      HttpWatcherLogger.instance.clear();
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: HttpWatcherOverlay(
            navigatorKey: navigatorKey,
            autoStartWebServer: true,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        if (HttpWatcherLogger.instance.webServerRunning) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      await tester.pump();

      final url = HttpWatcherLogger.instance.webServerUrl;
      expect(url, isNotNull, reason: HttpWatcherLogger.instance.webServerLastError);
      expect(HttpWatcherLogger.instance.webServerIsLoopback, isFalse,
          reason: 'the device should be on WiFi so other machines can reach it');
      expect(find.byIcon(Icons.wifi_tethering), findsOneWidget);

      HttpWatcherLogger.instance.logRequest(
        method: 'GET',
        url: 'https://example.com/device-check',
        statusCode: 200,
        responseBody: '{"ok":true}',
        startTime: DateTime.now(),
      );

      final page = await tester.runAsync(() => _get(url!));
      expect(page, contains('<title>HTTP Watcher</title>'));

      final body = await tester.runAsync(() => _get('$url/api/logs'));
      final logs = jsonDecode(body!) as List<dynamic>;
      expect(logs, hasLength(1));
      expect(logs.first['url'], 'https://example.com/device-check');
      expect(logs.first['statusCode'], 200);
    });
  });
}
