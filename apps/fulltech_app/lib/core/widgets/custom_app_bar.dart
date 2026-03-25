import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/app_role.dart';
import '../auth/auth_provider.dart';
import '../theme/role_branding.dart';
import '../routing/app_navigator.dart';

class CustomAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final Widget? titleWidget;
  final VoidCallback? onMenuPressed;
  final List<Widget>? actions;
  final Widget? trailing;
  final bool showLogo;
  final bool darkerTone;

  const CustomAppBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.onMenuPressed,
    this.actions,
    this.trailing,
    this.showLogo = true,
    this.darkerTone = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scaffold = Scaffold.maybeOf(context);
    final backButton = AppNavigator.maybeBackButton(context);
    final hasDrawer = scaffold?.hasDrawer ?? false;
    final role = ref.watch(authStateProvider).user?.appRole;
    final branding = resolveRoleBranding(role ?? AppRole.unknown);
    final gradient = darkerTone
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                Colors.black.withValues(alpha: 0.24),
                branding.appBarStartDark,
              ),
              Color.alphaBlend(
                Colors.black.withValues(alpha: 0.18),
                branding.appBarEndDark,
              ),
            ],
          )
        : branding.appBarDarkGradient;
    final shadowColor = darkerTone
        ? Colors.black.withValues(alpha: 0.24)
        : Colors.black.withValues(alpha: 0.18);

    final resolvedActions = <Widget>[
      ...?actions,
      if (trailing != null) trailing!,
    ];

    return AppBar(
      toolbarHeight: 70,
      leading:
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
              : null),
      title:
          titleWidget ??
          Row(
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
                    const SizedBox(height: 2),
                    Text(
                      branding.departmentName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.78),
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      actions: resolvedActions.isEmpty ? null : resolvedActions,
      elevation: 0,
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(70);
}
