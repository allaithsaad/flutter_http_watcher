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

    test('logRequestStart adds a pending entry', () {
      final id = HttpWatcherLogger.instance.logRequestStart(
        method: 'get',
        url: 'https://example.com/test',
      );
      expect(id, isNotNull);
      final log = HttpWatcherLogger.instance.logs.first;
      expect(log.isPending, isTrue);
      expect(log.method, 'GET');
      expect(log.statusCode, isNull);
      expect(log.isFailed, isFalse, reason: 'pending is not failed');
    });

    test('logResponse completes a pending entry in place', () {
      final id = HttpWatcherLogger.instance.logRequestStart(
        method: 'GET',
        url: 'https://example.com/test',
      )!;
      HttpWatcherLogger.instance.logResponse(
        id: id,
        statusCode: 200,
        responseBody: '{"ok":true}',
      );
      expect(HttpWatcherLogger.instance.logs.length, 1,
          reason: 'updates in place, no new entry');
      final log = HttpWatcherLogger.instance.logs.first;
      expect(log.isPending, isFalse);
      expect(log.statusCode, 200);
      expect(log.responseBody, '{"ok":true}');
      expect(log.isSuccess, isTrue);
    });

    test('failRequest marks a pending entry failed', () {
      final id = HttpWatcherLogger.instance.logRequestStart(
        method: 'GET',
        url: 'https://example.com/test',
      )!;
      HttpWatcherLogger.instance.failRequest(id: id, error: 'boom');
      final log = HttpWatcherLogger.instance.logs.first;
      expect(log.isPending, isFalse);
      expect(log.isFailed, isTrue);
      expect(log.responseBody, 'boom');
    });

    test('logResponse for unknown id is a no-op', () {
      HttpWatcherLogger.instance.logResponse(id: 'nope', statusCode: 200);
      expect(HttpWatcherLogger.instance.logs, isEmpty);
    });

    test('logRequestStart is no-op when disabled', () {
      HttpWatcherLogger.instance.enabled = false;
      final id = HttpWatcherLogger.instance.logRequestStart(
        method: 'GET',
        url: 'https://example.com',
      );
      expect(id, isNull);
      expect(HttpWatcherLogger.instance.logs, isEmpty);
      HttpWatcherLogger.instance.enabled = true;
    });

    test('pending entries are excluded from errorCount', () {
      HttpWatcherLogger.instance.logRequestStart(
        method: 'GET',
        url: 'https://example.com',
      );
      expect(HttpWatcherLogger.instance.errorCount, 0);
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

    test('pending log is neither success nor failed', () {
      final log = NetworkLog(
        id: '1', method: 'GET', url: 'https://x.com',
        timestamp: _epoch, pending: true,
      );
      expect(log.isPending, isTrue);
      expect(log.isFailed, isFalse);
      expect(log.isSuccess, isFalse);
    });
  });
}

final _epoch = DateTime(2024);
