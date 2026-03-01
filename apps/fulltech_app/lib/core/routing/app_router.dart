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
import '../../features/operaciones/operaciones_mapa_clientes_screen.dart';
import '../../features/operaciones/operaciones_reglas_screen.dart';
import '../../features/contabilidad/contabilidad_screen.dart';
import '../../features/contabilidad/cierres_diarios_screen.dart';
import '../../features/contabilidad/factura_fiscal_screen.dart';
import '../../features/contabilidad/pagos_pendientes_screen.dart';
import '../../features/administracion/administracion_screen.dart';
import '../../features/catalogo/catalogo_screen.dart';
import '../../modules/clientes/cliente_detail_screen.dart';
import '../../modules/clientes/clientes_screen.dart';
import '../../modules/clientes/cliente_form_screen.dart';
import '../../modules/nomina/nomina_screen.dart';
import '../../modules/nomina/mis_pagos_screen.dart';
import '../../modules/configuracion/configuracion_screen.dart';
import '../../modules/cotizaciones/cotizaciones_historial_screen.dart';
import '../../modules/cotizaciones/cotizaciones_screen.dart';
import '../../modules/ventas/mis_ventas_screen.dart';
import '../../modules/ventas/registrar_venta_screen.dart';
import '../auth/auth_provider.dart';
import '../auth/role_permissions.dart';
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
      GoRoute(
        path: Routes.registrarVenta,
        builder: (context, state) => const RegistrarVentaScreen(),
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
            path: Routes.operacionesAgenda,
            builder: (context, state) => const OperacionesAgendaScreen(),
          ),
          GoRoute(
            path: Routes.operacionesMapaClientes,
            builder: (context, state) => const OperacionesMapaClientesScreen(),
          ),
          GoRoute(
            path: Routes.operacionesReglas,
            builder: (context, state) => const OperacionesReglasScreen(),
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
            path: Routes.contabilidadCierresDiarios,
            builder: (context, state) => const CierresDiariosScreen(),
          ),
          GoRoute(
            path: Routes.contabilidadFacturaFiscal,
            builder: (context, state) => const FacturaFiscalScreen(),
          ),
          GoRoute(
            path: Routes.contabilidadPagosPendientes,
            builder: (context, state) => const PagosPendientesScreen(),
          ),
          GoRoute(
            path: Routes.administracion,
            builder: (context, state) => const AdministracionScreen(),
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
            path: Routes.cotizaciones,
            builder: (context, state) => const CotizacionesScreen(),
          ),
          GoRoute(
            path: Routes.cotizacionesHistorial,
            builder: (context, state) {
              final phone = (state.uri.queryParameters['customerPhone'] ?? '')
                  .trim();
              final pick = (state.uri.queryParameters['pick'] ?? '').trim();
              final pickForEditor = pick != '0';
              return CotizacionesHistorialScreen(
                customerPhone: phone.isEmpty ? null : phone,
                pickForEditor: pickForEditor,
              );
            },
          ),
          GoRoute(
            path: Routes.configuracion,
            builder: (context, state) => const ConfiguracionScreen(),
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
      final auth = ref.read(authStateProvider);
      final initialized = auth.initialized;
      final isAuth = auth.isAuthenticated;
      final isAdmin = (auth.user?.role ?? '').toUpperCase() == 'ADMIN';
      final canAccessContabilidad = canAccessContabilidadByRole(
        auth.user?.role,
      );
      final loc = state.uri.toString();
      final isAuthRoute = loc == Routes.login;
      final isSplash = loc == Routes.splash;
      final isConfigRoute =
          loc == Routes.configuracion ||
          loc.startsWith('${Routes.configuracion}/');
      final isContabilidadRoute =
          loc == Routes.contabilidad ||
          loc.startsWith('${Routes.contabilidad}/');
      final isAdminRoute =
          loc == Routes.administracion ||
          loc.startsWith('${Routes.administracion}/');

      if (!initialized) {
        return isSplash ? null : Routes.splash;
      }

      if (isSplash) {
        return isAuth ? Routes.operaciones : Routes.login;
      }

      if (!isAuth) {
        return isAuthRoute ? null : Routes.login;
      }

      if (isAuth && isAuthRoute) {
        return Routes.operaciones;
      }

      if (isConfigRoute && !isAdmin) {
        return Routes.operaciones;
      }

      if (isContabilidadRoute && !canAccessContabilidad) {
        return Routes.operaciones;
      }

      if (isAdminRoute && !isAdmin) {
        return Routes.operaciones;
      }

      return null;
    },
  );
});

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
