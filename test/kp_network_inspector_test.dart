import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_http_watcher/network_inspector.dart';

void main() {
  test('NetworkLogger singleton is accessible', () {
    expect(NetworkLogger.instance, isNotNull);
  });

  test('NetworkLogger logs are initially empty', () {
    NetworkLogger.instance.logs.clear();
    expect(NetworkLogger.instance.logs, isEmpty);
  });
}
