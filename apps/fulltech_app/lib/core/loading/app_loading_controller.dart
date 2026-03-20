import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppLoadingState {
  final int count;
  final bool visible;

  const AppLoadingState({required this.count, required this.visible});

  factory AppLoadingState.initial() =>
      const AppLoadingState(count: 0, visible: false);

  AppLoadingState copyWith({int? count, bool? visible}) {
    return AppLoadingState(
      count: count ?? this.count,
      visible: visible ?? this.visible,
    );
  }
}

final appLoadingProvider =
    StateNotifierProvider<AppLoadingController, AppLoadingState>((ref) {
      return AppLoadingController();
    });

class AppLoadingController extends StateNotifier<AppLoadingState> {
  static const Duration _showDelay = Duration(milliseconds: 220);
  static const Duration _startupGracePeriod = Duration(seconds: 2);
  static const Duration _staleRequestTimeout = Duration(seconds: 30);
  static const Duration _cleanupInterval = Duration(seconds: 5);

  Timer? _showTimer;
  Timer? _cleanupTimer;
  final Map<String, DateTime> _activeRequests = {};
  final DateTime _startedAt = DateTime.now();
  int _requestSequence = 0;

  AppLoadingController() : super(AppLoadingState.initial());

  String requestStarted() {
    final requestId = 'loader-${++_requestSequence}';
    _activeRequests[requestId] = DateTime.now();
    _ensureCleanupTimer();
    _syncState();
    return requestId;
  }

  void requestEnded([String? requestId]) {
    if (requestId != null && requestId.isNotEmpty) {
      _activeRequests.remove(requestId);
    } else if (_activeRequests.isNotEmpty) {
      _activeRequests.remove(_activeRequests.keys.first);
    }
    _syncState();
  }

  void reset() {
    _activeRequests.clear();
    _showTimer?.cancel();
    _showTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    state = const AppLoadingState(count: 0, visible: false);
  }

  void _ensureCleanupTimer() {
    _cleanupTimer ??= Timer.periodic(_cleanupInterval, (_) {
      _removeStaleRequests();
    });
  }

  void _removeStaleRequests() {
    if (_activeRequests.isEmpty) {
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
      return;
    }

    final cutoff = DateTime.now().subtract(_staleRequestTimeout);
    final staleIds = _activeRequests.entries
        .where((entry) => entry.value.isBefore(cutoff))
        .map((entry) => entry.key)
        .toList(growable: false);
    if (staleIds.isEmpty) return;

    for (final requestId in staleIds) {
      _activeRequests.remove(requestId);
    }
    _syncState();
  }

  void _syncState() {
    final nextCount = _activeRequests.length;
    if (nextCount == 0) {
      _showTimer?.cancel();
      _showTimer = null;
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
      if (state.count != 0 || state.visible) {
        state = const AppLoadingState(count: 0, visible: false);
      }
      return;
    }

    if (state.count == 0 && !state.visible) {
      _showTimer?.cancel();
      _showTimer = Timer(_nextShowDelay(), () {
        if (mounted && _activeRequests.isNotEmpty) {
          state = state.copyWith(count: _activeRequests.length, visible: true);
        }
      });
    }

    if (state.count != nextCount) {
      state = state.copyWith(count: nextCount);
    }
  }

  Duration _nextShowDelay() {
    final elapsed = DateTime.now().difference(_startedAt);
    if (elapsed >= _startupGracePeriod) return _showDelay;

    final remainingGrace = _startupGracePeriod - elapsed;
    return remainingGrace > _showDelay ? remainingGrace : _showDelay;
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _cleanupTimer?.cancel();
    _activeRequests.clear();
    super.dispose();
  }
}
