import 'package:dio/dio.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/close_model.dart';

class ContabilidadRepository {
  final Dio _dio;

  ContabilidadRepository(this._dio);

  Future<List<CloseModel>> getCloses({String? date}) async {
    try {
      final Map<String, dynamic> query = date != null ? {'date': date} : {};
      final res = await _dio.get(ApiRoutes.contabilidadCloses, queryParameters: query);
      final list = res.data as List;
      return list.map((e) => CloseModel.fromJson(e)).toList();
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudieron cargar los cierres'),
        e.response?.statusCode,
      );
    }
  }

  Future<CloseModel> createClose({
    required CloseType type,
    required String status,
    required double cash,
    required double transfer,
    required double card,
    required double expenses,
    required double cashDelivered,
    DateTime? date,
  }) async {
    try {
      final data = {
        'type': type.key,
        'status': status,
        'cash': cash,
        'transfer': transfer,
        'card': card,
        'expenses': expenses,
        'cashDelivered': cashDelivered,
      };
      if (date != null) data['date'] = date.toIso8601String();
      final res = await _dio.post(ApiRoutes.contabilidadCloses, data: data);
      return CloseModel.fromJson(res.data);
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo crear el cierre'),
        e.response?.statusCode,
      );
    }
  }

  Future<CloseModel> updateClose(String id, {
    String? status,
    double? cash,
    double? transfer,
    double? card,
    double? expenses,
    double? cashDelivered,
  }) async {
    try {
      final data = {};
      if (status != null) data['status'] = status;
      if (cash != null) data['cash'] = cash;
      if (transfer != null) data['transfer'] = transfer;
      if (card != null) data['card'] = card;
      if (expenses != null) data['expenses'] = expenses;
      if (cashDelivered != null) data['cashDelivered'] = cashDelivered;
      final res = await _dio.patch('${ApiRoutes.contabilidadCloses}/$id', data: data);
      return CloseModel.fromJson(res.data);
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo actualizar el cierre'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteClose(String id) async {
    try {
      await _dio.delete('${ApiRoutes.contabilidadCloses}/$id');
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo eliminar el cierre'),
        e.response?.statusCode,
      );
    }
  }

  String _message(dynamic data, String fallback) {
    if (data is Map && data['message'] != null) return data['message'];
    return fallback;
  }
}