import 'dart:async';

import 'package:dio/dio.dart';
import '../api/api_routes.dart';
import 'token_storage.dart';

class AuthInterceptor extends Interceptor {
  final TokenStorage tokenStorage;
  final Dio dio;
  final Dio _refreshDio;

  Completer<String?>? _refreshCompleter;

  AuthInterceptor(this.tokenStorage, this.dio) : _refreshDio = Dio(dio.options);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await tokenStorage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final refreshToken = await tokenStorage.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          _refreshCompleter ??= Completer<String?>();

          if (!_refreshCompleter!.isCompleted) {
            try {
              final response = await _refreshDio.post(
                ApiRoutes.refresh,
                data: {'refreshToken': refreshToken},
              );
              final data = response.data;
              final newToken = (data is Map ? data['accessToken'] : null) as String?;
              _refreshCompleter!.complete(newToken);
            } catch (_) {
              _refreshCompleter!.complete(null);
            }
          }

          final newToken = await _refreshCompleter!.future;
          _refreshCompleter = null;

          if (newToken != null && newToken.isNotEmpty) {
            await tokenStorage.saveTokens(newToken, refreshToken);
            final opts = err.requestOptions;
            opts.headers['Authorization'] = 'Bearer $newToken';
            final retryResponse = await dio.fetch(opts);
            return handler.resolve(retryResponse);
          }
        } catch (_) {}
      }
    }
    handler.next(err);
  }
}
