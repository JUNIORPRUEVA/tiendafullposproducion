import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/local_json_cache.dart';
import '../service_order_models.dart';

final serviceOrdersLocalCacheProvider = Provider<ServiceOrdersLocalCache>((ref) {
  return ServiceOrdersLocalCache();
});

class ServiceOrdersLocalCache {
  static const _listCacheKey = 'service_orders:list:v1';
  static const _detailCachePrefix = 'service_orders:detail:';
  static const cacheTtl = Duration(days: 7);

  final LocalJsonCache _cache = LocalJsonCache();

  Future<List<ServiceOrderModel>> getCachedList() async {
    final snapshot = await _cache.readMap(_listCacheKey, maxAge: cacheTtl);
    final rows = snapshot?['items'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => ServiceOrderModel.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> saveListSnapshot(List<ServiceOrderModel> items) async {
    await _cache.writeMap(_listCacheKey, {
      'items': items.map((item) => item.toJson()).toList(growable: false),
    });
    for (final item in items) {
      await saveOrder(item);
    }
  }

  Future<ServiceOrderModel?> getCachedOrder(String id) async {
    final snapshot = await _cache.readMap(
      '$_detailCachePrefix${id.trim()}',
      maxAge: cacheTtl,
    );
    if (snapshot == null) return null;
    return ServiceOrderModel.fromJson(snapshot);
  }

  Future<void> saveOrder(ServiceOrderModel order) async {
    await _cache.writeMap('$_detailCachePrefix${order.id}', order.toJson());
  }

  Future<void> removeOrder(String id) async {
    await _cache.remove('$_detailCachePrefix${id.trim()}');
  }
}