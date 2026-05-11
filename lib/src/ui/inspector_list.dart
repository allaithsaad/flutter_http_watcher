import 'package:flutter/material.dart';
import '../core/network_logger.dart';
import '../model/network_log.dart';
import 'inspector_detail.dart';

class InspectorListScreen extends StatefulWidget {
  const InspectorListScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const InspectorListScreen());

  @override
  State<InspectorListScreen> createState() => _InspectorListScreenState();
}

class _InspectorListScreenState extends State<InspectorListScreen> {
  @override
  void initState() {
    super.initState();
    NetworkLogger.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    NetworkLogger.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  Color _methodColor(String method) {
    switch (method) {
      case 'GET': return const Color(0xFF61AFEF);
      case 'POST': return const Color(0xFF98C379);
      case 'PUT': return const Color(0xFFE5C07B);
      case 'DELETE': return const Color(0xFFE06C75);
      default: return Colors.white70;
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
    final logs = NetworkLogger.instance.logs;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Network Inspector',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white70),
            tooltip: 'Clear',
            onPressed: () => NetworkLogger.instance.clear(),
          ),
          IconButton(
            icon: const Icon(Icons.visibility_off_outlined,
                color: Colors.white70),
            tooltip: 'Hide button',
            onPressed: () {
              NetworkLogger.instance.enabled = false;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(
              child: Text('No requests yet',
                  style: TextStyle(color: Colors.white38)))
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
    );
  }
}
