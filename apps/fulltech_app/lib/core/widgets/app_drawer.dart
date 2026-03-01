import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../auth/role_permissions.dart';
import '../models/user_model.dart';
import '../routing/routes.dart';

class AppDrawer extends ConsumerWidget {
  final UserModel? currentUser;

  const AppDrawer({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = currentUser?.role == 'ADMIN';
    final canAccessContabilidad = canAccessContabilidadByRole(currentUser?.role);
    final colorScheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final isCompactMobile = mediaQuery.size.width < 390;
    final location = _safeLocation(context);

    // Theme-driven blue/white gradient (more visible than a tiny lerp).
    final gradientTop = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.08),
      colorScheme.surface,
    );
    final gradientMid = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.14),
      colorScheme.surface,
    );
    final gradientBottom = Color.alphaBlend(
      colorScheme.secondary.withValues(alpha: 0.18),
      colorScheme.surface,
    );

    bool isActiveRoute(String route) {
      return location == route || location.startsWith('$route/');
    }

    return Drawer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [gradientTop, gradientMid, gradientBottom],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompactMobile ? 10 : 14,
                  isCompactMobile ? 10 : 12,
                  isCompactMobile ? 10 : 14,
                  isCompactMobile ? 6 : 8,
                ),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompactMobile ? 9 : 10,
                    vertical: isCompactMobile ? 7 : 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(isCompactMobile ? 9 : 10),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.business_rounded,
                        color: colorScheme.primary,
                        size: isCompactMobile ? 15 : 16,
                      ),
                      SizedBox(width: isCompactMobile ? 6 : 8),
                      Expanded(
                        child: Text(
                          'FULLTECH, SRL',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: isCompactMobile ? 12 : 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _DrawerSectionTitle('Principal', compact: isCompactMobile),
                    _DrawerMenuItem(
                      icon: Icons.build_outlined,
                      title: 'Operaciones',
                      compact: isCompactMobile,
                      selected: isActiveRoute(Routes.operaciones),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(Routes.operaciones);
                      },
                    ),
                    _DrawerMenuItem(
                      icon: Icons.access_time_rounded,
                      title: 'Ponche',
                      compact: isCompactMobile,
                      selected: isActiveRoute(Routes.ponche),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(Routes.ponche);
                      },
                    ),
                    _DrawerMenuItem(
                      icon: Icons.storefront_outlined,
                      title: 'Catálogo',
                      compact: isCompactMobile,
                      selected: isActiveRoute(Routes.catalogo),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(Routes.catalogo);
                      },
                    ),
                    _DrawerMenuItem(
                      icon: Icons.point_of_sale_outlined,
                      title: 'Mis Ventas',
                      compact: isCompactMobile,
                      selected: isActiveRoute(Routes.ventas),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(Routes.ventas);
                      },
                    ),
                    _DrawerMenuItem(
                      icon: Icons.request_quote_outlined,
                      title: 'Cotizaciones',
                      compact: isCompactMobile,
                      selected: isActiveRoute(Routes.cotizaciones),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(Routes.cotizaciones);
                      },
                    ),
                    _DrawerMenuItem(
                      icon: Icons.group_outlined,
                      title: 'Clientes',
                      compact: isCompactMobile,
                      selected: isActiveRoute(Routes.clientes),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(Routes.clientes);
                      },
                    ),
                    if (canAccessContabilidad)
                      _DrawerMenuItem(
                        icon: Icons.account_balance,
                        title: 'Contabilidad',
                        compact: isCompactMobile,
                        selected: isActiveRoute(Routes.contabilidad),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(Routes.contabilidad);
                        },
                      ),
                    if (isAdmin)
                      _DrawerMenuItem(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Administración',
                        compact: isCompactMobile,
                        selected: isActiveRoute(Routes.administracion),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(Routes.administracion);
                        },
                      ),

                    SizedBox(height: isCompactMobile ? 2 : 4),
                    _DrawerSectionTitle('Nómina', compact: isCompactMobile),
                    if (isAdmin)
                      _DrawerMenuItem(
                        icon: Icons.payments_outlined,
                        title: 'Nómina',
                        compact: isCompactMobile,
                        selected: isActiveRoute(Routes.nomina),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(Routes.nomina);
                        },
                      ),
                    _DrawerMenuItem(
                      icon: Icons.receipt_long_outlined,
                      title: 'Mis pagos',
                      compact: isCompactMobile,
                      selected: isActiveRoute(Routes.misPagos),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(Routes.misPagos);
                      },
                    ),

                    SizedBox(height: isCompactMobile ? 2 : 4),
                    _DrawerSectionTitle('Cuenta', compact: isCompactMobile),
                    if (isAdmin)
                      _DrawerMenuItem(
                        icon: Icons.settings_outlined,
                        title: 'Configuración',
                        compact: isCompactMobile,
                        selected: isActiveRoute(Routes.configuracion),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(Routes.configuracion);
                        },
                      ),
                    if (isAdmin)
                      _DrawerMenuItem(
                        icon: Icons.people_outline,
                        title: 'Usuarios',
                        compact: isCompactMobile,
                        selected: isActiveRoute(Routes.users),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(Routes.users);
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompactMobile ? 8 : 10,
                  isCompactMobile ? 2 : 4,
                  isCompactMobile ? 8 : 10,
                  isCompactMobile ? 8 : 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        selected: isActiveRoute(Routes.profile),
                        selectedTileColor: colorScheme.primary.withValues(
                          alpha: 0.10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            isCompactMobile ? 10 : 12,
                          ),
                        ),
                        leading: Icon(
                          Icons.badge_outlined,
                          size: isCompactMobile ? 20 : 22,
                        ),
                        title: Text(
                          'Perfil',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: isCompactMobile ? 13 : 14,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: colorScheme.onSurfaceVariant,
                          size: isCompactMobile ? 18 : 20,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(Routes.profile);
                        },
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isCompactMobile ? 12 : 16,
                          vertical: isCompactMobile ? 4 : 6,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar sesión',
                      onPressed: () async {
                        Navigator.pop(context);
                        await ref.read(authStateProvider.notifier).logout();
                        if (context.mounted) {
                          context.go(Routes.login);
                        }
                      },
                      icon: Icon(
                        Icons.logout_rounded,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _safeLocation(BuildContext context) {
  try {
    // `GoRouterState.of(context)` can throw in some widget subtrees (e.g. Drawer).
    return GoRouterState.of(context).uri.toString();
  } catch (_) {
    try {
      return GoRouter.of(context)
          .routerDelegate
          .currentConfiguration
          .uri
          .toString();
    } catch (_) {
      return '';
    }
  }
}

class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
    required this.title,
    required this.compact,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tileBg = selected
        ? Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.surface,
          )
        : colorScheme.surface.withValues(alpha: 0.92);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 10,
        compact ? 2 : 3,
        compact ? 8 : 10,
        compact ? 2 : 3,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: tileBg,
          borderRadius: BorderRadius.circular(compact ? 12 : 14),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.20)
                : colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: ListTile(
          dense: true,
          visualDensity: compact
              ? const VisualDensity(horizontal: -1, vertical: -2)
              : VisualDensity.compact,
          selected: selected,
          leading: Icon(
            icon,
            size: compact ? 20 : 22,
            color: selected ? colorScheme.primary : colorScheme.onSurface,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: compact ? 13.5 : 14.5,
              color: selected ? colorScheme.primary : null,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: compact ? 18 : 19,
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          onTap: onTap,
          contentPadding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 2 : 4,
          ),
        ),
      ),
    );
  }
}

class _DrawerSectionTitle extends StatelessWidget {
  final String text;
  final bool compact;

  const _DrawerSectionTitle(this.text, {required this.compact});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 14,
        compact ? 6 : 8,
        compact ? 12 : 14,
        compact ? 3 : 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: compact ? 10.5 : 11,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
