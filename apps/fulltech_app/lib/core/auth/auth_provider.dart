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
  static const Duration _bootstrapTimeout = Duration(seconds: 12);
  static const Duration _storageTimeout = Duration(seconds: 3);
  static const Duration _watchdogTimeout = Duration(seconds: 8);
  Timer? _bootstrapWatchdog;

  AuthController(this.ref)
    : super(AuthState(isAuthenticated: false, loading: true)) {
    _bootstrapWatchdog = Timer(_watchdogTimeout, () {
      if (!mounted) return;
      if (state.loading) {
        state = AuthState(isAuthenticated: false, user: null, loading: false);
      }
    });
    _init();
  }

  Future<void> _init() async {
    bool isAuthenticated = false;
    UserModel? resolvedUser;

    try {
      final repo = ref.read(authRepositoryProvider);
      final user = await repo.getMeOrNull().timeout(_bootstrapTimeout);
      if (user != null) {
        isAuthenticated = true;
        resolvedUser = user;
      } else {
        final storage = ref.read(tokenStorageProvider);
        final token = await storage.getAccessToken().timeout(_storageTimeout);
        if (token != null && token.isNotEmpty) {
          try {
            await storage.clearTokens().timeout(_storageTimeout);
          } catch (_) {}
        }
      }
    } catch (_) {
      final storage = ref.read(tokenStorageProvider);
      try {
        await storage.clearTokens().timeout(_storageTimeout);
      } catch (_) {}
    }

    if (!mounted) return;
    _bootstrapWatchdog?.cancel();
    state = AuthState(
      isAuthenticated: isAuthenticated,
      user: resolvedUser,
      loading: false,
    );
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(loading: true);
    final repo = ref.read(authRepositoryProvider);
    try {
      final user = await repo.login(email, password);
      state = AuthState(isAuthenticated: true, user: user, loading: false);
      return true;
    } catch (_) {
      state = AuthState(isAuthenticated: false, user: null, loading: false);
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

  @override
  void dispose() {
    _bootstrapWatchdog?.cancel();
    super.dispose();
  }
}
