import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_http_watcher/network_inspector.dart';
import 'package:flutter_http_watcher/src/ui/inspector_list.dart';

const _darkSurface = Color(0xFF1A1A2E);
const _lightSurface = Colors.white;

/// Pumps the inspector inside an app running [brightness], then opens the
/// options ("settings") bottom sheet.
Future<void> _openSettingsSheet(
  WidgetTester tester,
  Brightness brightness,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: const InspectorListScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
}

/// The theme row sits below the fold in the test viewport, so scroll it in
/// before touching it.
Future<Finder> _themeRow(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  return finder;
}

/// The colour actually painted behind the sheet's rows.
Color? _sheetSurface(WidgetTester tester) => tester
    .widget<Material>(
      find
          .ancestor(of: find.text('Stats'), matching: find.byType(Material))
          .first,
    )
    .color;

void main() {
  // Touch the singleton outside the widget tester's fake-async zone so its
  // connectivity timer is not reported as a pending timer by the test binding.
  setUpAll(() => HttpWatcherLogger.instance.enabled = true);

  setUp(() {
    HttpWatcherLogger.instance.clear();
    HttpWatcherLogger.instance.followAppTheme();
  });

  group('settings sheet follows the host app brightness', () {
    testWidgets('light app renders a light sheet', (tester) async {
      await _openSettingsSheet(tester, Brightness.light);
      expect(_sheetSurface(tester), _lightSurface);
    });

    testWidgets('dark app renders a dark sheet', (tester) async {
      await _openSettingsSheet(tester, Brightness.dark);
      expect(_sheetSurface(tester), _darkSurface);
    });

    testWidgets('system is the default mode', (tester) async {
      expect(HttpWatcherLogger.instance.themeMode, WatcherThemeMode.system);
    });
  });

  group('explicit override', () {
    testWidgets('pinned dark survives a light app', (tester) async {
      HttpWatcherLogger.instance.isDark = true;
      await _openSettingsSheet(tester, Brightness.light);
      expect(HttpWatcherLogger.instance.themeMode, WatcherThemeMode.dark);
      expect(_sheetSurface(tester), _darkSurface);
    });

    testWidgets('toggling in a dark app pins light', (tester) async {
      await _openSettingsSheet(tester, Brightness.dark);
      expect(_sheetSurface(tester), _darkSurface);

      await tester.tap(await _themeRow(tester, 'Light mode'));
      await tester.pumpAndSettle();

      expect(HttpWatcherLogger.instance.themeMode, WatcherThemeMode.light);
      expect(_sheetSurface(tester), _lightSurface);
    });

    testWidgets('long press hands control back to the app', (tester) async {
      HttpWatcherLogger.instance.isDark = true;
      await _openSettingsSheet(tester, Brightness.light);
      expect(_sheetSurface(tester), _darkSurface);

      await tester.longPress(await _themeRow(tester, 'Light mode'));
      await tester.pumpAndSettle();

      expect(HttpWatcherLogger.instance.themeMode, WatcherThemeMode.system);
      expect(_sheetSurface(tester), _lightSurface);
    });
  });
}
