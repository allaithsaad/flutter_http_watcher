import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_http_watcher/network_inspector.dart';

void main() {
  test('HttpWatcherLogger singleton is accessible', () {
    expect(HttpWatcherLogger.instance, isNotNull);
  });

  test('HttpWatcherLogger logs are initially empty', () {
    HttpWatcherLogger.instance.logs.clear();
    expect(HttpWatcherLogger.instance.logs, isEmpty);
  });
}
