import 'package:flutter/foundation.dart' show kIsWeb;

class AppConstants {
  AppConstants._();

  static const String appName = 'AskLo';

  static const String _configuredBackendUrl = String.fromEnvironment(
    'ASKLO_BACKEND_URL',
  );

  /// Web defaults to same-origin, mobile defaults to production.
  /// Builds can override this with --dart-define=ASKLO_BACKEND_URL=...
  static String get backendUrl {
    final configured = _configuredBackendUrl.trim();
    if (configured.isNotEmpty) return _withoutTrailingSlash(configured);
    if (kIsWeb) return _withoutTrailingSlash(Uri.base.origin);
    return 'https://asklo.iyantama.tech';
  }

  static String _withoutTrailingSlash(String value) {
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static const double maxChatWidth = 720.0;
  static const double mobileBreakpoint = 600.0;
  static const double sidebarBreakpoint = 900.0;
  static const double sidebarWidth = 280.0;

  static const Duration animationFast = Duration(milliseconds: 200);
  static const Duration animationNormal = Duration(milliseconds: 350);
  static const Duration animationSlow = Duration(milliseconds: 500);

  static const int maxFileSize = 1 * 1024 * 1024; // 1MB

  static const List<String> suggestions = [
    '✨ Jelaskan komputer kuantum secara sederhana',
    '📝 Buatkan puisi singkat tentang bintang',
    '💡 Kasih 5 ide startup kreatif',
    '🧑‍💻 Jelaskan async/await di Dart',
  ];
}
