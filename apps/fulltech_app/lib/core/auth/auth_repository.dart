import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../errors/api_exception.dart';
import '../models/user_model.dart';
import 'auth_interceptor.dart';
import 'token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final dioProvider = Provider<Dio>((ref) {
  final api = ApiClient();
  final storage = ref.watch(tokenStorageProvider);
  api.dio.interceptors.add(AuthInterceptor(storage, api.dio));
  return api.dio;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    dio: ref.watch(dioProvider),
    storage: ref.watch(tokenStorageProvider),
  );
});

class AuthRepository {
  final Dio _dio;
  final TokenStorage _storage;

  AuthRepository({required Dio dio, required TokenStorage storage})
    : _dio = dio,
      _storage = storage;

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final normalized = message
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        if (normalized.isNotEmpty) return normalized.join(' | ');
      }
      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error;
    }
    return fallback;
  }

  String _formatDioError(DioException e, String fallback) {
    final status = e.response?.statusCode;
    final endpoint = e.requestOptions.path;
    final rawMessage = _extractMessage(e.response?.data, fallback);

    if (status == null) {
      return '[NETWORK] $rawMessage\nEndpoint: $endpoint\nDetalle: ${e.message ?? 'Sin respuesta del servidor'}';
    }

    return '[HTTP $status] $rawMessage\nEndpoint: $endpoint';
  }

  Future<UserModel> login(String email, String password) async {
    try {
      final normalizedEmail = email.trim();
      Response<dynamic> res;

      try {
        res = await _dio.post(
          ApiRoutes.login,
          data: {'email': normalizedEmail, 'password': password},
        );
      } on DioException catch (firstError) {
        final status = firstError.response?.statusCode;
        final message = _extractMessage(firstError.response?.data, '');
        final shouldRetryWithIdentifier =
            status == 400 ||
            status == 422 ||
            message.toLowerCase().contains('identifier') ||
            message.toLowerCase().contains('internal server error');

        if (!shouldRetryWithIdentifier) rethrow;

        res = await _dio.post(
          ApiRoutes.login,
          data: {'identifier': normalizedEmail, 'password': password},
        );
      }

      final access = res.data['accessToken'] as String?;
      final refresh = res.data['refreshToken'] as String?;
      if (access != null && access.isNotEmpty) {
        await _storage.saveTokens(access, refresh);
      }
      final me = await _dio.get(ApiRoutes.me);
      return UserModel.fromJson((me.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _formatDioError(e, 'Login fallido'),
        e.response?.statusCode,
      );
    }
  }

  Future<UserModel?> getMeOrNull() async {
    try {
      final token = await _storage.getAccessToken();
      if (token == null) return null;
      try {
        final res = await _dio.get(ApiRoutes.me);
        return UserModel.fromJson(res.data);
      } on DioException catch (e) {
        // Si expira, intenta refresh y reintenta
        if (e.response?.statusCode == 401) {
          final refreshed = await _refreshAndSave();
          if (refreshed) {
            final res = await _dio.get(ApiRoutes.me);
            return UserModel.fromJson(res.data);
          }
        }
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<bool> _refreshAndSave() async {
    final refresh = await _storage.getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final res = await _dio.post(ApiRoutes.refresh, data: {'refreshToken': refresh});
      final access = res.data['accessToken'] as String?;
      if (access != null && access.isNotEmpty) {
        await _storage.saveTokens(access, refresh);
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }
}
