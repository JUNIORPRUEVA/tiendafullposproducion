import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';
import '../../clientes/cliente_model.dart';
import '../sales_models.dart';

final ventasRepositoryProvider = Provider<VentasRepository>((ref) {
  return VentasRepository(ref.watch(dioProvider));
});

class VentasRepository {
  final Dio _dio;

  VentasRepository(this._dio);

  String _extractMessage(dynamic data, String fallback) {
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) return first;
      }
    }
    return fallback;
  }

  Future<List<SaleModel>> listSales({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.sales,
        queryParameters: {'from': _dateOnly(from), 'to': _dateOnly(to)},
      );

      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((e) => SaleModel.fromJson(e.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar las ventas'),
        e.response?.statusCode,
      );
    }
  }

  Future<SalesSummaryModel> summary({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.salesSummary,
        queryParameters: {'from': _dateOnly(from), 'to': _dateOnly(to)},
      );
      return SalesSummaryModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el resumen'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteSale(String id) async {
    try {
      await _dio.delete(ApiRoutes.saleDetail(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar la venta'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> createSale({
    String? customerId,
    String? note,
    required List<SaleDraftItem> items,
  }) async {
    if (items.isEmpty) {
      throw ApiException('Agrega al menos un item');
    }

    try {
      await _dio.post(
        ApiRoutes.sales,
        data: {
          if (customerId != null && customerId.isNotEmpty)
            'customerId': customerId,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          'items': items.map((item) => item.toPayload()).toList(),
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar la venta'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<ProductModel>> fetchProducts() async {
    try {
      final res = await _dio.get(ApiRoutes.products);
      final data = res.data;
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((row) => ProductModel.fromJson(row.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar los productos',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<List<ClienteModel>> searchClients(String search) async {
    try {
      final res = await _dio.get(
        ApiRoutes.clients,
        queryParameters: {
          if (search.trim().isNotEmpty) 'search': search.trim(),
          'page': 1,
          'pageSize': 100,
        },
      );

      final raw = res.data;
      final List<dynamic> rows;
      if (raw is List) {
        rows = raw;
      } else if (raw is Map && raw['items'] is List) {
        rows = raw['items'] as List<dynamic>;
      } else {
        rows = const [];
      }

      return rows
          .whereType<Map>()
          .map((row) => ClienteModel.fromJson(row.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar clientes'),
        e.response?.statusCode,
      );
    }
  }

  Future<ClienteModel> createQuickClient({
    required String nombre,
    required String telefono,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.clients,
        data: {'nombre': nombre.trim(), 'telefono': telefono.trim()},
      );
      return ClienteModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear el cliente'),
        e.response?.statusCode,
      );
    }
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
