import 'package:dio/dio.dart';
import '../api/api_routes.dart';
import 'token_storage.dart';

class AuthInterceptor extends Interceptor {
  final TokenStorage tokenStorage;
  final Dio dio;
  final Dio _refreshDio;

  Future<_RefreshResult?>? _refreshFuture;

  AuthInterceptor(this.tokenStorage, this.dio) : _refreshDio = Dio(dio.options);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await tokenStorage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
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
          return _RefreshResult(accessToken: newAccess, refreshToken: newRefresh);
        }
      }
    } catch (_) {
      // Ignore
    }
    return null;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_isAuthRefreshPath(err.requestOptions.path)) {
      final refreshToken = await tokenStorage.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          _refreshFuture ??= _refresh(refreshToken).whenComplete(() {
            _refreshFuture = null;
          });

          final refreshed = await _refreshFuture;
          if (refreshed != null && refreshed.accessToken.isNotEmpty) {
            await tokenStorage.saveTokens(
              refreshed.accessToken,
              (refreshed.refreshToken != null && refreshed.refreshToken!.isNotEmpty)
                  ? refreshed.refreshToken
                  : refreshToken,
            );
            final opts = err.requestOptions;
            opts.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';
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
