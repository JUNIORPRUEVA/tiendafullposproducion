import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_connectivity_interceptor.dart';
import '../api/api_diagnostics_interceptor.dart';
import '../api/api_error_mapper.dart';
import '../api/api_retry_interceptor.dart';
import '../api/api_routes.dart';
import '../errors/api_exception.dart';
import '../models/user_model.dart';
import '../network/network_reachability.dart';
import '../utils/is_flutter_test.dart';
import 'auth_interceptor.dart';
import 'token_storage.dart';
import '../loading/app_loading_controller.dart';
import '../loading/loading_interceptor.dart';

enum SessionVerificationStatus { authenticated, invalid, deferred }

class HydratedSession {
  final bool hasToken;
  final UserModel? user;

  const HydratedSession({required this.hasToken, this.user});

  const HydratedSession.empty() : this(hasToken: false);
}

class SessionVerificationResult {
  final SessionVerificationStatus status;
  final UserModel? user;

  const SessionVerificationResult({required this.status, this.user});

  const SessionVerificationResult.invalid()
    : this(status: SessionVerificationStatus.invalid);

  const SessionVerificationResult.deferred({UserModel? user})
    : this(status: SessionVerificationStatus.deferred, user: user);

  const SessionVerificationResult.authenticated(UserModel user)
    : this(status: SessionVerificationStatus.authenticated, user: user);
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final networkReachabilityProvider = Provider<NetworkReachability>((ref) {
  return NetworkReachability();
});

final dioProvider = Provider<Dio>((ref) {
  final api = ApiClient();
  final storage = ref.watch(tokenStorageProvider);
  final reachability = ref.watch(networkReachabilityProvider);
  api.dio.interceptors.add(AuthInterceptor(storage, api.dio));
  api.dio.interceptors.add(
    ApiConnectivityInterceptor(dio: api.dio, reachability: reachability),
  );
  api.dio.interceptors.add(
    LoadingInterceptor(ref.read(appLoadingProvider.notifier)),
  );
  api.dio.interceptors.add(ApiDiagnosticsInterceptor());
  api.dio.interceptors.add(ApiRetryInterceptor(dio: api.dio));
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
  static const Duration _loginTimeout = Duration(seconds: 25);
  static const Duration _bootstrapTimeout = Duration(seconds: 12);
  static const Duration _storageTimeout = Duration(seconds: 3);

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

  ApiException _mapDioError(DioException error, String fallback) {
    return ApiErrorMapper.fromDio(error, fallbackMessage: fallback, dio: _dio);
  }

  UserModel? _userFromLoginResponse(dynamic data) {
    if (data is! Map) return null;
    final user = data['user'];
    if (user is! Map) return null;

    final normalized = user.cast<String, dynamic>();
    final id = (normalized['id'] ?? '').toString().trim();
    final email = (normalized['email'] ?? '').toString().trim();
    if (id.isEmpty || email.isEmpty) return null;

    return UserModel.fromJson(normalized);
  }

  Future<void> _safeClearTokens() async {
    try {
      await _storage.clearTokens().timeout(_storageTimeout);
    } catch (_) {}
  }

  Future<HydratedSession> hydrateSession() async {
    try {
      final token = await _storage.getAccessToken().timeout(_storageTimeout);
      if (token == null || token.isEmpty) {
        return const HydratedSession.empty();
      }

      final user = await _storage.getUserSnapshot().timeout(_storageTimeout);
      return HydratedSession(hasToken: true, user: user);
    } catch (_) {
      return const HydratedSession.empty();
    }
  }

  Future<UserModel> login(String email, String password) async {
    await _safeClearTokens();
    try {
      final normalizedEmail = email.trim();
      Response<dynamic> res;

      try {
        res = await _dio
            .post(
              ApiRoutes.login,
              data: {'email': normalizedEmail, 'password': password},
            )
            .timeout(_loginTimeout);
      } on DioException catch (firstError) {
        final status = firstError.response?.statusCode;
        final message = _extractMessage(firstError.response?.data, '');
        final shouldRetryWithIdentifier =
            status == 400 ||
            status == 422 ||
            message.toLowerCase().contains('identifier') ||
            message.toLowerCase().contains('internal server error');

        if (!shouldRetryWithIdentifier) rethrow;

        res = await _dio
            .post(
              ApiRoutes.login,
              data: {'identifier': normalizedEmail, 'password': password},
            )
            .timeout(_loginTimeout);
      }

      final access = res.data['accessToken'] as String?;
      final refresh = res.data['refreshToken'] as String?;
      if (access != null && access.isNotEmpty) {
        await _storage.saveTokens(access, refresh);
      }
      try {
        final me = await _dio.get(ApiRoutes.usersMe).timeout(_loginTimeout);
        final user = UserModel.fromJson(
          (me.data as Map).cast<String, dynamic>(),
        );
        await _storage.saveUserSnapshot(user);
        return user;
      } on DioException {
        final fallbackUser = _userFromLoginResponse(res.data);
        if (fallbackUser != null) {
          await _storage.saveUserSnapshot(fallbackUser);
          return fallbackUser;
        }
        rethrow;
      } on TimeoutException {
        final fallbackUser = _userFromLoginResponse(res.data);
        if (fallbackUser != null) {
          await _storage.saveUserSnapshot(fallbackUser);
          return fallbackUser;
        }
        rethrow;
      }
    } on TimeoutException {
      await _safeClearTokens();
      throw const ApiException.detailed(
        message:
            'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
        type: ApiErrorType.timeout,
        displayCode: 'NETWORK_TIMEOUT',
        retryable: true,
      );
    } on DioException catch (e) {
      await _safeClearTokens();
      throw _mapDioError(e, 'No se pudo iniciar sesión');
    } catch (_) {
      await _safeClearTokens();
      rethrow;
    }
  }

  Future<UserModel?> getMeOrNull() async {
    // Widget tests (smoke test) should not block on secure storage/network.
    // Those calls can hang in tests and leave pending timeout timers.
    // Note: `bool.fromEnvironment('FLUTTER_TEST')` would require --dart-define;
    // `flutter test` doesn't set that by default.
    if (isFlutterTest) {
      return null;
    }

    try {
      final token = await _storage.getAccessToken().timeout(_storageTimeout);
      if (token == null) return null;
      try {
        final res = await _dio
            .get(ApiRoutes.usersMe)
            .timeout(_bootstrapTimeout);
        final user = UserModel.fromJson(
          (res.data as Map).cast<String, dynamic>(),
        );
        await _storage.saveUserSnapshot(user);
        return user;
      } on DioException catch (e) {
        // Si expira, intenta refresh y reintenta
        if (e.response?.statusCode == 401) {
          final refreshed = await _refreshAndSave();
          if (refreshed) {
            final res = await _dio
                .get(ApiRoutes.usersMe)
                .timeout(_bootstrapTimeout);
            final user = UserModel.fromJson(
              (res.data as Map).cast<String, dynamic>(),
            );
            await _storage.saveUserSnapshot(user);
            return user;
          }

          await _safeClearTokens();
          return null;
        }

        return _storage.getUserSnapshot();
      } on TimeoutException {
        return _storage.getUserSnapshot();
      }
    } catch (_) {
      return _storage.getUserSnapshot();
    }
  }

  Future<SessionVerificationResult> verifySession() async {
    if (isFlutterTest) {
      return const SessionVerificationResult.invalid();
    }

    final hydrated = await hydrateSession();
    if (!hydrated.hasToken) {
      return const SessionVerificationResult.invalid();
    }

    try {
      final user = await getMeOrNull();
      if (user != null) {
        return SessionVerificationResult.authenticated(user);
      }

      final token = await _storage.getAccessToken().timeout(_storageTimeout);
      if (token == null || token.isEmpty) {
        return const SessionVerificationResult.invalid();
      }

      if (hydrated.user != null) {
        return SessionVerificationResult.deferred(user: hydrated.user);
      }

      return const SessionVerificationResult.deferred();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _safeClearTokens();
        return const SessionVerificationResult.invalid();
      }

      return SessionVerificationResult.deferred(user: hydrated.user);
    } on TimeoutException {
      return SessionVerificationResult.deferred(user: hydrated.user);
    } catch (_) {
      return SessionVerificationResult.deferred(user: hydrated.user);
    }
  }

  Future<bool> _refreshAndSave() async {
    final refresh = await _storage.getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final res = await _dio.post(
        ApiRoutes.refresh,
        data: {'refreshToken': refresh},
      );
      final access = res.data['accessToken'] as String?;
      final newRefresh = res.data['refreshToken'] as String?;
      if (access != null && access.isNotEmpty) {
        await _storage.saveTokens(
          access,
          (newRefresh != null && newRefresh.isNotEmpty) ? newRefresh : refresh,
        );
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }
}
