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

  Timer? _showTimer;

  AppLoadingController() : super(AppLoadingState.initial());

  void requestStarted() {
    final nextCount = state.count + 1;
    state = state.copyWith(count: nextCount);

    if (nextCount == 1) {
      _showTimer?.cancel();
      _showTimer = Timer(_showDelay, () {
        if (mounted && state.count > 0) {
          state = state.copyWith(visible: true);
        }
      });
    }
  }

  void requestEnded() {
    final nextCount = (state.count - 1).clamp(0, 1 << 30);
    if (nextCount == 0) {
      _showTimer?.cancel();
      _showTimer = null;
      state = state.copyWith(count: 0, visible: false);
      return;
    }
    state = state.copyWith(count: nextCount);
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }
}
