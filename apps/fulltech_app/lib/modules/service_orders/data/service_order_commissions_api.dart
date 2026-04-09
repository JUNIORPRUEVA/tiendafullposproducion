import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error_mapper.dart';
import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../commissions_models.dart';

final serviceOrderCommissionsApiProvider = Provider<ServiceOrderCommissionsApi>(
  (ref) {
    return ServiceOrderCommissionsApi(ref.watch(dioProvider));
  },
);

class ServiceOrderCommissionsApi {
  ServiceOrderCommissionsApi(this._dio);

  final Dio _dio;
  static final _backgroundOptions = Options(extra: {'skipLoader': true});

  Never _rethrow(DioException error, String fallback) {
    throw ApiErrorMapper.fromDio(error, fallbackMessage: fallback, dio: _dio);
  }

  Future<ServiceOrderCommissionsResponse> list({
    required String period,
    required int page,
    required int pageSize,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.serviceOrderCommissions,
        queryParameters: {'period': period, 'page': page, 'pageSize': pageSize},
        options: _backgroundOptions,
      );
      final raw = (res.data as Map?)?.cast<String, dynamic>();
      if (raw == null) {
        throw ApiException.detailed(
          message:
              'No se pudieron cargar las comisiones. El servidor devolvió un formato inválido.',
          type: ApiErrorType.parse,
          displayCode: 'PARSE_ERROR',
          retryable: false,
        );
      }
      return ServiceOrderCommissionsResponse.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron cargar las comisiones');
    }
  }
}
