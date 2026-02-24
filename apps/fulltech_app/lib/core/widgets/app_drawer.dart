import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../models/user_model.dart';
import '../routing/routes.dart';

class AppDrawer extends ConsumerWidget {
  final UserModel? currentUser;

  const AppDrawer({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = currentUser?.role == 'ADMIN';
    final colorScheme = Theme.of(context).colorScheme;
    final location = GoRouterState.of(context).uri.path;

    bool isActiveRoute(String route) {
      return location == route || location.startsWith('$route/');
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.business_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'FULLTECH, SRL',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (currentUser != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.35,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentUser?.nombreCompleto.isNotEmpty == true
                            ? currentUser!.nombreCompleto
                            : currentUser?.email ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentUser?.role ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
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
                    icon: Icons.group_outlined,
                    title: 'Clientes',
                    subtitle: 'Contactos y datos',
                    selected: isActiveRoute(Routes.clientes),
                    onTap: () {
                      Navigator.pop(context);
                      context.go(Routes.clientes);
                    },
                  ),
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
    return ListTile(
      selected: selected,
      selectedTileColor: colorScheme.primary.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(
        icon,
        color: selected ? colorScheme.primary : colorScheme.primary,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: selected ? colorScheme.primary : null,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
    );
  }
}

class _DrawerSectionTitle extends StatelessWidget {
  final String text;

  const _DrawerSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
