import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const _accessTokenKey = 'accessToken';
  static const _refreshTokenKey = 'refreshToken';
  final _secureStorage = const FlutterSecureStorage();

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<void> saveTokens(String accessToken, [String? refreshToken]) async {
    if (kIsWeb) {
      final prefs = await _prefs();
      await prefs.setString(_accessTokenKey, accessToken);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString(_refreshTokenKey, refreshToken);
      }
      return;
    }

    await _secureStorage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  Future<String?> getAccessToken() async {
    if (kIsWeb) {
      final prefs = await _prefs();
      return prefs.getString(_accessTokenKey);
    }
    return await _secureStorage.read(key: _accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    if (kIsWeb) {
      final prefs = await _prefs();
      return prefs.getString(_refreshTokenKey);
    }
    return await _secureStorage.read(key: _refreshTokenKey);
  }

  Future<void> clearTokens() async {
    if (kIsWeb) {
      final prefs = await _prefs();
      await prefs.remove(_accessTokenKey);
      await prefs.remove(_refreshTokenKey);
      return;
    }
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
  }
}
