import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? '';
  static int get apiTimeoutMs => int.tryParse(dotenv.env['API_TIMEOUT_MS'] ?? '15000') ?? 15000;
}
