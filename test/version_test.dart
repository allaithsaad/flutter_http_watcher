import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_http_watcher/src/version.dart';

/// The version in `pubspec.yaml`, which is what pub.dev publishes.
String _pubspecVersion() {
  final line = File('pubspec.yaml')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('version:'));
  return line.split(':')[1].trim();
}

void main() {
  // The HAR export stamps [kWatcherVersion] into `log.creator.version`, so a
  // drift here ships exports that misreport which version produced them —
  // exactly what happened when it sat hardcoded at '1.2.0' through 1.3.1.
  test('kWatcherVersion matches pubspec.yaml', () {
    expect(kWatcherVersion, _pubspecVersion());
  });
}
