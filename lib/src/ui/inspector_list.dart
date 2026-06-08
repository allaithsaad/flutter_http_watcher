import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/network_logger.dart';
import '../model/network_log.dart';
import 'inspector_detail.dart';
import 'inspector_stats.dart';
import 'watcher_theme.dart';

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
  String? _statusFilter; // '2xx', '4xx', '5xx', 'err'

  static const _methods = ['GET', 'POST', 'PUT', 'DELETE'];

  @override
  void initState() {
    super.initState();
    HttpWatcherLogger.instance.addListener(_refresh);
    _search.addListener(
      () => setState(() => _query = _search.text.trim().toLowerCase()),
    );
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
    if (_methodFilter != null) {
      logs = logs.where((l) => l.method == _methodFilter).toList();
    }
    if (_statusFilter != null) {
      logs = logs.where((l) {
        switch (_statusFilter) {
          case '2xx':
            return l.isSuccess;
          case '4xx':
            return l.isClientError;
          case '5xx':
            return l.isServerError;
          case 'err':
            return l.isFailed;
          default:
            return true;
        }
      }).toList();
    }
    if (_query.isNotEmpty) {
      logs = logs
          .where(
            (l) =>
                l.url.toLowerCase().contains(_query) ||
                l.method.toLowerCase().contains(_query) ||
                '${l.statusCode}'.contains(_query),
          )
          .toList();
    }
    return logs;
  }

  Future<void> _exportHar() async {
    final logs = HttpWatcherLogger.instance.logs;
    if (logs.isEmpty) return;
    final entries = logs.map((log) {
      final reqHeaders = (log.requestHeaders ?? {}).entries
          .map((e) => {'name': e.key, 'value': e.value})
          .toList();
      final bodyStr = log.requestBody?.toString() ?? '';
      final uri = Uri.tryParse(log.url) ?? Uri();
      return {
        'startedDateTime': log.timestamp.toUtc().toIso8601String(),
        'time': log.durationMs,
        'request': {
          'method': log.method,
          'url': log.url,
          'httpVersion': 'HTTP/1.1',
          'headers': reqHeaders,
          'queryString': uri.queryParameters.entries
              .map((e) => {'name': e.key, 'value': e.value})
              .toList(),
          'cookies': [],
          'headersSize': -1,
          'bodySize': bodyStr.isEmpty ? -1 : bodyStr.length,
          if (bodyStr.isNotEmpty)
            'postData': {'mimeType': 'application/json', 'text': bodyStr},
        },
        'response': {
          'status': log.statusCode ?? 0,
          'statusText': '',
          'httpVersion': 'HTTP/1.1',
          'headers': [],
          'cookies': [],
          'content': {
            'size': log.responseBody?.length ?? 0,
            'mimeType': 'application/json',
            'text': log.responseBody ?? '',
          },
          'redirectURL': '',
          'headersSize': -1,
          'bodySize': log.responseBody?.length ?? -1,
        },
        'cache': {},
        'timings': {'send': 0, 'wait': log.durationMs, 'receive': 0},
      };
    }).toList();

    final har = {
      'log': {
        'version': '1.2',
        'creator': {'name': 'flutter_http_watcher', 'version': '1.2.0'},
        'entries': entries,
      },
    };

    final json = const JsonEncoder.withIndent('  ').convert(har);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/http_watcher.har');
    await file.writeAsString(json);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'HTTP Watcher HAR Export',
      ),
    );
  }

  Future<void> _saveToFile() async {
    final logs = HttpWatcherLogger.instance.logs;
    if (logs.isEmpty) return;
    final buffer = StringBuffer();
    for (final log in logs) {
      buffer.writeln('[${log.method}] ${log.url}');
      buffer.writeln(
        'Status: ${log.statusCode ?? "Error"}  Duration: ${log.durationMs}ms',
      );
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
      ShareParams(files: [XFile(file.path)], subject: 'HTTP Watcher Logs'),
    );
  }

  void _showWebViewerDialog(BuildContext context) {
    final url = HttpWatcherLogger.instance.webServerUrl ?? '';
    final isLoopback = url.contains('127.0.0.1');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WatcherTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(
              Icons.wifi_tethering,
              color: Colors.greenAccent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Web Viewer',
              style: TextStyle(color: WatcherTheme.textPrimary, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLoopback) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: Colors.orange,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Device not on WiFi — URL only works on this device.',
                        style: TextStyle(
                          color: Colors.orange.shade300,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              isLoopback
                  ? 'Open this URL on this device:'
                  : 'Open this URL in any browser on the same WiFi:',
              style: TextStyle(color: WatcherTheme.textHint, fontSize: 13),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: url));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('URL copied'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: WatcherTheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        url,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.copy_outlined,
                      color: Colors.greenAccent,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the URL to copy it',
              style: TextStyle(color: WatcherTheme.textHint, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await HttpWatcherLogger.instance.stopWebServer();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              'Stop Server',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(color: WatcherTheme.textPrimary),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent.withValues(alpha: 0.15),
            ),
            icon: const Icon(
              Icons.open_in_browser,
              color: Colors.greenAccent,
              size: 16,
            ),
            label: const Text(
              'Open',
              style: TextStyle(color: Colors.greenAccent),
            ),
            onPressed: () async {
              final uri = Uri.tryParse(url);
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Material(
          color: WatcherTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: WatcherTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  _menuTile(
                    icon: Icons.bar_chart_rounded,
                    label: 'Stats',
                    subtitle: 'Success rate, avg duration, top hosts',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(InspectorStatsScreen.route());
                    },
                  ),
                  _menuTile(
                    icon: HttpWatcherLogger.instance.webServerRunning
                        ? Icons.wifi_tethering
                        : Icons.wifi_tethering_off_outlined,
                    label: HttpWatcherLogger.instance.webServerRunning
                        ? 'Web Viewer — Running'
                        : 'Web Viewer',
                    subtitle: HttpWatcherLogger.instance.webServerRunning
                        ? (HttpWatcherLogger.instance.webServerUrl ?? '')
                        : 'Open logs in any browser on the same WiFi',
                    iconColor: HttpWatcherLogger.instance.webServerRunning
                        ? Colors.greenAccent
                        : WatcherTheme.iconColor,
                    onTap: () async {
                      if (HttpWatcherLogger.instance.webServerRunning) {
                        Navigator.pop(context);
                        _showWebViewerDialog(context);
                      } else {
                        final url = await HttpWatcherLogger.instance
                            .startWebServer();
                        if (!context.mounted) return;
                        setSt(() {});
                        if (url != null) {
                          Navigator.pop(context);
                          _showWebViewerDialog(context);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not start web server. Check network permissions.',
                              ),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  _menuTile(
                    icon: Icons.text_snippet_outlined,
                    label: 'Save as .txt',
                    subtitle: 'Export all logs as a plain text file',
                    onTap: () {
                      Navigator.pop(context);
                      _saveToFile();
                    },
                  ),
                  _menuTile(
                    icon: Icons.code_rounded,
                    label: 'Export as .har',
                    subtitle: 'Import into Postman, Charles, or DevTools',
                    onTap: () {
                      Navigator.pop(context);
                      _exportHar();
                    },
                  ),
                  _menuTile(
                    icon: WatcherTheme.isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    label: WatcherTheme.isDark ? 'Light mode' : 'Dark mode',
                    subtitle: 'Toggle inspector theme',
                    onTap: () {
                      HttpWatcherLogger.instance.toggleTheme();
                      setSt(() {});
                    },
                  ),
                  _menuTile(
                    icon: HttpWatcherLogger.instance.enabled
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    label: HttpWatcherLogger.instance.enabled
                        ? 'Pause logging'
                        : 'Resume logging',
                    subtitle: HttpWatcherLogger.instance.enabled
                        ? 'Stop capturing new requests'
                        : 'Start capturing requests again',
                    iconColor: HttpWatcherLogger.instance.enabled
                        ? WatcherTheme.iconColor
                        : Colors.greenAccent,
                    onTap: () {
                      HttpWatcherLogger.instance.toggleEnabled();
                      setSt(() {});
                    },
                  ),
                  _menuTile(
                    icon: Icons.delete_outline,
                    label: 'Clear all',
                    subtitle: 'Remove all logged requests',
                    iconColor: Colors.redAccent,
                    onTap: () {
                      Navigator.pop(context);
                      HttpWatcherLogger.instance.clear();
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) => ListTile(
    leading: Icon(icon, color: iconColor ?? WatcherTheme.iconColor),
    title: Text(label, style: TextStyle(color: WatcherTheme.textPrimary)),
    subtitle: Text(
      subtitle,
      style: TextStyle(color: WatcherTheme.textHint, fontSize: 12),
    ),
    onTap: onTap,
  );

  Color _methodColor(String method) {
    switch (method) {
      case 'GET':
        return const Color(0xFF61AFEF);
      case 'POST':
        return const Color(0xFF98C379);
      case 'PUT':
        return const Color(0xFFE5C07B);
      case 'DELETE':
        return const Color(0xFFE06C75);
      default:
        return WatcherTheme.textSecond;
    }
  }

  Color _statusColor(NetworkLog log) {
    if (log.isSuccess) return Colors.green;
    if (log.isClientError) return Colors.orange;
    if (log.isServerError) return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filtered;
    return Scaffold(
      backgroundColor: WatcherTheme.background,
      appBar: AppBar(
        backgroundColor: WatcherTheme.surface,
        title: Text(
          'Network Inspector',
          style: TextStyle(color: WatcherTheme.textPrimary),
        ),
        iconTheme: IconThemeData(color: WatcherTheme.iconColor),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: WatcherTheme.iconColor),
            tooltip: 'Options',
            onPressed: () => _showMenu(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _search,
              style: TextStyle(color: WatcherTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search URL, method, status...',
                hintStyle: TextStyle(
                  color: WatcherTheme.textHint,
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: WatcherTheme.textHint,
                  size: 18,
                ),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close,
                          color: WatcherTheme.textHint,
                          size: 18,
                        ),
                        onPressed: () => _search.clear(),
                      )
                    : null,
                filled: true,
                fillColor: WatcherTheme.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
            child: Row(
              children: [
                _chip(
                  'All',
                  _methodFilter == null,
                  () => setState(() => _methodFilter = null),
                ),
                ..._methods.map(
                  (m) => _chip(
                    m,
                    _methodFilter == m,
                    () => setState(
                      () => _methodFilter = _methodFilter == m ? null : m,
                    ),
                    color: _methodColor(m),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: Row(
              children: [
                _chip(
                  'All',
                  _statusFilter == null,
                  () => setState(() => _statusFilter = null),
                ),
                _chip(
                  '2xx',
                  _statusFilter == '2xx',
                  () => setState(
                    () => _statusFilter = _statusFilter == '2xx' ? null : '2xx',
                  ),
                  color: Colors.green,
                ),
                _chip(
                  '4xx',
                  _statusFilter == '4xx',
                  () => setState(
                    () => _statusFilter = _statusFilter == '4xx' ? null : '4xx',
                  ),
                  color: Colors.orange,
                ),
                _chip(
                  '5xx',
                  _statusFilter == '5xx',
                  () => setState(
                    () => _statusFilter = _statusFilter == '5xx' ? null : '5xx',
                  ),
                  color: Colors.red,
                ),
                _chip(
                  'Error',
                  _statusFilter == 'err',
                  () => setState(
                    () => _statusFilter = _statusFilter == 'err' ? null : 'err',
                  ),
                  color: Colors.grey,
                ),
              ],
            ),
          ),
          Divider(color: WatcherTheme.divider, height: 1),
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Text(
                      _query.isNotEmpty ||
                              _methodFilter != null ||
                              _statusFilter != null
                          ? 'No matching requests'
                          : 'No requests yet',
                      style: TextStyle(color: WatcherTheme.textHint),
                    ),
                  )
                : ListView.separated(
                    itemCount: logs.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: WatcherTheme.divider, height: 1),
                    itemBuilder: (context, i) {
                      final log = logs[i];
                      return InkWell(
                        onTap: () => Navigator.of(
                          context,
                        ).push(InspectorDetailScreen.route(log)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 52,
                                child: Text(
                                  log.method,
                                  style: TextStyle(
                                    color: _methodColor(log.method),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      Uri.parse(log.url).path,
                                      style: TextStyle(
                                        color: WatcherTheme.textPrimary,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      Uri.parse(log.url).host,
                                      style: TextStyle(
                                        color: WatcherTheme.textHint,
                                        fontSize: 11,
                                      ),
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
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${log.durationMs}ms',
                                    style: TextStyle(
                                      color: WatcherTheme.textHint,
                                      fontSize: 11,
                                    ),
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

  Widget _chip(
    String label,
    bool selected,
    VoidCallback onTap, {
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? (color ?? WatcherTheme.textPrimary).withValues(alpha: 0.15)
              : WatcherTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? (color ?? WatcherTheme.textSecond)
                : WatcherTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? (color ?? WatcherTheme.textPrimary)
                : WatcherTheme.textHint,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    ),
  );
}
