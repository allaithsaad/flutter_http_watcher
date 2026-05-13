import 'package:flutter/material.dart';
import '../core/network_logger.dart';

/// Provides colors for both dark and light inspector themes.
/// Toggle via [HttpWatcherLogger.instance.isDark].
class WatcherTheme {
  WatcherTheme._();

  static bool get isDark => HttpWatcherLogger.instance.isDark;

  static Color get background  => isDark ? const Color(0xFF0D0D1A) : const Color(0xFFF0F2F5);
  static Color get surface     => isDark ? const Color(0xFF1A1A2E) : Colors.white;
  static Color get divider     => isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E0);
  static Color get textPrimary => isDark ? Colors.white            : const Color(0xFF1A1A2E);
  static Color get textSecond  => isDark ? Colors.white70          : Colors.black54;
  static Color get textHint    => isDark ? Colors.white38          : Colors.black38;
  static Color get border      => isDark ? Colors.white12          : Colors.black12;
  static Color get codeText    => isDark ? const Color(0xFF90EE90) : const Color(0xFF2E7D32);
  static Color get iconColor   => isDark ? Colors.white70          : Colors.black54;
}
