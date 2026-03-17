import '../debug/trace_log.dart';
import '../offline/offline_store.dart';

class LocalJsonCache {
  static const String _prefix = 'ft_cache:';

  final OfflineStore _store = OfflineStore.instance;

  String _key(String key) => '$_prefix$key';

  Future<Map<String, dynamic>?> readMap(String key, {Duration? maxAge}) async {
    try {
      final value = await _store.readCacheEntry(_key(key), maxAge: maxAge);
      TraceLog.log(
        'cache',
        value == null ? 'cache miss key=$key' : 'cache hit key=$key',
      );
      return value;
    } catch (error, stackTrace) {
      TraceLog.log(
        'cache',
        'cache read error key=$key',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    TraceLog.log('cache', 'cache write key=$key');
    await _store.writeCacheEntry(_key(key), value);
  }

  Future<void> remove(String key) async {
    TraceLog.log('cache', 'cache remove key=$key');
    await _store.removeCacheEntry(_key(key));
  }
}
