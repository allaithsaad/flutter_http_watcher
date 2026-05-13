import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/network_logger.dart';
import '../model/network_log.dart';
import 'inspector_detail.dart';
import 'inspector_stats.dart';

class InspectorListScreen extends StatefulWidget {
  const InspectorListScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const InspectorListScreen());

  @override
  State<InspectorListScreen> createState() => _InspectorListScreenState();
}

class _InspectorListScreenState extends State<InspectorListScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _methodFilter;

  static const _methods = ['GET', 'POST', 'PUT', 'DELETE'];

  @override
  void initState() {
    super.initState();
    HttpWatcherLogger.instance.addListener(_refresh);
    _search.addListener(() => setState(() => _query = _search.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    HttpWatcherLogger.instance.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  List<NetworkLog> get _filtered {
    var logs = HttpWatcherLogger.instance.logs.toList();
    if (_methodFilter != null) logs = logs.where((l) => l.method == _methodFilter).toList();
    if (_query.isNotEmpty) {
      logs = logs.where((l) =>
        l.url.toLowerCase().contains(_query) ||
        l.method.toLowerCase().contains(_query) ||
        '${l.statusCode}'.contains(_query),
      ).toList();
    }
    return logs;
  }

  Future<void> _saveToFile() async {
    final logs = HttpWatcherLogger.instance.logs;
    if (logs.isEmpty) return;

    final buffer = StringBuffer();
    for (final log in logs) {
      buffer.writeln('[${ log.method}] ${log.url}');
      buffer.writeln('Status: ${log.statusCode ?? "Error"}  Duration: ${log.durationMs}ms');
      buffer.writeln('Time: ${log.timestamp.toLocal()}');
      if (log.requestHeaders != null) {
        buffer.writeln('--- Request Headers ---');
        log.requestHeaders!.forEach((k, v) => buffer.writeln('$k: $v'));
      }
      if (log.requestBody != null) {
        buffer.writeln('--- Request Body ---');
        buffer.writeln(log.requestBody);
      }
      buffer.writeln('--- Response Body ---');
      buffer.writeln(log.responseBody ?? '(empty)');
      buffer.writeln('=' * 60);
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/http_watcher_logs.txt');
    await file.writeAsString(buffer.toString());

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'HTTP Watcher Logs',
      ),
    );
  }

  Color _methodColor(String method) {
    switch (method) {
      case 'GET':    return const Color(0xFF61AFEF);
      case 'POST':   return const Color(0xFF98C379);
      case 'PUT':    return const Color(0xFFE5C07B);
      case 'DELETE': return const Color(0xFFE06C75);
      default:       return Colors.white70;
    }
  }

  Color _statusColor(NetworkLog log) {
    if (log.isSuccess)    return Colors.green;
    if (log.isClientError) return Colors.orange;
    if (log.isServerError) return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Network Inspector', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded, color: Colors.white70),
            tooltip: 'Stats',
            onPressed: () => Navigator.of(context).push(InspectorStatsScreen.route()),
          ),
          IconButton(
            icon: const Icon(Icons.save_alt_outlined, color: Colors.white70),
            tooltip: 'Save to file',
            onPressed: _saveToFile,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white70),
            tooltip: 'Clear',
            onPressed: () => HttpWatcherLogger.instance.clear(),
          ),
          IconButton(
            icon: Icon(
              HttpWatcherLogger.instance.enabled
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
              color: HttpWatcherLogger.instance.enabled
                  ? Colors.white70
                  : Colors.greenAccent,
            ),
            tooltip: HttpWatcherLogger.instance.enabled ? 'Pause' : 'Resume',
            onPressed: HttpWatcherLogger.instance.toggleEnabled,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _search,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search URL, method, status...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                        onPressed: () => _search.clear(),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Method filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                _chip('All', _methodFilter == null, () => setState(() => _methodFilter = null)),
                ..._methods.map((m) => _chip(
                  m,
                  _methodFilter == m,
                  () => setState(() => _methodFilter = _methodFilter == m ? null : m),
                  color: _methodColor(m),
                )),
              ],
            ),
          ),
          const Divider(color: Color(0xFF2A2A3E), height: 1),
          // List
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Text(
                      _query.isNotEmpty || _methodFilter != null
                          ? 'No matching requests'
                          : 'No requests yet',
                      style: const TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.separated(
                    itemCount: logs.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Color(0xFF2A2A3E), height: 1),
                    itemBuilder: (context, i) {
                      final log = logs[i];
                      return InkWell(
                        onTap: () => Navigator.of(context)
                            .push(InspectorDetailScreen.route(log)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 52,
                                child: Text(log.method,
                                    style: TextStyle(
                                        color: _methodColor(log.method),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      Uri.parse(log.url).path,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      Uri.parse(log.url).host,
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${log.statusCode ?? "ERR"}',
                                    style: TextStyle(
                                        color: _statusColor(log),
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '${log.durationMs}ms',
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Color? color}) =>
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? (color ?? Colors.white).withValues(alpha: 0.15)
                  : const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? (color ?? Colors.white54) : Colors.white12,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? (color ?? Colors.white) : Colors.white38,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
}
