import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_provider.dart';
import '../auth/app_role.dart';
import '../models/user_model.dart';
import '../routing/routes.dart';
import '../theme/role_branding.dart';
import 'app_navigation.dart';
import 'user_avatar.dart';

class AppDrawer extends ConsumerWidget {
  final UserModel? currentUser;

  const AppDrawer({super.key, this.currentUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = buildAppNavigationSections(ref, currentUser);
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final isCompactMobile = mediaQuery.size.width < 390;
    final location = safeCurrentLocation(context);
    final role =
        currentUser?.appRole ??
        ref.watch(authStateProvider).user?.appRole ??
        AppRole.unknown;
    final branding = resolveRoleBranding(role);
    final userDisplayName =
        currentUser?.nombreCompleto.trim().isNotEmpty == true
        ? currentUser!.nombreCompleto
        : branding.departmentName;
    const onBase = Colors.white;

    final panelShadow = BoxShadow(
      color: branding.tertiary.withValues(alpha: 0.14),
      blurRadius: 26,
      offset: const Offset(6, 0),
    );

    return Drawer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: branding.drawerGradient,
          boxShadow: [panelShadow],
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompactMobile ? 12 : 16,
                  isCompactMobile ? 12 : 16,
                  isCompactMobile ? 12 : 16,
                  isCompactMobile ? 8 : 10,
                ),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    isCompactMobile ? 12 : 14,
                    isCompactMobile ? 11 : 13,
                    isCompactMobile ? 12 : 14,
                    isCompactMobile ? 11 : 13,
                  ),
                  decoration: BoxDecoration(
                    color: onBase.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: onBase.withValues(alpha: 0.10)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              context.go(Routes.profile);
                            },
                            child: UserAvatar(
                              imageUrl: currentUser?.fotoPersonalUrl,
                              radius: isCompactMobile ? 19 : 21,
                              backgroundColor: onBase.withValues(alpha: 0.18),
                              child: Text(
                                userInitials(currentUser),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: onBase,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'FULLTECH',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: onBase,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.9,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  branding.departmentName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: onBase.withValues(alpha: 0.88),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        constraints: BoxConstraints(
                          maxWidth: isCompactMobile ? 210 : 240,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: onBase.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: onBase.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 15,
                              color: onBase.withValues(alpha: 0.82),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                userDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: onBase,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
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
                    for (final section in sections) ...[
                      _DrawerSectionTitle(
                        section.title,
                        compact: isCompactMobile,
                      ),
                      for (final item in section.items)
                        _DrawerMenuItem(
                          icon: item.icon,
                          title: item.title,
                          compact: isCompactMobile,
                          selected: isNavigationRouteActive(
                            location,
                            item.route,
                          ),
                          showIndicator: item.showIndicator,
                          onTap: () {
                            Navigator.pop(context);
                            context.go(item.route);
                          },
                        ),
                      SizedBox(height: isCompactMobile ? 2 : 4),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: onBase.withValues(alpha: 0.12)),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompactMobile ? 10 : 12,
                  isCompactMobile ? 8 : 10,
                  isCompactMobile ? 10 : 12,
                  isCompactMobile ? 12 : 14,
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: onBase.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: onBase.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Text(
                        branding.departmentName,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: onBase.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _DrawerMenuItem(
                            icon: Icons.badge_outlined,
                            title: 'Perfil',
                            compact: isCompactMobile,
                            selected: isNavigationRouteActive(
                              location,
                              Routes.profile,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              context.go(Routes.profile);
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar sesion',
                          onPressed: () async {
                            Navigator.pop(context);
                            await ref.read(authStateProvider.notifier).logout();
                          },
                          icon: Icon(
                            Icons.logout_rounded,
                            color: onBase.withValues(alpha: 0.92),
                          ),
                        ),
                      ],
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

Widget? buildAdaptiveDrawer(
  BuildContext context, {
  required UserModel? currentUser,
}) {
  // Never show drawer inside dialogs/bottom-sheet routes.
  final route = ModalRoute.of(context);
  if (route is PopupRoute) return null;
  if (route is PageRoute && route.fullscreenDialog) return null;

  final width = MediaQuery.sizeOf(context).width;
  if (width >= kDesktopShellBreakpoint) return null;
  return AppDrawer(currentUser: currentUser);
}

class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool compact;
  final bool selected;
  final bool showIndicator;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
    required this.title,
    required this.compact,
    required this.selected,
    this.showIndicator = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final deepBlue = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.86),
      colorScheme.tertiary,
    );
    final base = Color.alphaBlend(
      colorScheme.secondary.withValues(alpha: 0.08),
      deepBlue,
    );
    final onBase = colorScheme.onPrimary;
    final tileBg = selected
        ? Color.alphaBlend(colorScheme.primary.withValues(alpha: 0.26), base)
        : Colors.transparent;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 10,
        compact ? 1 : 2,
        compact ? 8 : 10,
        compact ? 1 : 2,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: tileBg,
          borderRadius: BorderRadius.circular(compact ? 12 : 14),
          border: Border.all(
            color: selected
                ? onBase.withValues(alpha: 0.16)
                : onBase.withValues(alpha: 0.08),
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
            color: selected ? onBase : onBase.withValues(alpha: 0.88),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: compact ? 13.5 : 14.5,
              color: selected ? onBase : onBase.withValues(alpha: 0.92),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showIndicator)
                Container(
                  width: compact ? 8 : 9,
                  height: compact ? 8 : 9,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
              Icon(
                Icons.chevron_right_rounded,
                size: compact ? 18 : 19,
                color: selected ? onBase : onBase.withValues(alpha: 0.70),
              ),
            ],
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
    final scheme = Theme.of(context).colorScheme;
    final onBase = scheme.onPrimary;
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
                color: onBase.withValues(alpha: 0.68),
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
