import 'package:flutter/material.dart';
import '../core/network_logger.dart';
import 'watcher_theme.dart';

class InspectorStatsScreen extends StatelessWidget {
  const InspectorStatsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const InspectorStatsScreen());

  @override
  Widget build(BuildContext context) {
    final logs = HttpWatcherLogger.instance.logs;

    if (logs.isEmpty) {
      return Scaffold(
        backgroundColor: WatcherTheme.background,
        appBar: _appBar(),
        body: Center(
          child: Text('No requests yet',
              style: TextStyle(color: WatcherTheme.textHint)),
        ),
      );
    }

    final total = logs.length;
    final success = logs.where((l) => l.isSuccess).length;
    final clientErr = logs.where((l) => l.isClientError).length;
    final serverErr = logs.where((l) => l.isServerError).length;
    final failed = logs.where((l) => l.isFailed).length;
    final avgDuration =
        logs.map((l) => l.durationMs).reduce((a, b) => a + b) ~/ total;
    final slowest = [...logs]
      ..sort((a, b) => b.durationMs.compareTo(a.durationMs));

    final methodCounts = <String, int>{};
    for (final log in logs) {
      methodCounts[log.method] = (methodCounts[log.method] ?? 0) + 1;
    }

    final hostCounts = <String, int>{};
    for (final log in logs) {
      final host = Uri.tryParse(log.url)?.host ?? log.url;
      hostCounts[host] = (hostCounts[host] ?? 0) + 1;
    }
    final topHosts = hostCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      backgroundColor: WatcherTheme.background,
      appBar: _appBar(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Overview'),
          const SizedBox(height: 8),
          Row(children: [
            _statCard('Total', '$total', WatcherTheme.textSecond),
            const SizedBox(width: 8),
            _statCard('Avg Duration', '${avgDuration}ms', WatcherTheme.textSecond),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _statCard('Success', '$success', Colors.green),
            const SizedBox(width: 8),
            _statCard('Client Err', '$clientErr', Colors.orange),
            const SizedBox(width: 8),
            _statCard('Server Err', '${serverErr + failed}', Colors.red),
          ]),
          const SizedBox(height: 16),
          _sectionTitle('Success Rate'),
          const SizedBox(height: 8),
          _card(_SuccessBar(success: success, total: total)),
          const SizedBox(height: 16),
          _sectionTitle('By Method'),
          const SizedBox(height: 8),
          _card(Column(
            children: methodCounts.entries
                .map((e) => _barRow(e.key, e.value, total, _methodColor(e.key)))
                .toList(),
          )),
          const SizedBox(height: 16),
          _sectionTitle('Top Hosts'),
          const SizedBox(height: 8),
          _card(Column(
            children: topHosts
                .take(5)
                .map((e) => _barRow(e.key, e.value, total, WatcherTheme.textSecond))
                .toList(),
          )),
          const SizedBox(height: 16),
          _sectionTitle('Slowest Requests'),
          const SizedBox(height: 8),
          _card(Column(
            children: slowest
                .take(5)
                .map((log) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Text(log.method,
                            style: TextStyle(
                                color: _methodColor(log.method),
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            Uri.tryParse(log.url)?.path ?? log.url,
                            style: TextStyle(
                                color: WatcherTheme.textPrimary, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('${log.durationMs}ms',
                            style: const TextStyle(
                                color: Colors.orange, fontSize: 12)),
                      ]),
                    ))
                .toList(),
          )),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  AppBar _appBar() => AppBar(
        backgroundColor: WatcherTheme.surface,
        title: Text('Stats',
            style: TextStyle(color: WatcherTheme.textPrimary)),
        iconTheme: IconThemeData(color: WatcherTheme.iconColor),
      );

  Widget _sectionTitle(String title) => Text(title,
      style: TextStyle(
          color: WatcherTheme.textSecond,
          fontSize: 13,
          fontWeight: FontWeight.bold));

  Widget _card(Widget child) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: WatcherTheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(12),
        child: child,
      );

  Widget _statCard(String label, String value, Color color) => Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: WatcherTheme.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        color: WatcherTheme.textHint, fontSize: 11)),
              ]),
        ),
      );

  Widget _barRow(String label, int count, int total, Color color) {
    final pct = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 72,
          child: Text(label,
              style:
                  TextStyle(color: WatcherTheme.textSecond, fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: WatcherTheme.divider,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$count',
            style: TextStyle(color: WatcherTheme.textHint, fontSize: 12)),
      ]),
    );
  }

  Color _methodColor(String method) {
    switch (method) {
      case 'GET':    return const Color(0xFF61AFEF);
      case 'POST':   return const Color(0xFF98C379);
      case 'PUT':    return const Color(0xFFE5C07B);
      case 'DELETE': return const Color(0xFFE06C75);
      default:       return WatcherTheme.textSecond;
    }
  }
}

class _SuccessBar extends StatelessWidget {
  final int success;
  final int total;
  const _SuccessBar({required this.success, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : success / total;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('${(pct * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
                color: Colors.green,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const Spacer(),
        Text('$success / $total',
            style: TextStyle(color: WatcherTheme.textHint, fontSize: 12)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct,
          backgroundColor: WatcherTheme.divider,
          valueColor: const AlwaysStoppedAnimation(Colors.green),
          minHeight: 10,
        ),
      ),
    ]);
  }
}
