import 'package:dio/dio.dart';

import 'app_loading_controller.dart';

class LoadingInterceptor extends Interceptor {
  final AppLoadingController controller;

  LoadingInterceptor(this.controller);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    controller.requestStarted();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    controller.requestEnded();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    controller.requestEnded();
    handler.next(err);
  }
}
