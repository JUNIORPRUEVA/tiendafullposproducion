import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/user/profile_screen.dart';
import '../../features/user/users_screen.dart';
import '../../features/ponche/ponche_screen.dart';
import '../../features/operaciones/operaciones_screen.dart';
import '../../features/contabilidad/contabilidad_screen.dart';
import '../../features/catalogo/catalogo_screen.dart';
import '../../modules/clientes/cliente_detail_screen.dart';
import '../../modules/clientes/clientes_screen.dart';
import '../../modules/clientes/cliente_form_screen.dart';
import '../../modules/nomina/nomina_screen.dart';
import '../../modules/nomina/mis_pagos_screen.dart';
import '../../modules/ventas/mis_ventas_screen.dart';
import '../../modules/ventas/registrar_venta_screen.dart';
import '../auth/auth_provider.dart';
import 'routes.dart';

final _routerRefreshProvider = Provider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier();
  ref.listen<AuthState>(
    authStateProvider,
    (previous, next) => notifier.refresh(),
  );
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
      GoRoute(
        path: Routes.register,
        redirect: (context, state) => Routes.login,
      ),
      GoRoute(
        path: Routes.home,
        redirect: (context, state) => Routes.operaciones,
      ),
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: Routes.user,
            builder: (context, state) => const UsersScreen(),
          ),
          GoRoute(
            path: Routes.nomina,
            builder: (context, state) => const NominaScreen(),
          ),
          GoRoute(
            path: Routes.misPagos,
            builder: (context, state) => const MisPagosScreen(),
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
            path: Routes.catalogo,
            builder: (context, state) => const CatalogoScreen(),
          ),
          GoRoute(
            path: Routes.contabilidad,
            builder: (context, state) => const ContabilidadScreen(),
          ),
          GoRoute(
            path: Routes.clientes,
            builder: (context, state) => const ClientesScreen(),
          ),
          GoRoute(
            path: Routes.ventas,
            builder: (context, state) => const MisVentasScreen(),
          ),
          GoRoute(
            path: Routes.registrarVenta,
            builder: (context, state) => const RegistrarVentaScreen(),
          ),
          GoRoute(
            path: Routes.clienteNuevo,
            builder: (context, state) => const ClienteFormScreen(),
          ),
          GoRoute(
            path: Routes.clienteDetalle,
            builder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return ClienteDetailScreen(clienteId: id);
            },
          ),
          GoRoute(
            path: Routes.clienteEditar,
            builder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return ClienteFormScreen(clienteId: id);
            },
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
        return Routes.operaciones;
      }

      return null;
    },
  );
});

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
