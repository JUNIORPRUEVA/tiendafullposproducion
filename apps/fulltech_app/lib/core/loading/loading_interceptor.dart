import 'package:dio/dio.dart';

import 'app_loading_controller.dart';

const String _loadingRequestIdKey = '__app_loading_request_id';

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
      options.extra[_loadingRequestIdKey] = controller.requestStarted();
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    controller.requestEnded(_requestIdFor(response.requestOptions));
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    controller.requestEnded(_requestIdFor(err.requestOptions));
    handler.next(err);
  }

  String? _requestIdFor(RequestOptions options) {
    final requestId = options.extra.remove(_loadingRequestIdKey);
    return requestId is String && requestId.isNotEmpty ? requestId : null;
  }
}
