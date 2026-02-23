import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const _accessTokenKey = 'accessToken';
  static const _refreshTokenKey = 'refreshToken';
  final _secureStorage = const FlutterSecureStorage();

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<void> saveTokens(String accessToken, [String? refreshToken]) async {
    await _saveInPrefs(accessToken, refreshToken); // Keep a durable fallback
    await _saveInSecure(accessToken, refreshToken);
  }

  Future<String?> getAccessToken() async {
    final secure = await _readSecure(_accessTokenKey);
    if (secure != null && secure.isNotEmpty) return secure;

    final prefs = await _prefs();
    return prefs.getString(_accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    final secure = await _readSecure(_refreshTokenKey);
    if (secure != null && secure.isNotEmpty) return secure;

    final prefs = await _prefs();
    return prefs.getString(_refreshTokenKey);
  }

  Future<void> clearTokens() async {
    final prefs = await _prefs();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await _deleteSecure(_accessTokenKey);
    await _deleteSecure(_refreshTokenKey);
  }

  Future<void> _saveInPrefs(String accessToken, [String? refreshToken]) async {
    final prefs = await _prefs();
    await prefs.setString(_accessTokenKey, accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString(_refreshTokenKey, refreshToken);
    }
  }

  Future<void> _saveInSecure(String accessToken, [String? refreshToken]) async {
    if (kIsWeb) return; // Secure storage is not available on web
    try {
      await _secureStorage.write(key: _accessTokenKey, value: accessToken);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
      }
    } catch (_) {
      // Silently fall back to prefs when secure storage is unavailable
    }
  }

  Future<String?> _readSecure(String key) async {
    if (kIsWeb) return null;
    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteSecure(String key) async {
    if (kIsWeb) return;
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {
      // Ignore secure storage failures on platforms without support
    }
  }
}
