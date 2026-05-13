import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../model/network_log.dart';
import 'watcher_theme.dart';

class InspectorDetailScreen extends StatelessWidget {
  final NetworkLog log;
  const InspectorDetailScreen({super.key, required this.log});

  static Route<void> route(NetworkLog log) =>
      MaterialPageRoute(builder: (_) => InspectorDetailScreen(log: log));

  String _prettyJson(String? raw) {
    if (raw == null || raw.isEmpty) return '(empty)';
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }

  String _bodyStr(dynamic body) {
    if (body == null) return '(none)';
    if (body is String) return _prettyJson(body);
    try {
      return const JsonEncoder.withIndent('  ').convert(body);
    } catch (_) {
      return body.toString();
    }
  }

  Color _statusColor() {
    if (log.isSuccess) return Colors.green;
    if (log.isClientError) return Colors.orange;
    if (log.isServerError) return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WatcherTheme.background,
      appBar: AppBar(
        backgroundColor: WatcherTheme.surface,
        title: Text(
          '${log.method}  ${Uri.parse(log.url).path}',
          style: TextStyle(color: WatcherTheme.textPrimary, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: IconThemeData(color: WatcherTheme.iconColor),
        actions: [
          IconButton(
            icon: Icon(Icons.share_outlined, color: WatcherTheme.iconColor),
            tooltip: 'Share',
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: _fullText()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _infoSection([
            _row('URL', log.url),
            _row('Method', log.method),
            _row('Status', '${log.statusCode ?? "Error"}', valueColor: _statusColor()),
            _row('Duration', '${log.durationMs} ms'),
            _row('Time', log.timestamp.toLocal().toString()),
          ]),
          const SizedBox(height: 12),
          _codeSection('Request Headers', _headersStr(log.requestHeaders)),
          const SizedBox(height: 12),
          _codeSection('Request Body', _bodyStr(log.requestBody)),
          const SizedBox(height: 12),
          _codeSection('Response Body', _prettyJson(log.responseBody)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _headersStr(Map<String, String>? h) {
    if (h == null || h.isEmpty) return '(none)';
    return h.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }

  String _fullText() => '''
=== Summary ===
${_summaryText()}

=== Request Headers ===
${_headersStr(log.requestHeaders)}

=== Request Body ===
${_bodyStr(log.requestBody)}

=== Response Body ===
${_prettyJson(log.responseBody)}
''';

  String _summaryText() => [
        'URL: ${log.url}',
        'Method: ${log.method}',
        'Status: ${log.statusCode ?? "Error"}',
        'Duration: ${log.durationMs} ms',
        'Time: ${log.timestamp.toLocal()}',
      ].join('\n');

  Widget _infoSection(List<Widget> rows) => _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Summary',
                  style: TextStyle(
                      color: WatcherTheme.textSecond,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    Clipboard.setData(ClipboardData(text: _summaryText())),
                child: Icon(Icons.copy, color: WatcherTheme.textHint, size: 16),
              ),
            ]),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      );

  Widget _row(String label, String value, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(label,
                  style: TextStyle(color: WatcherTheme.textHint, fontSize: 12)),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                    color: valueColor ?? WatcherTheme.textPrimary, fontSize: 12),
              ),
            ),
          ],
        ),
      );

  Widget _codeSection(String title, String content) => _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(title,
                  style: TextStyle(
                      color: WatcherTheme.textSecond,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: () => Clipboard.setData(ClipboardData(text: content)),
                child: Icon(Icons.copy, color: WatcherTheme.textHint, size: 16),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              content,
              style: TextStyle(
                  color: WatcherTheme.codeText,
                  fontSize: 11,
                  fontFamily: 'monospace'),
            ),
          ],
        ),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: WatcherTheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(12),
        child: child,
      );
}
