import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import '../models/user_model.dart';

class AuthState {
  final bool isAuthenticated;
  final UserModel? user;
  final bool loading;

  AuthState({required this.isAuthenticated, this.user, this.loading = false});

  AuthState copyWith({bool? isAuthenticated, UserModel? user, bool? loading}) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      loading: loading ?? this.loading,
    );
  }
}

final authStateProvider = StateNotifierProvider<AuthController, AuthState>((
  ref,
) {
  return AuthController(ref);
});

class AuthController extends StateNotifier<AuthState> {
  final Ref ref;

  AuthController(this.ref) : super(AuthState(isAuthenticated: false, loading: true)) {
    _init();
  }

  Future<void> _init() async {
    final repo = ref.read(authRepositoryProvider);
    final user = await repo.getMeOrNull();
    if (user != null) {
      state = state.copyWith(isAuthenticated: true, user: user, loading: false);
      return;
    }

    state = state.copyWith(isAuthenticated: false, user: null, loading: false);
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(loading: true);
    final repo = ref.read(authRepositoryProvider);
    try {
      final user = await repo.login(email, password);
      state = AuthState(isAuthenticated: true, user: user, loading: false);
      return true;
    } catch (_) {
      state = state.copyWith(loading: false, isAuthenticated: false);
      rethrow;
    }
  }

  Future<void> logout() async {
    final storage = ref.read(tokenStorageProvider);
    await storage.clearTokens();
    state = AuthState(isAuthenticated: false, user: null, loading: false);
  }

  void setUser(UserModel user) {
    state = state.copyWith(user: user, isAuthenticated: true);
  }
}
