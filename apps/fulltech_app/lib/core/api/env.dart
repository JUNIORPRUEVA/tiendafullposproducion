import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'runtime_env.dart';

class Env {
  static const String _defaultApiBaseUrl = 'https://api.midominio.com';
  static const int _defaultApiTimeoutMs = 15000;
  static const int _minApiTimeoutMs = 1000;

  static String? _readEnv(String key) {
    // 1) Compile-time values (flutter build --dart-define=...)
    if (key == 'API_BASE_URL') {
      const v = String.fromEnvironment('API_BASE_URL', defaultValue: '');
      if (v.trim().isNotEmpty) return v;
    }
    if (key == 'API_TIMEOUT_MS') {
      const v = String.fromEnvironment('API_TIMEOUT_MS', defaultValue: '');
      if (v.trim().isNotEmpty) return v;
    }

    // 2) Runtime values for Web (injected via env.js)
    if (kIsWeb) {
      final v = RuntimeEnv.get(key);
      if (v != null && v.trim().isNotEmpty) return v;
    }

    // 3) Bundled .env assets (flutter_dotenv)
    try {
      return dotenv.env[key];
    } catch (_) {
      return null;
    }
  }

  static String get apiBaseUrl {
    final raw = (_readEnv('API_BASE_URL') ?? '').trim();

    if (raw.isEmpty) {
      debugPrint(
        'API_BASE_URL is missing. Define it in .env / EasyPanel env vars. Using fallback: $_defaultApiBaseUrl',
      );
      return _defaultApiBaseUrl;
    }

    if (raw.startsWith('/')) {
      if (kIsWeb) {
        final value = '${Uri.base.origin}$raw';
        return value.endsWith('/')
            ? value.substring(0, value.length - 1)
            : value;
      }

      debugPrint(
        'Relative API_BASE_URL is only valid on web. Value="$raw". Using fallback.',
      );
      return _defaultApiBaseUrl;
    }

    final value = raw;

    final parsed = Uri.tryParse(value);

    if (parsed == null || parsed.scheme.isEmpty) {
      debugPrint('Invalid API_BASE_URL (no scheme): "$value". Using default.');
      return _defaultApiBaseUrl;
    }

    final host = parsed.host.trim().toLowerCase();
    final isHttp = parsed.scheme == 'http' || parsed.scheme == 'https';
    if (!isHttp || host.isEmpty) {
      debugPrint('Invalid API_BASE_URL: "$value". Using default.');
      return _defaultApiBaseUrl;
    }

    // In release builds, warn if config looks dev-only, but don't block startup.
    if (kReleaseMode) {
      if (raw.isEmpty) {
        debugPrint(
          'API_BASE_URL missing in release build; using default: $_defaultApiBaseUrl',
        );
      } else if (host == 'localhost' || host == '127.0.0.1') {
        debugPrint('API_BASE_URL points to localhost in release: $value');
      }
    }

    // Evita doble slash al concatenar rutas.
    final normalized = value.endsWith('/')
        ? value.substring(0, value.length - 1)
        : value;
    return normalized;
  }

  static int get apiTimeoutMs {
    final raw = (_readEnv('API_TIMEOUT_MS') ?? '').trim();
    final parsed = int.tryParse(raw);
    final value = parsed ?? _defaultApiTimeoutMs;

    // Dio treats Duration.zero as “no timeout”. A misconfigured 0 would look
    // like a freeze for users.
    if (value <= 0) return _defaultApiTimeoutMs;
    if (value < _minApiTimeoutMs) return _minApiTimeoutMs;
    return value;
  }
}
