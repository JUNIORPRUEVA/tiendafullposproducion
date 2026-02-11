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
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) return first;
      }
    }
    return fallback;
  }

  Future<UserModel> login(String email, String password) async {
    try {
      final res = await _dio.post(
        ApiRoutes.login,
        data: {'email': email.trim(), 'password': password},
      );
      final access = res.data['accessToken'] as String?;
      if (access != null && access.isNotEmpty) {
        await _storage.saveTokens(access);
      }
      final me = await _dio.get(ApiRoutes.me);
      return UserModel.fromJson((me.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'Login fallido'),
        e.response?.statusCode,
      );
    }
  }

  Future<UserModel?> getMeOrNull() async {
    try {
      final token = await _storage.getAccessToken();
      if (token == null) return null;
      final res = await _dio.get(ApiRoutes.me);
      return UserModel.fromJson(res.data);
    } catch (_) {
      return null;
    }
  }
}
