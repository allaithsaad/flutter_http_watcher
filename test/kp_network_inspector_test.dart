import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_http_watcher/network_inspector.dart';

void main() {
  setUp(() => HttpWatcherLogger.instance.clear());

  group('HttpWatcherLogger', () {
    test('singleton is accessible', () {
      expect(HttpWatcherLogger.instance, isNotNull);
    });

    test('logs are empty after clear', () {
      expect(HttpWatcherLogger.instance.logs, isEmpty);
    });

    test('logRequest adds an entry', () {
      HttpWatcherLogger.instance.logRequest(
        method: 'GET',
        url: 'https://example.com/test',
        statusCode: 200,
        responseBody: '{"ok":true}',
        startTime: DateTime.now(),
      );
      expect(HttpWatcherLogger.instance.logs.length, 1);
      expect(HttpWatcherLogger.instance.logs.first.method, 'GET');
      expect(HttpWatcherLogger.instance.logs.first.statusCode, 200);
    });

    test('logRequest uppercases method', () {
      HttpWatcherLogger.instance.logRequest(
        method: 'post',
        url: 'https://example.com/test',
        statusCode: 201,
        responseBody: '',
        startTime: DateTime.now(),
      );
      expect(HttpWatcherLogger.instance.logs.first.method, 'POST');
    });

    test('logs are newest first', () {
      HttpWatcherLogger.instance.logRequest(
        method: 'GET', url: 'https://example.com/1',
        statusCode: 200, responseBody: '', startTime: DateTime.now(),
      );
      HttpWatcherLogger.instance.logRequest(
        method: 'POST', url: 'https://example.com/2',
        statusCode: 201, responseBody: '', startTime: DateTime.now(),
      );
      expect(HttpWatcherLogger.instance.logs.first.url,
          contains('/2'));
    });

    test('logRequest is no-op when disabled', () {
      HttpWatcherLogger.instance.enabled = false;
      HttpWatcherLogger.instance.logRequest(
        method: 'GET', url: 'https://example.com',
        statusCode: 200, responseBody: '', startTime: DateTime.now(),
      );
      expect(HttpWatcherLogger.instance.logs, isEmpty);
      HttpWatcherLogger.instance.enabled = true;
    });

    test('toggleEnabled flips enabled', () {
      expect(HttpWatcherLogger.instance.enabled, isTrue);
      HttpWatcherLogger.instance.toggleEnabled();
      expect(HttpWatcherLogger.instance.enabled, isFalse);
      HttpWatcherLogger.instance.toggleEnabled();
      expect(HttpWatcherLogger.instance.enabled, isTrue);
    });

    test('maxEntries limit is respected', () {
      HttpWatcherLogger.instance.maxEntries = 3;
      for (var i = 0; i < 5; i++) {
        HttpWatcherLogger.instance.logRequest(
          method: 'GET', url: 'https://example.com/$i',
          statusCode: 200, responseBody: '', startTime: DateTime.now(),
        );
      }
      expect(HttpWatcherLogger.instance.logs.length, 3);
      HttpWatcherLogger.instance.maxEntries = 300;
    });

    test('clear removes all logs', () {
      HttpWatcherLogger.instance.logRequest(
        method: 'GET', url: 'https://example.com',
        statusCode: 200, responseBody: '', startTime: DateTime.now(),
      );
      HttpWatcherLogger.instance.clear();
      expect(HttpWatcherLogger.instance.logs, isEmpty);
    });

    test('toggleTheme flips isDark', () {
      final initial = HttpWatcherLogger.instance.isDark;
      HttpWatcherLogger.instance.toggleTheme();
      expect(HttpWatcherLogger.instance.isDark, !initial);
      HttpWatcherLogger.instance.toggleTheme();
      expect(HttpWatcherLogger.instance.isDark, initial);
    });
  });

  group('NetworkLog', () {
    test('isSuccess for 2xx', () {
      final log = NetworkLog(
        id: '1', method: 'GET', url: 'https://x.com',
        statusCode: 200, timestamp: _epoch, durationMs: 10,
      );
      expect(log.isSuccess, isTrue);
      expect(log.isClientError, isFalse);
      expect(log.isServerError, isFalse);
      expect(log.isFailed, isFalse);
    });

    test('isClientError for 4xx', () {
      final log = NetworkLog(
        id: '1', method: 'GET', url: 'https://x.com',
        statusCode: 404, timestamp: _epoch, durationMs: 10,
      );
      expect(log.isClientError, isTrue);
      expect(log.isSuccess, isFalse);
    });

    test('isServerError for 5xx', () {
      final log = NetworkLog(
        id: '1', method: 'GET', url: 'https://x.com',
        statusCode: 500, timestamp: _epoch, durationMs: 10,
      );
      expect(log.isServerError, isTrue);
    });

    test('isFailed when statusCode is null', () {
      final log = NetworkLog(
        id: '1', method: 'GET', url: 'https://x.com',
        statusCode: null, timestamp: _epoch, durationMs: 0,
      );
      expect(log.isFailed, isTrue);
    });
  });
}

final _epoch = DateTime(2024);
