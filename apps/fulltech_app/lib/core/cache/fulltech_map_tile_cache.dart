import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class FulltechMapTileCacheManager {
  static const _key = 'fulltechMapTilesV1';

  static final CacheManager instance = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 45),
      maxNrOfCacheObjects: 8000,
    ),
  );

  static Future<void> warmTileUrls(
    Iterable<String> urls, {
    int maxUrls = 64,
  }) async {
    final unique = <String>{};
    for (final raw in urls) {
      final url = raw.trim();
      if (url.isEmpty) continue;
      if (!unique.add(url)) continue;
      if (unique.length >= maxUrls) break;
    }

    for (final url in unique) {
      try {
        await instance.downloadFile(url);
      } catch (_) {
        // Ignore individual warm-up failures.
      }
    }
  }
}
