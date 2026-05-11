import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../model/network_log.dart';

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
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(
          '${log.method}  ${Uri.parse(log.url).path}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
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

  Widget _infoSection(List<Widget> rows) => _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
      );

  Widget _row(String label, String value, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(color: valueColor ?? Colors.white, fontSize: 12),
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
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: () => Clipboard.setData(ClipboardData(text: content)),
                child:
                    const Icon(Icons.copy, color: Colors.white38, size: 16),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              content,
              style: const TextStyle(
                  color: Color(0xFF90EE90),
                  fontSize: 11,
                  fontFamily: 'monospace'),
            ),
          ],
        ),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(12),
        child: child,
      );
}
