import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import '../models/user_model.dart';

class AuthState {
  final bool initialized;
  final bool isAuthenticated;
  final UserModel? user;
  final bool loading;

  AuthState({
    required this.initialized,
    required this.isAuthenticated,
    this.user,
    this.loading = false,
  });

  AuthState copyWith({
    bool? initialized,
    bool? isAuthenticated,
    UserModel? user,
    bool? loading,
    bool clearUser = false,
  }) {
    return AuthState(
      initialized: initialized ?? this.initialized,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: clearUser ? null : (user ?? this.user),
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
  static const Duration _bootstrapTimeout = Duration(seconds: 10);

  AuthController(this.ref)
    : super(
        AuthState(
          initialized: false,
          isAuthenticated: false,
          user: null,
          loading: false,
        ),
      ) {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final repo = ref.read(authRepositoryProvider);
      final user = await repo.getMeOrNull().timeout(_bootstrapTimeout);

      if (!mounted) return;
      state = AuthState(
        initialized: true,
        isAuthenticated: user != null,
        user: user,
        loading: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = AuthState(
        initialized: true,
        isAuthenticated: false,
        user: null,
        loading: false,
      );
    }
  }

  Future<bool> login(String email, String password) async {
    if (state.loading) return false;
    state = state.copyWith(loading: true);
    final repo = ref.read(authRepositoryProvider);
    try {
      final user = await repo.login(email, password);
      state = AuthState(
        initialized: true,
        isAuthenticated: true,
        user: user,
        loading: false,
      );
      return true;
    } catch (_) {
      state = AuthState(
        initialized: true,
        isAuthenticated: false,
        user: null,
        loading: false,
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    final storage = ref.read(tokenStorageProvider);
    await storage.clearTokens();
    state = AuthState(
      initialized: true,
      isAuthenticated: false,
      user: null,
      loading: false,
    );
  }

  void setUser(UserModel user) {
    state = state.copyWith(user: user, isAuthenticated: true);
  }
}
