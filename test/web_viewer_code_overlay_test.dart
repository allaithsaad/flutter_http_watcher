import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_http_watcher/network_inspector.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> _pumpOverlay(
  WidgetTester tester, {
  String? code,
  bool requiresCode = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: _navigatorKey,
      home: HttpWatcherOverlay(
        navigatorKey: _navigatorKey,
        webServerCode: code,
        webServerRequiresCode: requiresCode,
        child: const SizedBox.shrink(),
      ),
    ),
  );
  await tester.pump(); // flush the deferred notification
}

void main() {
  final logger = HttpWatcherLogger.instance;

  // Touch the singleton outside the fake-async zone (connectivity timer).
  setUpAll(() => logger.enabled = true);

  tearDown(() {
    logger.setWebServerCode(null);
    logger.setWebServerRequiresCode(true);
  });

  testWidgets('defaults: random code, code required', (tester) async {
    await _pumpOverlay(tester);
    expect(logger.webServerHasCustomCode, isFalse);
    expect(logger.webServerRequiresCode, isTrue);
  });

  testWidgets('webServerCode sets a custom code on mount', (tester) async {
    await _pumpOverlay(tester, code: 'abcdef');
    expect(tester.takeException(), isNull);
    expect(logger.webServerHasCustomCode, isTrue);
  });

  testWidgets('an invalid webServerCode is ignored', (tester) async {
    await _pumpOverlay(tester, code: 'ab');
    expect(tester.takeException(), isNull);
    expect(logger.webServerHasCustomCode, isFalse);
  });

  testWidgets('webServerRequiresCode: false turns the code off',
      (tester) async {
    await _pumpOverlay(tester, requiresCode: false);
    expect(tester.takeException(), isNull);
    expect(logger.webServerRequiresCode, isFalse);
  });

  testWidgets('a rebuild does not undo a change made on the phone',
      (tester) async {
    await _pumpOverlay(tester, code: 'abcdef');
    logger.setWebServerRequiresCode(false); // as from the dialog's switch
    logger.setWebServerCode(null); // "Use random code"
    await _pumpOverlay(tester, code: 'abcdef');

    expect(logger.webServerHasCustomCode, isFalse);
    expect(logger.webServerRequiresCode, isFalse);
  });

  testWidgets('connectivity checks run only while the button is shown',
      (tester) async {
    Future<void> pump(bool show) => tester.pumpWidget(MaterialApp(
          navigatorKey: _navigatorKey,
          home: HttpWatcherOverlay(
            navigatorKey: _navigatorKey,
            show: show,
            child: const SizedBox.shrink(),
          ),
        ));

    await pump(false); // e.g. show: kDebugMode in a release build
    expect(logger.debugConnectivityPolling, isFalse);
    await pump(true);
    expect(logger.debugConnectivityPolling, isTrue);
    await pump(false);
    expect(logger.debugConnectivityPolling, isFalse);
  });

  testWidgets('webServerLocalOnly is applied on mount', (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: _navigatorKey,
      home: HttpWatcherOverlay(
        navigatorKey: _navigatorKey,
        webServerLocalOnly: true,
        child: const SizedBox.shrink(),
      ),
    ));
    expect(logger.webServerLocalOnly, isTrue);
    await tester.runAsync(() => logger.setWebServerLocalOnly(false));
  });

  testWidgets('changing the parameter applies the new value',
      (tester) async {
    await _pumpOverlay(tester, code: 'abcdef');
    await _pumpOverlay(tester, code: null);
    expect(logger.webServerHasCustomCode, isFalse);
  });
}
