import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static const String _defaultApiBaseUrl = 'http://localhost:4000';

  static String get apiBaseUrl {
    final raw = (dotenv.env['API_BASE_URL'] ?? '').trim();
    final value = raw.isEmpty ? _defaultApiBaseUrl : raw;

    final parsed = Uri.tryParse(value);
    final host = (parsed?.host ?? '').trim().toLowerCase();

    // In release builds, avoid silently using a dev-only API.
    if (kReleaseMode) {
      if (raw.isEmpty) {
        throw StateError(
          'API_BASE_URL is required for release builds. Create apps/fulltech_app/.env',
        );
      }

      if (host == 'localhost' || host == '127.0.0.1') {
        throw StateError(
          'API_BASE_URL cannot point to localhost in release builds: $value',
        );
      }
    }

    // Evita doble slash al concatenar rutas.
    if (value.endsWith('/')) return value.substring(0, value.length - 1);
    return value;
  }

  static int get apiTimeoutMs =>
      int.tryParse(dotenv.env['API_TIMEOUT_MS'] ?? '15000') ?? 15000;
}
