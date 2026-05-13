import 'package:flutter/material.dart';
import '../core/network_logger.dart';
import 'inspector_list.dart';

Color _statusColor(NetworkStatus s) {
  switch (s) {
    case NetworkStatus.online:
      return const Color(0xFF4CAF50);
    case NetworkStatus.offline:
      return const Color(0xFFF44336);
    case NetworkStatus.unknown:
      return const Color(0xFF9E9E9E);
  }
}

/// Wraps [child] and adds a draggable floating inspector button.
///
/// Place this as the outermost widget in your `MaterialApp` builder:
///
/// ```dart
/// builder: (context, child) => HttpWatcherOverlay(
///   navigatorKey: Get.key, // pass your app's navigator key
///   child: child!,
/// ),
/// ```
///
/// Set [show] to `false` to hide the button (e.g. via a feature flag).
class HttpWatcherOverlay extends StatefulWidget {
  final Widget child;

  /// Whether to show the inspector button.
  final bool show;

  /// The navigator key used to push the inspector screen.
  /// Pass your app's [navigatorKey] or `Get.key` (for GetX apps).
  final GlobalKey<NavigatorState> navigatorKey;

  const HttpWatcherOverlay({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.show = true,
  });

  @override
  State<HttpWatcherOverlay> createState() =>
      _HttpWatcherOverlayState();
}

class _HttpWatcherOverlayState extends State<HttpWatcherOverlay> {
  double _top = 120;
  double _right = 12;

  @override
  void initState() {
    super.initState();
    HttpWatcherLogger.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    HttpWatcherLogger.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (!widget.show) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: _top,
          right: _right,
          child: GestureDetector(
            onPanUpdate: (d) => setState(() {
              final size = MediaQuery.of(context).size;
              _top = (_top + d.delta.dy).clamp(0.0, size.height - 48);
              _right = (_right - d.delta.dx).clamp(0.0, size.width - 72);
            }),
            child: _InspectorButton(
              count: HttpWatcherLogger.instance.logs.length,
              status: HttpWatcherLogger.instance.networkStatus,
              paused: !HttpWatcherLogger.instance.enabled,
              onTap: () {
                if (!HttpWatcherLogger.instance.enabled) {
                  HttpWatcherLogger.instance.toggleEnabled();
                  return;
                }
                final nav = widget.navigatorKey.currentState ??
                    Navigator.of(context, rootNavigator: true);
                nav.push(InspectorListScreen.route());
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _InspectorButton extends StatelessWidget {
  final int count;
  final NetworkStatus status;
  final bool paused;
  final VoidCallback onTap;

  const _InspectorButton({
    required this.count,
    required this.status,
    required this.paused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(24),
      color: paused
          ? const Color(0xDD2E1A1A)
          : const Color(0xDD1A1A2E),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (paused)
                const Icon(Icons.play_arrow_rounded,
                    color: Colors.greenAccent, size: 18)
              else ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.network_check_rounded,
                    color: Colors.white, size: 18),
                if (count > 0) ...[
                  const SizedBox(width: 5),
                  Text(
                    '$count',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
