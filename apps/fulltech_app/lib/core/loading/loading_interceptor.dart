import 'package:dio/dio.dart';

import 'app_loading_controller.dart';

class LoadingInterceptor extends Interceptor {
  final AppLoadingController controller;

  LoadingInterceptor(this.controller);

  bool _shouldTrack(RequestOptions options) {
    final extra = options.extra;
    final silent = extra['silent'];
    if (silent is bool && silent) return false;

    final skip = extra['skipLoader'];
    if (skip is bool && skip) return false;

    final show = extra['showLoader'];
    if (show is bool && show == false) return false;

    return true;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_shouldTrack(options)) {
      controller.requestStarted();
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (_shouldTrack(response.requestOptions)) {
      controller.requestEnded();
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_shouldTrack(err.requestOptions)) {
      controller.requestEnded();
    }
    handler.next(err);
  }
}
