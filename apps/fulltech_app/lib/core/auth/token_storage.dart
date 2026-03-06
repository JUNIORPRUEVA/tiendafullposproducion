import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const _accessTokenKey = 'accessToken';
  static const _refreshTokenKey = 'refreshToken';
  final _secureStorage = const FlutterSecureStorage();
  String? _memoryAccessToken;
  String? _memoryRefreshToken;

  bool get _useSecureStorage {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<void> saveTokens(String accessToken, [String? refreshToken]) async {
    _memoryAccessToken = accessToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _memoryRefreshToken = refreshToken;
    }

    await _saveInPrefs(accessToken, refreshToken); // Keep a durable fallback
    await _saveInSecure(accessToken, refreshToken);
  }

  Future<String?> getAccessToken() async {
    if (_memoryAccessToken != null && _memoryAccessToken!.isNotEmpty) {
      return _memoryAccessToken;
    }

    final secure = await _readSecure(_accessTokenKey);
    if (secure != null && secure.isNotEmpty) {
      _memoryAccessToken = secure;
      return secure;
    }

    try {
      final prefs = await _prefs();
      final value = prefs.getString(_accessTokenKey);
      if (value != null && value.isNotEmpty) {
        _memoryAccessToken = value;
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getRefreshToken() async {
    if (_memoryRefreshToken != null && _memoryRefreshToken!.isNotEmpty) {
      return _memoryRefreshToken;
    }

    final secure = await _readSecure(_refreshTokenKey);
    if (secure != null && secure.isNotEmpty) {
      _memoryRefreshToken = secure;
      return secure;
    }

    try {
      final prefs = await _prefs();
      final value = prefs.getString(_refreshTokenKey);
      if (value != null && value.isNotEmpty) {
        _memoryRefreshToken = value;
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearTokens() async {
    _memoryAccessToken = null;
    _memoryRefreshToken = null;

    try {
      final prefs = await _prefs();
      await prefs.remove(_accessTokenKey);
      await prefs.remove(_refreshTokenKey);
    } catch (_) {
      // Ignore prefs failures and still clear secure storage.
    }

    await _deleteSecure(_accessTokenKey);
    await _deleteSecure(_refreshTokenKey);
  }

  Future<void> _saveInPrefs(String accessToken, [String? refreshToken]) async {
    try {
      final prefs = await _prefs();
      await prefs.setString(_accessTokenKey, accessToken);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString(_refreshTokenKey, refreshToken);
      }
    } catch (_) {
      // Keep in-memory tokens as fallback for this session.
    }
  }

  Future<void> _saveInSecure(String accessToken, [String? refreshToken]) async {
    if (!_useSecureStorage) return;
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
    if (!_useSecureStorage) return null;
    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteSecure(String key) async {
    if (!_useSecureStorage) return;
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {
      // Ignore secure storage failures on platforms without support
    }
  }
}
