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
    final location = GoRouterState.of(context).uri.path;

    bool isActiveRoute(String route) {
      return location == route || location.startsWith('$route/');
    }

    return Drawer(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFFFF), Color(0xFFF5F9FF), Color(0xFFE8F0FF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.business_rounded,
                        color: colorScheme.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'FULLTECH, SRL',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: 13,
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
                    const _DrawerSectionTitle('Principal'),
                    _DrawerMenuItem(
                      icon: Icons.point_of_sale_outlined,
                      title: 'Mis Ventas',
                      subtitle: 'Registro y comisión',
                      selected: isActiveRoute(Routes.ventas),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(Routes.ventas);
                      },
                    ),
                    _DrawerMenuItem(
                      icon: Icons.request_quote_outlined,
                      title: 'Cotizaciones',
                      subtitle: 'Ticket rápido móvil',
                      selected: isActiveRoute(Routes.cotizaciones),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(Routes.cotizaciones);
                      },
                    ),
                    _DrawerMenuItem(
                      icon: Icons.group_outlined,
                      title: 'Clientes',
                      subtitle: 'Contactos y datos',
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
                        subtitle: 'Estado y finanzas',
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
                        subtitle: 'Panel global empresa',
                        selected: isActiveRoute(Routes.administracion),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(Routes.administracion);
                        },
                      ),

                    const SizedBox(height: 4),
                    const _DrawerSectionTitle('Nómina'),
                    if (isAdmin)
                      _DrawerMenuItem(
                        icon: Icons.payments_outlined,
                        title: 'Nómina',
                        subtitle: 'Gestión de nómina',
                        selected: isActiveRoute(Routes.nomina),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(Routes.nomina);
                        },
                      ),
                    _DrawerMenuItem(
                      icon: Icons.receipt_long_outlined,
                      title: 'Mis pagos',
                      subtitle: 'Historial y acumulados',
                      selected: isActiveRoute(Routes.misPagos),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(Routes.misPagos);
                      },
                    ),

                    const SizedBox(height: 4),
                    const _DrawerSectionTitle('Cuenta'),
                    if (isAdmin)
                      _DrawerMenuItem(
                        icon: Icons.settings_outlined,
                        title: 'Configuración',
                        subtitle: 'Datos de la empresa',
                        selected: isActiveRoute(Routes.configuracion),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(Routes.configuracion);
                        },
                      ),
                    _DrawerMenuItem(
                      icon: Icons.people_outline,
                      title: 'Usuarios',
                      subtitle: 'Gestión y perfiles',
                      selected: isActiveRoute(Routes.user),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(Routes.user);
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        selected: isActiveRoute(Routes.profile),
                        selectedTileColor: colorScheme.primary.withValues(
                          alpha: 0.10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: const Icon(Icons.badge_outlined),
                        title: const Text(
                          'Perfil',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Datos y preferencias',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(Routes.profile);
                        },
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
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

class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.20)
                : colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          selected: selected,
          leading: Icon(
            icon,
            size: 20,
            color: selected ? colorScheme.primary : colorScheme.onSurface,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: selected ? colorScheme.primary : null,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 0,
          ),
        ),
      ),
    );
  }
}

class _DrawerSectionTitle extends StatelessWidget {
  final String text;

  const _DrawerSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
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
