import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/user/user_screen.dart';
import '../../features/user/profile_screen.dart';
import '../../features/user/users_screen.dart';
import '../../features/ponche/ponche_screen.dart';
import '../../features/operaciones/operaciones_screen.dart';
import '../../features/ventas/ventas_screen.dart';
import '../../features/contabilidad/contabilidad_screen.dart';
import '../auth/auth_provider.dart';
import 'routes.dart';

final _routerRefreshProvider = Provider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier();
  ref.listen<AuthState>(authStateProvider, (_, __) => notifier.refresh());
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);
  final refresh = ref.watch(_routerRefreshProvider);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(path: Routes.register, redirect: (_, __) => Routes.login),
      GoRoute(path: Routes.home, redirect: (_, __) => Routes.user),
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: Routes.user,
            builder: (context, state) => const UserScreen(),
          ),
          GoRoute(
            path: Routes.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: Routes.users,
            builder: (context, state) => const UsersScreen(),
          ),
          GoRoute(
            path: Routes.ponche,
            builder: (context, state) => const PoncheScreen(),
          ),
          GoRoute(
            path: Routes.operaciones,
            builder: (context, state) => const OperacionesScreen(),
          ),
          GoRoute(
            path: Routes.ventas,
            builder: (context, state) => const VentasScreen(),
          ),
          GoRoute(
            path: Routes.contabilidad,
            builder: (context, state) => const ContabilidadScreen(),
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final isAuth = auth.isAuthenticated;
      final isLoading = auth.loading;
      final loc = state.uri.toString();
      final isAuthRoute = loc == Routes.login;
      final isSplash = loc == Routes.splash;

      if (isLoading) {
        return isSplash ? null : Routes.splash;
      }

      if (!isAuth) {
        return isAuthRoute ? null : Routes.login;
      }

      if (isAuth && (isAuthRoute || isSplash)) {
        return Routes.user;
      }

      return null;
    },
  );
});

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
