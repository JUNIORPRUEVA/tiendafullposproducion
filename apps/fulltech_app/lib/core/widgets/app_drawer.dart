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
    const slate50 = Color(0xFFF8FAFC);
    const slate400 = Color(0xFF94A3B8);
    const panelTop = Color(0xFF0F172A);
    const panelBottom = Color(0xFF111C31);

    final panelShadow = BoxShadow(
      color: branding.tertiary.withValues(alpha: 0.14),
      blurRadius: 26,
      offset: const Offset(6, 0),
    );

    return Drawer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [panelTop, panelBottom],
          ),
          boxShadow: [panelShadow],
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompactMobile ? 12 : 14,
                  isCompactMobile ? 10 : 12,
                  isCompactMobile ? 12 : 14,
                  10,
                ),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    isCompactMobile ? 10 : 12,
                    isCompactMobile ? 10 : 11,
                    isCompactMobile ? 10 : 12,
                    isCompactMobile ? 10 : 11,
                  ),
                  decoration: BoxDecoration(
                    color: onBase.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: onBase.withValues(alpha: 0.08)),
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
                              radius: isCompactMobile ? 17 : 18,
                              backgroundColor: onBase.withValues(alpha: 0.16),
                              child: Text(
                                userInitials(currentUser),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: onBase,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'FULLTECH',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: slate50,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  branding.departmentName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: slate400,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: BoxConstraints(
                          maxWidth: isCompactMobile ? 210 : 240,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: onBase.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: onBase.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 14,
                              color: slate400,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                userDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: slate50,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
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
                  padding: EdgeInsets.fromLTRB(
                    isCompactMobile ? 8 : 10,
                    4,
                    isCompactMobile ? 8 : 10,
                    8,
                  ),
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
                      SizedBox(height: isCompactMobile ? 12 : 16),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: onBase.withValues(alpha: 0.08)),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompactMobile ? 10 : 12,
                  8,
                  isCompactMobile ? 10 : 12,
                  12,
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: onBase.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: onBase.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        branding.departmentName,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: slate400,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
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
                            color: slate400,
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

class _DrawerMenuItem extends StatefulWidget {
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
  State<_DrawerMenuItem> createState() => _DrawerMenuItemState();
}

class _DrawerMenuItemState extends State<_DrawerMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const activeText = Color(0xFFFFFFFF);
    const normalText = Color(0xFF94A3B8);
    final selected = widget.selected;
    final tileBg = selected
        ? Colors.white.withValues(alpha: 0.12)
        : (_hovered ? Colors.white.withValues(alpha: 0.06) : Colors.transparent);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.compact ? 1 : 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOut,
              height: widget.compact ? 44 : 46,
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 12 : 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    width: 3,
                    height: 24,
                    decoration: BoxDecoration(
                      color: selected
                          ? colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  SizedBox(width: selected ? 10 : 13),
                  Icon(
                    widget.icon,
                    size: widget.compact ? 18 : 19,
                    color: selected ? activeText : normalText,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: widget.compact ? 13.4 : 14,
                        color: selected ? activeText : normalText,
                      ),
                    ),
                  ),
                  if (widget.showIndicator)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
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
    const titleColor = Color(0xFF64748B);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 6 : 8,
        compact ? 14 : 16,
        compact ? 6 : 8,
        compact ? 6 : 8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: titleColor,
                letterSpacing: 0.9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
