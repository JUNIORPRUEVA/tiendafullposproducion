import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../auth/auth_provider.dart';
import '../location/location_tracker_provider.dart';
import '../models/user_model.dart';
import '../routing/routes.dart';
import 'app_navigation.dart';

class ResponsiveShell extends ConsumerStatefulWidget {
  const ResponsiveShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends ConsumerState<ResponsiveShell> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(locationTrackingBootstrapProvider);

    final media = MediaQuery.sizeOf(context);
    if (media.width < kDesktopShellBreakpoint) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final user = ref.watch(authStateProvider).user;
    final sections = buildAppNavigationSections(ref, user);
    final location = safeCurrentLocation(context);
    final title = resolveNavigationTitle(location, sections);
    final showShellAppBar = desktopShellShouldShowOwnAppBar(location);

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              Color.alphaBlend(
                theme.colorScheme.primary.withValues(alpha: 0.05),
                theme.colorScheme.surface,
              ),
              Color.alphaBlend(
                theme.colorScheme.secondary.withValues(alpha: 0.07),
                theme.colorScheme.surface,
              ),
            ],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              DesktopSidebar(
                collapsed: _collapsed,
                currentUser: user,
                sections: sections,
                currentLocation: location,
                onToggleSidebar: () {
                  setState(() => _collapsed = !_collapsed);
                },
                onNavigate: (route) => context.go(route),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(0, showShellAppBar ? 14 : 10, 16, 16),
                  child: Column(
                    children: [
                      if (showShellAppBar) ...[
                        DesktopShellAppBar(
                          collapsed: _collapsed,
                          title: title,
                          currentUser: user,
                          onToggleSidebar: () {
                            setState(() => _collapsed = !_collapsed);
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Material(
                            color: theme.colorScheme.surface,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 28,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: widget.child,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DesktopShellAppBar extends StatelessWidget {
  const DesktopShellAppBar({
    super.key,
    required this.collapsed,
    required this.title,
    required this.currentUser,
    required this.onToggleSidebar,
  });

  final bool collapsed;
  final String title;
  final UserModel? currentUser;
  final VoidCallback onToggleSidebar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateFormat('EEEE, d MMMM', 'es').format(DateTime.now());
    final photoUrl = (currentUser?.fotoPersonalUrl ?? '').trim();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 14 : 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              tooltip: collapsed ? 'Expandir menú' : 'Colapsar menú',
              onPressed: onToggleSidebar,
              icon: AnimatedRotation(
                turns: collapsed ? 0.5 : 0,
                duration: const Duration(milliseconds: 240),
                child: const Icon(Icons.menu_open_rounded, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FULLTECH Workspace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  today,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (!collapsed) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
          ],
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 8 : 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.14),
                  backgroundImage: photoUrl.isEmpty ? null : NetworkImage(photoUrl),
                  child: photoUrl.isEmpty
                      ? Text(
                          userInitials(currentUser),
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        )
                      : null,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        (currentUser?.nombreCompleto ?? 'Usuario').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Sesión activa',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({
    super.key,
    required this.collapsed,
    required this.currentUser,
    required this.sections,
    required this.currentLocation,
    required this.onToggleSidebar,
    required this.onNavigate,
  });

  final bool collapsed;
  final UserModel? currentUser;
  final List<AppNavigationSection> sections;
  final String currentLocation;
  final VoidCallback onToggleSidebar;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final width = collapsed ? 84.0 : 272.0;
    final gradientTop = Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: 0.10),
      theme.colorScheme.surface,
    );
    final gradientBottom = Color.alphaBlend(
      theme.colorScheme.secondary.withValues(alpha: 0.12),
      theme.colorScheme.surface,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: width,
      margin: const EdgeInsets.fromLTRB(16, 14, 14, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientTop, theme.colorScheme.surface, gradientBottom],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? 12 : 16, 14, collapsed ? 12 : 16, 10),
              child: Tooltip(
                message: collapsed ? 'Expandir menú' : 'Encoger menú',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: onToggleSidebar,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: collapsed
                          ? Container(
                              key: const ValueKey('brand-collapsed'),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(alpha: 0.76),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor:
                                        theme.colorScheme.primary.withValues(alpha: 0.14),
                                    child: Icon(
                                      Icons.business_rounded,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Icon(
                                    Icons.keyboard_double_arrow_left_rounded,
                                    size: 16,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            )
                          : Container(
                              key: const ValueKey('brand-expanded'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(alpha: 0.76),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: theme.colorScheme.primary,
                                    child: const Icon(
                                      Icons.business_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'FULLTECH',
                                          style: theme.textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                        Text(
                                          'Toca para encoger menú',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard_double_arrow_left_rounded,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(collapsed ? 10 : 12, 4, collapsed ? 10 : 12, 8),
                children: [
                  for (final section in sections) ...[
                    if (!collapsed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                        child: Text(
                          section.title,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    for (final item in section.items)
                      _DesktopSidebarItem(
                        collapsed: collapsed,
                        item: item,
                        selected: isNavigationRouteActive(currentLocation, item.route),
                        onTap: () => onNavigate(item.route),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? 10 : 12, 8, collapsed ? 10 : 12, 12),
              child: Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => context.push(Routes.profile),
                      child: Ink(
                        padding: EdgeInsets.symmetric(
                          horizontal: collapsed ? 0 : 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: collapsed
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  theme.colorScheme.primary.withValues(alpha: 0.14),
                              child: Text(
                                userInitials(currentUser),
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (!collapsed) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (currentUser?.nombreCompleto ?? 'Perfil').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      'Ver perfil',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (collapsed)
                    IconButton.filledTonal(
                      tooltip: 'Cerrar sesión',
                      onPressed: () async {
                        await ref.read(authStateProvider.notifier).logout();
                        if (context.mounted) context.go(Routes.login);
                      },
                      icon: const Icon(Icons.logout_rounded),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await ref.read(authStateProvider.notifier).logout();
                        if (context.mounted) context.go(Routes.login);
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Cerrar sesión'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
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

class _DesktopSidebarItem extends StatelessWidget {
  const _DesktopSidebarItem({
    required this.collapsed,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final bool collapsed;
  final AppNavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = selected
        ? Color.alphaBlend(
            theme.colorScheme.primary.withValues(alpha: 0.12),
            theme.colorScheme.surface,
          )
        : Colors.transparent;
    final iconColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    final child = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      constraints: BoxConstraints(minHeight: collapsed ? 52 : 0),
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.22)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        mainAxisAlignment:
            collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(item.icon, size: 22, color: iconColor),
              if (item.showIndicator)
                Positioned(
                  right: -2,
                  top: -1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          if (!collapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  color: selected ? theme.colorScheme.primary : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: collapsed ? item.title : '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}
