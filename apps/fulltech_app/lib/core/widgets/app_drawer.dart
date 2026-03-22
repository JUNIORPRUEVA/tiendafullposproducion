import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_provider.dart';
import '../models/user_model.dart';
import '../routing/routes.dart';
import 'app_navigation.dart';

class AppDrawer extends ConsumerWidget {
  final UserModel? currentUser;

  const AppDrawer({super.key, this.currentUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = buildAppNavigationSections(ref, currentUser);
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final isCompactMobile = mediaQuery.size.width < 390;
    final location = safeCurrentLocation(context);

    // Deep professional blue, consistent with desktop sidebar (theme-based).
    final deepBlue = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.86),
      colorScheme.tertiary,
    );
    final base = Color.alphaBlend(
      colorScheme.secondary.withValues(alpha: 0.08),
      deepBlue,
    );
    final onBase = colorScheme.onPrimary;

    final panelShadow = BoxShadow(
      color: theme.colorScheme.shadow.withValues(alpha: 0.10),
      blurRadius: 20,
      offset: const Offset(6, 0),
    );

    return Drawer(
      child: DecoratedBox(
        decoration: BoxDecoration(color: base, boxShadow: [panelShadow]),
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
                    color: onBase.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(
                      isCompactMobile ? 9 : 10,
                    ),
                    border: Border.all(color: onBase.withValues(alpha: 0.10)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.business_rounded,
                        color: onBase,
                        size: isCompactMobile ? 15 : 16,
                      ),
                      SizedBox(width: isCompactMobile ? 6 : 8),
                      Expanded(
                        child: Text(
                          'FULLTECH, SRL',
                          style: TextStyle(
                            color: onBase,
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
                  isCompactMobile ? 8 : 10,
                  isCompactMobile ? 2 : 4,
                  isCompactMobile ? 8 : 10,
                  isCompactMobile ? 8 : 10,
                ),
                child: Row(
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
