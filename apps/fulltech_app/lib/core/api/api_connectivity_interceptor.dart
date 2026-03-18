import 'package:dio/dio.dart';

import '../network/network_reachability.dart';
import 'api_error_mapper.dart';

class ApiConnectivityInterceptor extends Interceptor {
  final Dio dio;
  final NetworkReachability reachability;

  ApiConnectivityInterceptor({required this.dio, required this.reachability});

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipConnectivityCheck'] == true) {
      handler.next(options);
      return;
    }

    final configError = ApiErrorMapper.validateBaseUrl(
      rawBaseUrl: dio.options.baseUrl,
      requestUri: options.uri,
      method: options.method.toUpperCase(),
    );
    if (configError != null) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: configError,
          message: configError.message,
          type: DioExceptionType.unknown,
        ),
      );
      return;
    }

    final probe = await reachability.probe(options.uri);
    if (!probe.isReachable) {
      final apiError = ApiErrorMapper.fromNetworkProbe(
        probe: probe,
        fallbackMessage: 'No fue posible conectar con el servidor',
        uri: options.uri,
        method: options.method.toUpperCase(),
      );
      handler.reject(
        DioException(
          requestOptions: options,
          error: apiError,
          message: probe.detail,
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }

    handler.next(options);
  }
}