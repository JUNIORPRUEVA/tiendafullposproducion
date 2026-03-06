import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static const String _defaultApiBaseUrl = 'https://api.midominio.com';

  static String? _readEnv(String key) {
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

  static int get apiTimeoutMs =>
      int.tryParse(_readEnv('API_TIMEOUT_MS') ?? '15000') ?? 15000;
}
