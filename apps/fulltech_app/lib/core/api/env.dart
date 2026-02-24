import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static const String _defaultApiBaseUrl =
      'https://fulltech-tienda-fulltechapppwa.gcdndd.easypanel.host';

  static String get apiBaseUrl {
    final raw = (dotenv.env['API_BASE_URL'] ?? '').trim();
    final value = raw.isEmpty ? _defaultApiBaseUrl : raw;
    // Evita doble slash al concatenar rutas.
    if (value.endsWith('/')) return value.substring(0, value.length - 1);
    return value;
  }
  static int get apiTimeoutMs => int.tryParse(dotenv.env['API_TIMEOUT_MS'] ?? '15000') ?? 15000;
}
