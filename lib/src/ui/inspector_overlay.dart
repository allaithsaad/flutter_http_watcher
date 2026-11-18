import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/network_logger.dart';
import 'inspector_list.dart';
import 'watcher_theme.dart';

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
/// Set [icon] to replace the default network icon with any [IconData].
/// Set [autoStartWebServer] to `true` to start the Web Viewer on launch in
/// debug builds.
class HttpWatcherOverlay extends StatefulWidget {
  final Widget child;

  /// Whether to show the inspector button.
  final bool show;

  /// The navigator key used to push the inspector screen.
  /// Pass your app's [navigatorKey] or `Get.key` (for GetX apps).
  final GlobalKey<NavigatorState> navigatorKey;

  /// Custom icon for the floating button. Defaults to [Icons.network_check_rounded].
  final IconData? icon;

  /// Start the Web Viewer server as soon as the overlay is mounted, so the
  /// logs are reachable from a browser without opening the inspector first.
  ///
  /// Only takes effect in debug builds ([kDebugMode]) and while [show] is
  /// `true`; it is ignored in profile and release builds and on Flutter web.
  /// The URL is printed to the debug console. Defaults to `false`.
  final bool autoStartWebServer;

  /// A fixed code for the Web Viewer (4–64 characters, no spaces) instead of
  /// a random 6-digit one each start. Can also be changed on the phone in
  /// **⋮ → Web Viewer**. An invalid value is ignored with a debug message.
  final String? webServerCode;

  /// Whether a browser must enter the code before it sees the logs. Defaults
  /// to `true`. With `false`, anyone on the same network can read every
  /// logged header and body, including auth tokens.
  final bool webServerRequiresCode;

  /// Listen only on this device (127.0.0.1) instead of the Wi-Fi address, so
  /// the logs never cross the network. Open them from a computer over USB:
  /// `adb forward tcp:9742 tcp:9742`, then `http://localhost:9742`. Defaults
  /// to `false`. Can also be switched on the phone in **⋮ → Web Viewer**.
  final bool webServerLocalOnly;

  const HttpWatcherOverlay({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.show = true,
    this.icon,
    this.autoStartWebServer = false,
    this.webServerCode,
    this.webServerRequiresCode = true,
    this.webServerLocalOnly = false,
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
    // Listen only while the button is shown: a hidden overlay (e.g. `show:
    // kDebugMode` in release) then keeps the logger's connectivity check off.
    if (widget.show) HttpWatcherLogger.instance.addListener(_refresh);
    _applyWebServerCode();
    _applyWebServerRequiresCode();
    _applyWebServerLocalOnly();
    deleteWatcherExports();
    _maybeAutoStartWebServer();
  }

  void _applyWebServerLocalOnly() {
    if (widget.webServerLocalOnly ==
        HttpWatcherLogger.instance.webServerLocalOnly) {
      return;
    }
    HttpWatcherLogger.instance.setWebServerLocalOnly(widget.webServerLocalOnly);
  }

  // Applied on mount and when the parameter changes, so a change made on the
  // phone in ⋮ → Web Viewer isn't undone by every rebuild.
  void _applyWebServerCode() {
    final code = widget.webServerCode;
    final problem =
        code == null ? null : HttpWatcherLogger.validateWebServerCode(code);
    if (problem != null) {
      debugPrint('[HttpWatcher] webServerCode ignored: $problem');
      return;
    }
    if (code == null && !HttpWatcherLogger.instance.webServerHasCustomCode) {
      return;
    }
    HttpWatcherLogger.instance.setWebServerCode(code);
  }

  void _applyWebServerRequiresCode() {
    if (widget.webServerRequiresCode ==
        HttpWatcherLogger.instance.webServerRequiresCode) {
      return;
    }
    HttpWatcherLogger.instance
        .setWebServerRequiresCode(widget.webServerRequiresCode);
  }

  @override
  void didUpdateWidget(HttpWatcherOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.webServerCode != oldWidget.webServerCode) _applyWebServerCode();
    if (widget.webServerRequiresCode != oldWidget.webServerRequiresCode) {
      _applyWebServerRequiresCode();
    }
    if (widget.webServerLocalOnly != oldWidget.webServerLocalOnly) {
      _applyWebServerLocalOnly();
    }
    if (widget.show != oldWidget.show) {
      final logger = HttpWatcherLogger.instance;
      widget.show
          ? logger.addListener(_refresh)
          : logger.removeListener(_refresh);
    }
    // Only react to the option being switched on (e.g. by a hot reload), so a
    // server the developer stopped by hand is not restarted on every rebuild.
    final wasOn = oldWidget.autoStartWebServer && oldWidget.show;
    if (!wasOn) _maybeAutoStartWebServer();
  }

  Future<void> _maybeAutoStartWebServer() async {
    if (!kDebugMode || kIsWeb) return;
    if (!widget.autoStartWebServer || !widget.show) return;
    final logger = HttpWatcherLogger.instance;
    if (logger.webServerRunning) return;
    // startWebServer prints the URL and code to the debug console.
    await logger.startWebServer();
  }

  @override
  void dispose() {
    if (widget.show) HttpWatcherLogger.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // The overlay wraps the whole app, so this is where the inspector picks up
    // the app's brightness — and where it re-reads it when the app's theme
    // changes, even while no inspector screen is open.
    WatcherTheme.syncWith(context);

    if (!widget.show) {
      return widget.child;
    }

    // Keep the button clear of system UI — in landscape the navigation bar
    // sits on the right edge and would otherwise cover the end of the button,
    // where the count, server icon, and error badge are.
    final safe = MediaQuery.of(context).padding;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: _top,
          right: _right + safe.right,
          child: GestureDetector(
            onPanUpdate: (d) => setState(() {
              final size = MediaQuery.of(context).size;
              _top = (_top + d.delta.dy)
                  .clamp(safe.top, size.height - safe.bottom - 48);
              _right = (_right - d.delta.dx)
                  .clamp(0.0, size.width - safe.horizontal - 72);
            }),
            child: _InspectorButton(
              count: HttpWatcherLogger.instance.logs.length,
              errorCount: HttpWatcherLogger.instance.errorCount,
              status: HttpWatcherLogger.instance.networkStatus,
              paused: !HttpWatcherLogger.instance.enabled,
              serverRunning: HttpWatcherLogger.instance.webServerRunning,
              icon: widget.icon,
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
  final int errorCount;
  final NetworkStatus status;
  final bool paused;
  final bool serverRunning;
  final IconData? icon;
  final VoidCallback onTap;

  const _InspectorButton({
    required this.count,
    required this.errorCount,
    required this.status,
    required this.paused,
    required this.serverRunning,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
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
                Icon(icon ?? Icons.network_check_rounded,
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
              // Shown while paused too — the server keeps serving either way.
              if (serverRunning) ...[
                const SizedBox(width: 5),
                const Icon(Icons.wifi_tethering,
                    color: Colors.greenAccent,
                    size: 14,
                    semanticLabel: 'Web Viewer running'),
              ],
            ],
          ),
        ),
      ),
    );

    if (errorCount == 0 || paused) return button;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              errorCount > 99 ? '99+' : '$errorCount',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
