import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalJsonCache {
  static const String _prefix = 'ft_cache:';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  String _key(String key) => '$_prefix$key';
  String _atKey(String key) => '${_key(key)}:at';

  Future<Map<String, dynamic>?> readMap(String key, {Duration? maxAge}) async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_key(key));
      if (raw == null || raw.trim().isEmpty) return null;

      final atMs = prefs.getInt(_atKey(key));
      if (maxAge != null && atMs != null) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(atMs),
        );
        if (age > maxAge) return null;
      }

      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    final prefs = await _prefs();
    final encoded = jsonEncode(value);
    await prefs.setString(_key(key), encoded);
    await prefs.setInt(_atKey(key), DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> remove(String key) async {
    final prefs = await _prefs();
    await prefs.remove(_key(key));
    await prefs.remove(_atKey(key));
  }
}
