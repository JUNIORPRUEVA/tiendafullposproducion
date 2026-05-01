import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/amonestaciones/application/warnings_controller.dart';
import '../auth/app_role.dart';
import '../auth/auth_provider.dart';
import '../routing/routes.dart';
import '../theme/role_branding.dart';
import '../routing/app_navigator.dart';
import 'user_avatar.dart';

class CustomAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final Widget? titleWidget;
  final VoidCallback? onMenuPressed;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget? trailing;
  final PreferredSizeWidget? bottom;
  final bool showLogo;
  final bool showDepartmentLabel;
  final bool darkerTone;
  final bool highContrast;
  final double? toolbarHeight;
  final bool centerTitle;
  final double? titleSpacing;
  final String? fallbackRoute;

  const CustomAppBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.onMenuPressed,
    this.leading,
    this.actions,
    this.trailing,
    this.bottom,
    this.showLogo = true,
    this.showDepartmentLabel = true,
    this.darkerTone = false,
    this.highContrast = false,
    this.toolbarHeight,
    this.centerTitle = false,
    this.titleSpacing,
    this.fallbackRoute,
  });

  double get _resolvedToolbarHeight =>
      toolbarHeight ?? ((showLogo || showDepartmentLabel) ? 70 : kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scaffold = Scaffold.maybeOf(context);
    final backButton = AppNavigator.maybeBackButton(
      context,
      fallbackRoute: fallbackRoute,
    );
    final hasDrawer = scaffold?.hasDrawer ?? false;
    final isMobileLayout = MediaQuery.sizeOf(context).width < 900;
    final role = ref.watch(authStateProvider).user?.appRole;
    final branding = resolveRoleBranding(role ?? AppRole.unknown);
    final appBarColor = branding.drawerSolidColor;
    final shadowColor = Colors.black.withValues(
      alpha: highContrast
          ? 0.28
          : darkerTone
          ? 0.24
          : 0.20,
    );
    final departmentLabelColor = Colors.white.withValues(
      alpha: highContrast ? 0.96 : 0.90,
    );

    final primaryPendingAction = _buildPrimaryPendingAction(
      context: context,
      ref: ref,
    );

    final resolvedActions = <Widget>[
      ...?actions,
      if (primaryPendingAction != null) primaryPendingAction,
      if (trailing != null)
        trailing!
      else
        _buildDefaultPrimaryAvatar(context: context, ref: ref),
    ];

    final resolvedLeading =
        leading ??
        backButton ??
        ((onMenuPressed != null || hasDrawer)
            ? IconButton(
                tooltip: 'Menú',
                onPressed:
                    onMenuPressed ??
                    () {
                      scaffold?.openDrawer();
                    },
                icon: const Icon(Icons.menu_rounded),
              )
            : null);

    final resolvedTitle = titleWidget ??
        (!(showLogo || showDepartmentLabel)
            ? Text(title, overflow: TextOverflow.ellipsis)
            : Row(
                children: [
                  if (showLogo)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      padding: const EdgeInsets.all(5),
                      child: Image.asset(
                        'assets/logoprincipal.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.business, color: Colors.white);
                        },
                      ),
                    ),
                  if (showLogo) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        if (showDepartmentLabel) const SizedBox(height: 2),
                        if (showDepartmentLabel)
                          Text(
                            branding.departmentName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: departmentLabelColor,
                              letterSpacing: 0.1,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ));

    return AppBar(
      toolbarHeight: _resolvedToolbarHeight,
      centerTitle: centerTitle,
      titleSpacing: titleSpacing,
      leading: resolvedLeading,
      title: resolvedTitle,
      actions: resolvedActions.isEmpty ? null : resolvedActions,
      bottom: bottom,
      elevation: 0,
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(
          color: isMobileLayout ? appBarColor : appBarColor,
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      backgroundColor: appBarColor,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
    );
  }

  Widget? _buildPrimaryPendingAction({
    required BuildContext context,
    required WidgetRef ref,
  }) {
    final user = ref.watch(authStateProvider).user;
    if (user == null) return null;

    // Show pending indicator on any top-level screen (mobile or desktop).
    // On mobile the screen owns a drawer; on desktop it does not — but we
    // still want the badge visible next to the profile avatar.
    final pendingCount = ref.watch(myPendingWarningsCountProvider);
    if (pendingCount <= 0) return null;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _AnimatedPendingWarningsAction(
        visible: true,
        count: pendingCount,
        onTap: () => context.push(Routes.misAmonestacionesPendientes),
      ),
    );
  }

  Widget _buildDefaultPrimaryAvatar({
    required BuildContext context,
    required WidgetRef ref,
  }) {
    final user = ref.watch(authStateProvider).user;
    if (user == null) return const SizedBox.shrink();
    final photoUrl = (user.fotoPersonalUrl ?? '').trim();

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.98, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Tooltip(
          message: 'Mi perfil',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => context.push(Routes.profile),
              child: Ink(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.94, end: 1).animate(
                          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: UserAvatar(
                    key: ValueKey(photoUrl),
                    radius: 16,
                    backgroundColor: Colors.white24,
                    imageUrl: photoUrl,
                    child: Text(
                      _getInitials(user.nombreCompleto),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
    _resolvedToolbarHeight + (bottom?.preferredSize.height ?? 0),
  );
}

String _getInitials(String name) {
  final initials = name
      .split(' ')
      .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
      .join('')
      .replaceAll(' ', '');

  if (initials.isEmpty) return 'U';
  if (initials.length >= 2) return initials.substring(0, 2);
  return initials.padRight(2, initials[0]);
}

class _PendingWarningsAction extends StatelessWidget {
  const _PendingWarningsAction({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shownCount = count > 99 ? '99+' : '$count';

    return Tooltip(
      message: 'Tienes $count pendientes de firma',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.20),
                ),
              ),
              child: const Icon(
                Icons.notification_important_outlined,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5A5F),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: Center(
                child: Text(
                  shownCount,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedPendingWarningsAction extends StatelessWidget {
  const _AnimatedPendingWarningsAction({
    required this.visible,
    required this.count,
    required this.onTap,
  });

  final bool visible;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        );
      },
      child: visible
          ? _PendingWarningsAction(
              key: const ValueKey('pending-visible'),
              count: count,
              onTap: onTap,
            )
          : const SizedBox(
              key: ValueKey('pending-hidden'),
              width: 0,
              height: 0,
            ),
    );
  }
}
