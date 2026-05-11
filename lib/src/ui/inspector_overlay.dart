import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/network_logger.dart';
import 'inspector_list.dart';

/// Wraps [child] and adds a draggable floating inspector button in debug mode.
///
/// Place this as the outermost widget in your `MaterialApp` builder:
///
/// ```dart
/// builder: (context, child) => NetworkInspectorOverlay(child: child!),
/// ```
///
/// Set [show] to `false` to hide the button (e.g. via a feature flag).
class NetworkInspectorOverlay extends StatefulWidget {
  final Widget child;

  /// Whether to show the inspector button. Has no effect in release builds.
  final bool show;

  const NetworkInspectorOverlay({
    super.key,
    required this.child,
    this.show = true,
  });

  @override
  State<NetworkInspectorOverlay> createState() =>
      _NetworkInspectorOverlayState();
}

class _NetworkInspectorOverlayState extends State<NetworkInspectorOverlay> {
  double _top = 120;
  double _right = 12;

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

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || !widget.show || !NetworkLogger.instance.enabled) {
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
              count: NetworkLogger.instance.logs.length,
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .push(InspectorListScreen.route()),
            ),
          ),
        ),
      ],
    );
  }
}

class _InspectorButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _InspectorButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(24),
      color: const Color(0xDD1A1A2E),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
          ),
        ),
      ),
    );
  }
}
