import 'dart:async';

import 'package:dio/dio.dart';

import '../debug/trace_log.dart';
import '../api/api_routes.dart';
import 'token_storage.dart';

class AuthInterceptor extends Interceptor {
  final TokenStorage tokenStorage;
  final Dio dio;
  final Dio _refreshDio;

  Future<_RefreshResult?>? _refreshFuture;

  AuthInterceptor(this.tokenStorage, this.dio) : _refreshDio = Dio(dio.options);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final seq = TraceLog.nextSeq();
    final sw = Stopwatch()..start();
    TraceLog.log(
      'AuthInterceptor',
      'onRequest start -> ${options.method} ${options.uri}',
      seq: seq,
    );

    try {
      final token = await tokenStorage.getAccessToken().timeout(
        const Duration(seconds: 2),
      );
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      TraceLog.log(
        'AuthInterceptor',
        'onRequest token=${token == null ? 'null' : (token.isEmpty ? 'empty' : 'present')} (${sw.elapsedMilliseconds}ms)',
        seq: seq,
      );
    } on TimeoutException catch (e, st) {
      TraceLog.log(
        'AuthInterceptor',
        'onRequest getAccessToken() TIMEOUT -> continuing without token',
        seq: seq,
        error: e,
        stackTrace: st,
      );
    } catch (e, st) {
      TraceLog.log(
        'AuthInterceptor',
        'onRequest getAccessToken() ERROR -> continuing without token',
        seq: seq,
        error: e,
        stackTrace: st,
      );
    }

    handler.next(options);
  }

  bool _isAuthRefreshPath(String path) {
    // `path` puede venir como '/auth/refresh' o con baseUrl ya aplicada en algunos casos.
    return path == ApiRoutes.refresh || path.endsWith(ApiRoutes.refresh);
  }

  Future<_RefreshResult?> _refresh(String refreshToken) async {
    try {
      final response = await _refreshDio.post(
        ApiRoutes.refresh,
        data: {'refreshToken': refreshToken},
      );
      final data = response.data;
      if (data is Map) {
        final newAccess = data['accessToken'] as String?;
        final newRefresh = data['refreshToken'] as String?;
        if (newAccess != null && newAccess.isNotEmpty) {
          return _RefreshResult(
            accessToken: newAccess,
            refreshToken: newRefresh,
          );
        }
      }
    } catch (_) {
      // Ignore
    }
    return null;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 &&
        !_isAuthRefreshPath(err.requestOptions.path)) {
      final seq = TraceLog.nextSeq();
      TraceLog.log(
        'AuthInterceptor',
        'onError 401 -> attempting refresh',
        seq: seq,
      );

      String? refreshToken;
      try {
        refreshToken = await tokenStorage.getRefreshToken().timeout(
          const Duration(seconds: 2),
        );
      } on TimeoutException catch (e, st) {
        TraceLog.log(
          'AuthInterceptor',
          'getRefreshToken() TIMEOUT',
          seq: seq,
          error: e,
          stackTrace: st,
        );
      } catch (e, st) {
        TraceLog.log(
          'AuthInterceptor',
          'getRefreshToken() ERROR',
          seq: seq,
          error: e,
          stackTrace: st,
        );
      }

      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          _refreshFuture ??= _refresh(refreshToken).whenComplete(() {
            _refreshFuture = null;
          });

          final refreshed = await _refreshFuture;
          if (refreshed != null && refreshed.accessToken.isNotEmpty) {
            await tokenStorage.saveTokens(
              refreshed.accessToken,
              (refreshed.refreshToken != null &&
                      refreshed.refreshToken!.isNotEmpty)
                  ? refreshed.refreshToken
                  : refreshToken,
            );
            final opts = err.requestOptions;
            opts.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';

            // Dio no permite reutilizar FormData ya enviada (queda "finalized").
            // Clonamos para que el reintento funcione en uploads multipart.
            final data = opts.data;
            if (data is FormData) {
              opts.data = data.clone();
            }

            final retryResponse = await dio.fetch(opts);
            return handler.resolve(retryResponse);
          }
        } catch (_) {}
      }
    }
    handler.next(err);
  }
}

class _RefreshResult {
  final String accessToken;
  final String? refreshToken;

  _RefreshResult({required this.accessToken, this.refreshToken});
}
