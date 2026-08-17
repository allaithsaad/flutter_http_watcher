import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_http_watcher/network_inspector.dart';

/// Starts a request log from [initState] — i.e. while the framework is still
/// building. This is what an app does when it kicks off an API call from a
/// screen's `initState` or a state-management controller's `onInit`.
class _LogsDuringBuild extends StatefulWidget {
  const _LogsDuringBuild();

  @override
  State<_LogsDuringBuild> createState() => _LogsDuringBuildState();
}

class _LogsDuringBuildState extends State<_LogsDuringBuild> {
  @override
  void initState() {
    super.initState();
    HttpWatcherLogger.instance.logRequestStart(
      method: 'GET',
      url: 'https://example.com/config',
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  // Touch the singleton outside the widget tester's fake-async zone so its
  // connectivity timer is not reported as a pending timer by the test binding.
  setUpAll(() => HttpWatcherLogger.instance.enabled = true);

  setUp(() => HttpWatcherLogger.instance.clear());

  testWidgets('logRequestStart during build does not throw', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: HttpWatcherOverlay(
          navigatorKey: navigatorKey,
          child: const _LogsDuringBuild(),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // The entry is still recorded synchronously — only the notification defers.
    expect(HttpWatcherLogger.instance.logs.length, 1);
    expect(HttpWatcherLogger.instance.logs.first.isPending, isTrue);
  });

  testWidgets('logResponse during build does not throw', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final id = HttpWatcherLogger.instance.logRequestStart(
      method: 'GET',
      url: 'https://example.com/config',
    )!;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: HttpWatcherOverlay(
          navigatorKey: navigatorKey,
          child: Builder(
            builder: (_) {
              HttpWatcherLogger.instance.logResponse(
                id: id,
                statusCode: 200,
                responseBody: '{}',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(HttpWatcherLogger.instance.logs.first.isPending, isFalse);
  });

  testWidgets('overlay rebuilds after a deferred notification', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: HttpWatcherOverlay(
          navigatorKey: navigatorKey,
          child: const _LogsDuringBuild(),
        ),
      ),
    );

    // The badge shows the log count, so a successful rebuild renders '1'.
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });
}
