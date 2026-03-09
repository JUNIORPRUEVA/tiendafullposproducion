import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import '../debug/trace_log.dart';
import '../models/user_model.dart';
import '../utils/is_flutter_test.dart';

class AuthState {
  final bool initialized;
  final bool isAuthenticated;
  final UserModel? user;
  final bool loading;
  final bool restoringSession;
  final bool hasSessionHint;

  AuthState({
    required this.initialized,
    required this.isAuthenticated,
    this.user,
    this.loading = false,
    this.restoringSession = false,
    this.hasSessionHint = false,
  });

  AuthState copyWith({
    bool? initialized,
    bool? isAuthenticated,
    UserModel? user,
    bool? loading,
    bool? restoringSession,
    bool? hasSessionHint,
    bool clearUser = false,
  }) {
    return AuthState(
      initialized: initialized ?? this.initialized,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: clearUser ? null : (user ?? this.user),
      loading: loading ?? this.loading,
      restoringSession: restoringSession ?? this.restoringSession,
      hasSessionHint: hasSessionHint ?? this.hasSessionHint,
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
          restoringSession: false,
          hasSessionHint: false,
        ),
      ) {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final seq = TraceLog.nextSeq();
    final sw = Stopwatch()..start();
    TraceLog.log('Auth', '_bootstrap() start', seq: seq);

    if (isFlutterTest) {
      state = AuthState(
        initialized: true,
        isAuthenticated: false,
        user: null,
        loading: false,
        restoringSession: false,
        hasSessionHint: false,
      );
      return;
    }

    try {
      final repo = ref.read(authRepositoryProvider);
      final hydrated = await repo.hydrateSession();

      if (!mounted) return;

      if (!hydrated.hasToken) {
        state = AuthState(
          initialized: true,
          isAuthenticated: false,
          user: null,
          loading: false,
          restoringSession: false,
          hasSessionHint: false,
        );
        sw.stop();
        TraceLog.log(
          'Auth',
          '_bootstrap() no local session (${sw.elapsedMilliseconds}ms)',
          seq: seq,
        );
        return;
      }

      state = AuthState(
        initialized: true,
        isAuthenticated: true,
        user: hydrated.user,
        loading: false,
        restoringSession: true,
        hasSessionHint: true,
      );
      sw.stop();
      TraceLog.log(
        'Auth',
        '_bootstrap() local session restored (${sw.elapsedMilliseconds}ms)',
        seq: seq,
      );

      unawaited(_verifySession());
    } catch (_) {
      if (!mounted) return;
      state = AuthState(
        initialized: true,
        isAuthenticated: false,
        user: null,
        loading: false,
        restoringSession: false,
        hasSessionHint: false,
      );
    }
  }

  Future<void> _verifySession() async {
    final seq = TraceLog.nextSeq();
    final sw = Stopwatch()..start();
    TraceLog.log('Auth', '_verifySession() start', seq: seq);

    try {
      final result = await ref.read(authRepositoryProvider).verifySession();
      if (!mounted) return;

      switch (result.status) {
        case SessionVerificationStatus.authenticated:
          state = AuthState(
            initialized: true,
            isAuthenticated: true,
            user: result.user,
            loading: false,
            restoringSession: false,
            hasSessionHint: true,
          );
          break;
        case SessionVerificationStatus.invalid:
          state = AuthState(
            initialized: true,
            isAuthenticated: false,
            user: null,
            loading: false,
            restoringSession: false,
            hasSessionHint: false,
          );
          break;
        case SessionVerificationStatus.deferred:
          state = state.copyWith(
            initialized: true,
            isAuthenticated: true,
            user: result.user,
            loading: false,
            restoringSession: false,
            hasSessionHint: true,
          );
          break;
      }
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        initialized: true,
        isAuthenticated: state.hasSessionHint,
        loading: false,
        restoringSession: false,
      );
    } finally {
      sw.stop();
      TraceLog.log(
        'Auth',
        '_verifySession() end (${sw.elapsedMilliseconds}ms)',
        seq: seq,
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
        restoringSession: false,
        hasSessionHint: true,
      );
      return true;
    } catch (_) {
      state = AuthState(
        initialized: true,
        isAuthenticated: false,
        user: null,
        loading: false,
        restoringSession: false,
        hasSessionHint: false,
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
      restoringSession: false,
      hasSessionHint: false,
    );
  }

  void setUser(UserModel user) {
    state = state.copyWith(
      user: user,
      isAuthenticated: true,
      restoringSession: false,
      hasSessionHint: true,
    );
  }
}
