import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class FulltechImageCacheManager {
  static const _key = 'fulltechProductImagesV4';

  static final CacheManager instance = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 2500,
    ),
  );

  static Future<void> warmImageUrls(
    Iterable<String?> urls, {
    int maxUrls = 120,
  }) async {
    final unique = <String>{};
    for (final raw in urls) {
      final url = (raw ?? '').trim();
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

  static Future<void> clear() => instance.emptyCache();
}
