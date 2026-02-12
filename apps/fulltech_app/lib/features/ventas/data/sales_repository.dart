import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/client_model.dart';
import '../../../core/models/sale_model.dart';

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(ref.watch(dioProvider));
});

class SalesRepository {
  final Dio _dio;
  SalesRepository(this._dio);

  String _message(dynamic data, String fallback) {
    if (data is Map) {
      final msg = data['message'];
      if (msg is String && msg.trim().isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) {
        final first = msg.first;
        if (first is String && first.trim().isNotEmpty) return first;
      }
    }
    return fallback;
  }

  Map<String, dynamic> _compactQuery(Map<String, dynamic> values) {
    return values..removeWhere((key, value) => value == null);
  }

  Future<List<ClientModel>> fetchClients({
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.clients,
        queryParameters: _compactQuery({
          'search': search,
          'page': page,
          'pageSize': pageSize,
        }),
      );
      final data = res.data;
      if (data is Map && data['items'] is List) {
        return (data['items'] as List)
            .map(
              (e) => ClientModel.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();
      }
      if (data is List) {
        return data
            .map(
              (e) => ClientModel.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();
      }
      return [];
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudieron cargar los clientes'),
        e.response?.statusCode,
      );
    }
  }

  Future<ClientModel> createClient({
    required String nombre,
    required String telefono,
    String? email,
    String? direccion,
    String? notas,
  }) async {
    try {
      final data = {
        'nombre': nombre,
        'telefono': telefono,
      };
      if (email != null) data['email'] = email;
      if (direccion != null) data['direccion'] = direccion;
      if (notas != null) data['notas'] = notas;
      final res = await _dio.post(
        ApiRoutes.clients,
        data: data,
      );
      return ClientModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo crear el cliente'),
        e.response?.statusCode,
      );
    }
  }

  Future<ClientModel> updateClient(
    String id, {
    required String nombre,
    String? telefono,
    String? email,
    String? direccion,
    String? notas,
  }) async {
    try {
      final data = {
        'nombre': nombre,
      };
      if (telefono != null) data['telefono'] = telefono;
      if (email != null) data['email'] = email;
      if (direccion != null) data['direccion'] = direccion;
      if (notas != null) data['notas'] = notas;
      final res = await _dio.patch(
        '${ApiRoutes.clients}/$id',
        data: data,
      );
      return ClientModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo actualizar el cliente'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteClient(String id) async {
    try {
      await _dio.delete('${ApiRoutes.clients}/$id');
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo eliminar el cliente'),
        e.response?.statusCode,
      );
    }
  }

  Future<SaleModel> createSale({
    String? clientId,
    String? note,
    String? status,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.sales,
        data: {
          'clientId': clientId,
          'note': note,
          'status': status,
          'items': items,
        },
      );
      return SaleModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo crear la venta'),
        e.response?.statusCode,
      );
    }
  }

  Future<SaleModel> updateSale(
    String saleId, {
    String? clientId,
    String? note,
    String? status,
  }) async {
    try {
      final res = await _dio.put(
        ApiRoutes.saleDetail(saleId),
        data: {'clientId': clientId, 'note': note, 'status': status},
      );
      return SaleModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo actualizar la venta'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteSale(String saleId) async {
    try {
      await _dio.delete(ApiRoutes.saleDetail(saleId));
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo eliminar la venta'),
        e.response?.statusCode,
      );
    }
  }

  Future<SaleModel> addItem(
    String saleId, {
    required String productId,
    int qty = 1,
    double? unitPriceSold,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.saleItems(saleId),
        data: {
          'productId': productId,
          'qty': qty,
          'unitPriceSold': unitPriceSold,
        },
      );
      return SaleModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo agregar el producto'),
        e.response?.statusCode,
      );
    }
  }

  Future<SaleModel> updateItem(
    String saleId,
    String itemId, {
    int? qty,
    double? unitPriceSold,
  }) async {
    try {
      final res = await _dio.put(
        ApiRoutes.saleItemDetail(saleId, itemId),
        data: {'qty': qty, 'unitPriceSold': unitPriceSold},
      );
      return SaleModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo actualizar el item'),
        e.response?.statusCode,
      );
    }
  }

  Future<SaleModel> removeItem(String saleId, String itemId) async {
    try {
      final res = await _dio.delete(ApiRoutes.saleItemDetail(saleId, itemId));
      return SaleModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo eliminar el item'),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> listMySales({
    DateTime? from,
    DateTime? to,
    String? status,
    String? productId,
    String? clientId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.salesMe,
        queryParameters: _compactQuery({
          'from': from?.toIso8601String(),
          'to': to?.toIso8601String(),
          'status': status,
          'productId': productId,
          'clientId': clientId,
        }),
      );
      final data = (res.data as Map).cast<String, dynamic>();
      final items =
          (data['items'] as List?)
              ?.map(
                (e) => SaleModel.fromJson((e as Map).cast<String, dynamic>()),
              )
              .toList() ??
          <SaleModel>[];
      final summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? {};
      return {'items': items, 'summary': summary};
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo cargar tu historial de ventas'),
        e.response?.statusCode,
      );
    }
  }

  Future<SaleModel> getSale(String saleId) async {
    try {
      final res = await _dio.get(ApiRoutes.saleDetail(saleId));
      return SaleModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo cargar la venta'),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> adminSales({
    DateTime? from,
    DateTime? to,
    String? status,
    String? productId,
    String? clientId,
    String? sellerId,
    String? role,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.adminSales,
        queryParameters: _compactQuery({
          'from': from?.toIso8601String(),
          'to': to?.toIso8601String(),
          'status': status,
          'productId': productId,
          'clientId': clientId,
          'sellerId': sellerId,
          'role': role,
        }),
      );
      final data = (res.data as Map).cast<String, dynamic>();
      final items =
          (data['items'] as List?)
              ?.map(
                (e) => SaleModel.fromJson((e as Map).cast<String, dynamic>()),
              )
              .toList() ??
          <SaleModel>[];
      final summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? {};
      return {'items': items, 'summary': summary};
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo cargar el dashboard de ventas'),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> adminSummary({
    DateTime? from,
    DateTime? to,
    String? productId,
    String? sellerId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.adminSalesSummary,
        queryParameters: _compactQuery({
          'from': from?.toIso8601String(),
          'to': to?.toIso8601String(),
          'productId': productId,
          'sellerId': sellerId,
        }),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo cargar el resumen'),
        e.response?.statusCode,
      );
    }
  }
}
