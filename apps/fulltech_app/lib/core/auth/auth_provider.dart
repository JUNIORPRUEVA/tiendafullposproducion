import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import '../models/user_model.dart';
import '../utils/is_flutter_test.dart';

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
    if (isFlutterTest) {
      state = AuthState(
        initialized: true,
        isAuthenticated: false,
        user: null,
        loading: false,
      );
      return;
    }
    try {
      final repo = ref.read(authRepositoryProvider);
      // Avoid adding an additional Future.timeout() here.
      // The repository/Dio layer already applies timeouts and, in widget tests,
      // an extra timeout Timer can remain pending when the widget tree disposes.
      final user = await repo.getMeOrNull();

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
