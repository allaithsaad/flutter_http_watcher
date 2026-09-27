import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_http_watcher/network_inspector.dart';

final _serverIcon = find.byIcon(Icons.wifi_tethering);

// Shared across pumps so a re-pump rebuilds the same overlay instead of
// remounting it — the way an overlay in `MaterialApp.builder` behaves.
final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> _pumpOverlay(
  WidgetTester tester, {
  bool autoStartWebServer = false,
  bool show = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: _navigatorKey,
      home: HttpWatcherOverlay(
        navigatorKey: _navigatorKey,
        autoStartWebServer: autoStartWebServer,
        show: show,
        child: const SizedBox.shrink(),
      ),
    ),
  );
}

/// Binding a socket is real I/O, which the widget tester's fake-async zone
/// never completes on its own. Let real time pass, then pump so the overlay
/// picks up the logger's notification.
Future<void> _settleServer(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    if (HttpWatcherLogger.instance.webServerRunning) break;
  }
  // One more frame for the rebuild the start notification scheduled.
  await tester.pump();
}

/// A server bound inside the test zone owns a fake idle-timeout timer, which
/// the binding reports as pending unless the server is closed before the test
/// body ends.
Future<void> _stopServer(WidgetTester tester) async {
  await tester.runAsync(HttpWatcherLogger.instance.stopWebServer);
  await tester.pump();
}

void main() {
  // Touch the singleton outside the widget tester's fake-async zone so its
  // connectivity timer is not reported as a pending timer by the test binding.
  setUpAll(() => HttpWatcherLogger.instance.enabled = true);

  tearDown(() => HttpWatcherLogger.instance.stopWebServer());

  group('floating button server icon', () {
    testWidgets('hidden while the server is stopped', (tester) async {
      await _pumpOverlay(tester);
      expect(_serverIcon, findsNothing);
    });

    testWidgets('shown while the server is running', (tester) async {
      await _pumpOverlay(tester);
      await tester.runAsync(HttpWatcherLogger.instance.startWebServer);
      await tester.pump();
      await tester.pump();

      expect(HttpWatcherLogger.instance.webServerRunning, isTrue);
      expect(_serverIcon, findsOneWidget);
    });

    testWidgets('stays clear of a side navigation bar', (tester) async {
      // Landscape Android puts the navigation bar on the right edge.
      tester.view.padding = FakeViewPadding(
        right: 48 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.reset);
      await _pumpOverlay(tester);

      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final button = tester.getRect(find
          .ancestor(
            of: find.byIcon(Icons.network_check_rounded),
            matching: find.byType(Material),
          )
          .first);
      expect(button.right, screenWidth - 48 - 12);
    });

    testWidgets('shown while logging is paused', (tester) async {
      await _pumpOverlay(tester);
      await tester.runAsync(HttpWatcherLogger.instance.startWebServer);
      HttpWatcherLogger.instance.toggleEnabled();
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(_serverIcon, findsOneWidget);
      HttpWatcherLogger.instance.toggleEnabled();
    });
  });

  group('autoStartWebServer', () {
    testWidgets('starts the server on mount in debug', (tester) async {
      await _pumpOverlay(tester, autoStartWebServer: true);
      await _settleServer(tester);

      expect(HttpWatcherLogger.instance.webServerRunning, isTrue);
      expect(_serverIcon, findsOneWidget);
      await _stopServer(tester);
      expect(_serverIcon, findsNothing);
    });

    testWidgets('does nothing when off (the default)', (tester) async {
      await _pumpOverlay(tester);
      await _settleServer(tester);

      expect(HttpWatcherLogger.instance.webServerRunning, isFalse);
    });

    testWidgets('does nothing while the overlay is hidden', (tester) async {
      await _pumpOverlay(tester, autoStartWebServer: true, show: false);
      await _settleServer(tester);

      expect(HttpWatcherLogger.instance.webServerRunning, isFalse);
    });

    testWidgets('starts when switched on by a rebuild', (tester) async {
      await _pumpOverlay(tester);
      await _settleServer(tester);
      expect(HttpWatcherLogger.instance.webServerRunning, isFalse);

      await _pumpOverlay(tester, autoStartWebServer: true);
      await _settleServer(tester);
      expect(HttpWatcherLogger.instance.webServerRunning, isTrue);
      await _stopServer(tester);
    });

    testWidgets('does not restart a server stopped by hand', (tester) async {
      await _pumpOverlay(tester, autoStartWebServer: true);
      await _settleServer(tester);
      expect(HttpWatcherLogger.instance.webServerRunning, isTrue);
      await _stopServer(tester);

      // A rebuild with the option still on must leave the server stopped.
      await _pumpOverlay(tester, autoStartWebServer: true);
      await _settleServer(tester);
      expect(HttpWatcherLogger.instance.webServerRunning, isFalse);
    });
  });
}
