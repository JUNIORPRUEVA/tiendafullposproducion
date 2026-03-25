import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/cache/fulltech_cache_manager.dart';
import '../../../core/models/product_model.dart';
import '../../../core/realtime/catalog_realtime_service.dart';
import '../data/catalog_local_repository.dart';
import '../data/catalog_repository.dart';
import '../data/catalog_sync_utils.dart';

final catalogBackgroundSyncServiceProvider =
    Provider<CatalogBackgroundSyncService>((ref) {
      final service = CatalogBackgroundSyncService(
        repository: ref.watch(catalogRepositoryProvider),
        localRepository: ref.watch(catalogLocalRepositoryProvider),
        realtimeService: ref.watch(catalogRealtimeServiceProvider),
      );
      ref.onDispose(service.dispose);
      return service;
    });

final catalogBackgroundSyncBootstrapProvider = Provider<void>((ref) {
  final authState = ref.watch(authStateProvider);
  final service = ref.watch(catalogBackgroundSyncServiceProvider);

  if (authState.isAuthenticated) {
    unawaited(service.start());
  } else {
    service.stop();
  }
});

class CatalogBackgroundSyncService {
  CatalogBackgroundSyncService({
    required CatalogRepository repository,
    required CatalogLocalRepository localRepository,
    required CatalogRealtimeService realtimeService,
  }) : _repository = repository,
       _localRepository = localRepository,
       _realtimeService = realtimeService;

  static const _liveSyncInterval = Duration(minutes: 2);
  static const _staleAfter = Duration(minutes: 2);

  final CatalogRepository _repository;
  final CatalogLocalRepository _localRepository;
  final CatalogRealtimeService _realtimeService;

  StreamSubscription<CatalogRealtimeMessage>? _realtimeSubscription;
  Timer? _timer;
  bool _started = false;
  bool _syncInFlight = false;
  bool _queuedForceRemoteSync = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _realtimeSubscription = _realtimeService.stream.listen((_) {
      unawaited(syncNow(forceRemote: true));
    });
    _timer?.cancel();
    _timer = Timer.periodic(_liveSyncInterval, (_) {
      unawaited(syncNow(forceRemote: true));
    });

    final snapshot = await _localRepository.readSnapshot();
    final shouldRefresh =
        snapshot.items.isEmpty ||
        snapshot.lastSyncedAt == null ||
        DateTime.now().difference(snapshot.lastSyncedAt!) > _staleAfter;
    if (shouldRefresh) {
      await syncNow(forceRemote: true);
    }
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _queuedForceRemoteSync = false;
  }

  Future<void> syncNow({bool forceRemote = false}) async {
    if (!_started) return;
    if (_syncInFlight) {
      _queuedForceRemoteSync = _queuedForceRemoteSync || forceRemote;
      return;
    }

    _syncInFlight = true;
    try {
      final previousSnapshot = await _localRepository.readSnapshot();
      final fetched = await _repository.fetchProducts(
        forceRefresh: forceRemote,
        silent: true,
      );
      final merged = mergeRecoveredCatalogImages(
        previousItems: previousSnapshot.items,
        fetchedItems: fetched,
      );
      final catalogVersion = buildCatalogSyncVersion(merged);
      final items = applyCatalogSyncVersion(merged, catalogVersion);
      await _localRepository.saveSnapshot(
        items,
        syncedAt: DateTime.now(),
        catalogVersion: catalogVersion,
      );
      Future<void>.microtask(
        () => FulltechImageCacheManager.warmImageUrls(
          items.map((item) => item.displayFotoUrl),
        ),
      );
    } catch (_) {
      // Keep the last local snapshot if the cloud refresh fails.
    } finally {
      _syncInFlight = false;
      if (_queuedForceRemoteSync) {
        _queuedForceRemoteSync = false;
        unawaited(syncNow(forceRemote: true));
      }
    }
  }

  void dispose() {
    stop();
  }
}