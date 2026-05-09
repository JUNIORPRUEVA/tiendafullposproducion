import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_provider.dart';
import '../auth/app_role.dart';
import '../models/user_model.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/role_branding.dart';
import 'app_navigation.dart';
import 'user_avatar.dart';

class AppDrawer extends ConsumerWidget {
  final UserModel? currentUser;

  const AppDrawer({super.key, this.currentUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = buildAppNavigationSections(ref, currentUser);
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
    final panelShadow = BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(6, 0),
    );

    return Drawer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
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
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
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
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.10,
                              ),
                              child: Text(
                                userInitials(currentUser),
                                style: AppTextStyles.small.copyWith(
                                  color: AppColors.primary,
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
                                  style: AppTextStyles.title.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  branding.departmentName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.small,
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
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                userDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body.copyWith(
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
              const Divider(height: 1, color: AppColors.border),
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
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        branding.departmentName,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.small.copyWith(
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
                            color: AppColors.textSecondary,
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

class _DrawerMenuItemState extends State<_DrawerMenuItem>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 140),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handlePointerDown() {
    _pressController.forward();
  }

  void _handlePointerUp() {
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final borderColor = selected
        ? AppColors.primary.withValues(alpha: 0.30)
        : (_hovered
              ? AppColors.secondary.withValues(alpha: 0.20)
              : Colors.transparent);
    final tileBg = selected
        ? AppColors.primary.withValues(alpha: 0.10)
        : (_hovered
              ? AppColors.secondary.withValues(alpha: 0.06)
              : Colors.transparent);
    final foreground = selected ? AppColors.primary : AppColors.textSecondary;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.compact ? 2 : 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Listener(
          onPointerDown: (_) => _handlePointerDown(),
          onPointerUp: (_) => _handlePointerUp(),
          onPointerCancel: (_) => _handlePointerUp(),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  _handlePointerUp();
                  widget.onTap();
                },
                splashColor: AppColors.primary.withValues(alpha: 0.15),
                highlightColor: AppColors.primary.withValues(alpha: 0.08),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  height: widget.compact ? 50 : 54,
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 12 : 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: borderColor,
                      width: 1.5,
                    ),
                    boxShadow: _hovered || selected
                        ? [
                            BoxShadow(
                              color: selected
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : AppColors.secondary.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: selected ? 4 : 3,
                        height: 28,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      SizedBox(width: selected ? 9 : 12),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: widget.compact ? 18 : 20,
                          color: foreground,
                        ),
                        child: Icon(
                          widget.icon,
                          size: widget.compact ? 20 : 22,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: selected
                                ? FontWeight.w700
                                : (_hovered ? FontWeight.w600 : FontWeight.w500),
                            fontSize: widget.compact ? 13.8 : 14.4,
                            color: foreground,
                          ),
                        ),
                      ),
                      if (widget.showIndicator)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 10),
                          decoration: BoxDecoration(
                            color: colorScheme.error,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.error.withValues(
                                  alpha: 0.40,
                                ),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
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
              style: AppTextStyles.small.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
