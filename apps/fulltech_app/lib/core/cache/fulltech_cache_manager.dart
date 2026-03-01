import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class FulltechImageCacheManager {
  static const _key = 'fulltechProductImages';

  static final CacheManager instance = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 2500,
    ),
  );

  static Future<void> clear() => instance.emptyCache();
}
