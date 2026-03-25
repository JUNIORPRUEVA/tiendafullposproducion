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

    final resolvedActions = <Widget>[
      ...?actions,
      if (trailing != null) trailing!,
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

  @override
  Size get preferredSize => Size.fromHeight(
    _resolvedToolbarHeight + (bottom?.preferredSize.height ?? 0),
  );
}
