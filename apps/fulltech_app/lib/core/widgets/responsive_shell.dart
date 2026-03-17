import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../ai_assistant/application/ai_assistant_controller.dart';
import '../ai_assistant/presentation/ai_chat_context_resolver.dart';
import '../ai_assistant/presentation/widgets/ai_assistant_dock_button.dart';
import '../auth/auth_provider.dart';
import '../location/location_tracker_provider.dart';
import '../models/user_model.dart';
import '../routing/routes.dart';
import 'app_navigation.dart';

Color _desktopSidebarBaseColor(ThemeData theme) {
  final cs = theme.colorScheme;
  final deepBlue = Color.alphaBlend(
    cs.primary.withValues(alpha: 0.86),
    cs.tertiary,
  );
  return Color.alphaBlend(cs.secondary.withValues(alpha: 0.08), deepBlue);
}

Color _desktopSidebarHoverColor(ThemeData theme) {
  final base = _desktopSidebarBaseColor(theme);
  return Color.alphaBlend(
    theme.colorScheme.primary.withValues(alpha: 0.22),
    base,
  );
}

BoxDecoration _desktopSurfaceDecoration(ThemeData theme) {
  return BoxDecoration(
    color: theme.colorScheme.surface.withValues(alpha: 0.92),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.40),
    ),
    boxShadow: [
      BoxShadow(
        color: theme.colorScheme.shadow.withValues(alpha: 0.08),
        blurRadius: 30,
        offset: const Offset(0, 14),
      ),
    ],
  );
}

bool _shouldShowDesktopAiAssistant(String location) {
  final normalized = location.trim();
  final uri = Uri.tryParse(normalized) ?? Uri(path: normalized);
  final path = uri.path.trim().toLowerCase();

  return !path.startsWith(Routes.operaciones);
}

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
            child: Column(
              children: [
                if (showShellAppBar)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: DesktopShellAppBar(
                      collapsed: _collapsed,
                      title: title,
                      currentUser: user,
                      onToggleSidebar: () {
                        setState(() => _collapsed = !_collapsed);
                      },
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      showShellAppBar ? 0 : 12,
                      16,
                      12,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: DecoratedBox(
                        decoration: _desktopSurfaceDecoration(theme),
                        child: Theme(
                          data: theme.copyWith(
                            scaffoldBackgroundColor: Colors.transparent,
                          ),
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                ),
                const DesktopShellFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DesktopShellFooter extends ConsumerWidget {
  const DesktopShellFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final location = safeCurrentLocation(context);
    final showAiAssistant = _shouldShowDesktopAiAssistant(location);

    final open = ref.watch(desktopAiAssistantPanelOpenProvider);

    return StreamBuilder<DateTime>(
      stream: Stream<DateTime>.periodic(
        const Duration(seconds: 15),
        (_) => DateTime.now(),
      ),
      initialData: now,
      builder: (context, snapshot) {
        final dateTime = snapshot.data ?? DateTime.now();
        final timeText = DateFormat('HH:mm').format(dateTime);

        return Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.88),
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.60),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '© 2026 FULLTECH, SRL — Todos los derechos reservados',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              Text(
                timeText,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: 0.3,
                ),
              ),
              if (showAiAssistant) ...[
                const SizedBox(width: 14),
                AiAssistantDockButton(
                  compact: true,
                  isActive: open,
                  onPressed: () {
                    final ctx = buildAiChatContextFromLocation(location);
                    ref
                        .read(aiAssistantControllerProvider.notifier)
                        .setContext(ctx);
                    ref
                        .read(desktopAiAssistantPanelOpenProvider.notifier)
                        .state = !open;
                  },
                ),
              ],
            ],
          ),
        );
      },
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
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: theme.colorScheme.primary),
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
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.14,
                  ),
                  backgroundImage: photoUrl.isEmpty
                      ? null
                      : NetworkImage(photoUrl),
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
    final width = collapsed ? 84.0 : 280.0;
    final base = _desktopSidebarBaseColor(theme);
    final onBase = theme.colorScheme.onPrimary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: base,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(6, 0),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                collapsed ? 12 : 16,
                14,
                collapsed ? 12 : 16,
                10,
              ),
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
                                color: onBase.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: onBase.withValues(alpha: 0.10),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: theme.colorScheme.primary
                                        .withValues(alpha: 0.20),
                                    child: Icon(
                                      Icons.business_rounded,
                                      color: onBase,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Icon(
                                    Icons.keyboard_double_arrow_left_rounded,
                                    size: 16,
                                    color: onBase.withValues(alpha: 0.80),
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
                                color: onBase.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: onBase.withValues(alpha: 0.10),
                                ),
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final isNarrow = constraints.maxWidth < 190;

                                  return Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: theme
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.96),
                                        child: const Icon(
                                          Icons.business_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'FULLTECH',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w900,
                                                    letterSpacing: 0.8,
                                                    color: onBase,
                                                  ),
                                            ),
                                            if (!isNarrow)
                                              Text(
                                                'Toca para encoger menú',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: onBase.withValues(
                                                        alpha: 0.78,
                                                      ),
                                                    ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (!isNarrow)
                                        Icon(
                                          Icons
                                              .keyboard_double_arrow_left_rounded,
                                          color: onBase.withValues(alpha: 0.80),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  collapsed ? 10 : 12,
                  4,
                  collapsed ? 10 : 12,
                  8,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final itemCount = sections.fold<int>(
                      0,
                      (sum, section) => sum + section.items.length,
                    );
                    final titleCount = collapsed ? 0 : sections.length;
                    final titleHeight = collapsed ? 0.0 : 18.0;
                    final reservedForTitles = titleCount * titleHeight;
                    final availableForItems =
                        (constraints.maxHeight - reservedForTitles).clamp(
                          0.0,
                          constraints.maxHeight,
                        );
                    final rawItemHeight = itemCount == 0
                        ? 0.0
                        : (availableForItems / itemCount);
                    final itemHeight = rawItemHeight > 64.0
                        ? 64.0
                        : rawItemHeight;

                    final children = <Widget>[];
                    for (final section in sections) {
                      if (!collapsed) {
                        children.add(
                          SizedBox(
                            height: titleHeight,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  section.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: onBase.withValues(alpha: 0.72),
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.7,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      for (final item in section.items) {
                        children.add(
                          SizedBox(
                            height: itemHeight,
                            child: _DesktopSidebarItem(
                              collapsed: collapsed,
                              item: item,
                              height: itemHeight,
                              selected: isNavigationRouteActive(
                                currentLocation,
                                item.route,
                              ),
                              onTap: () => onNavigate(item.route),
                            ),
                          ),
                        );
                      }
                    }

                    return Column(children: children);
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                collapsed ? 10 : 12,
                8,
                collapsed ? 10 : 12,
                12,
              ),
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
                          color: onBase.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: onBase.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: collapsed
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: onBase.withValues(alpha: 0.12),
                              child: Text(
                                userInitials(currentUser),
                                style: TextStyle(
                                  color: onBase,
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
                                      (currentUser?.nombreCompleto ?? 'Perfil')
                                          .toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: onBase,
                                          ),
                                    ),
                                    Text(
                                      'Ver perfil',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: onBase.withValues(
                                              alpha: 0.74,
                                            ),
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
    );
  }
}

class _DesktopSidebarItem extends StatefulWidget {
  const _DesktopSidebarItem({
    required this.collapsed,
    required this.item,
    required this.height,
    required this.selected,
    required this.onTap,
  });

  final bool collapsed;
  final AppNavigationItem item;
  final double height;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DesktopSidebarItem> createState() => _DesktopSidebarItemState();
}

class _DesktopSidebarItemState extends State<_DesktopSidebarItem> {
  // Avoid manual hover state with setState on desktop.
  // MouseRegion hover callbacks can trigger MouseTracker asserts on Windows.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = _desktopSidebarBaseColor(theme);
    final onBase = theme.colorScheme.onPrimary;
    final selected = widget.selected;
    final background = selected
        ? Color.alphaBlend(
            theme.colorScheme.primary.withValues(alpha: 0.34),
            base,
          )
        : Colors.transparent;
    final iconColor = selected ? onBase : onBase.withValues(alpha: 0.88);

    final hoverBg = selected
      ? _desktopSidebarHoverColor(theme)
      : onBase.withValues(alpha: 0.08);

    final effectiveBg = background;

    final height = widget.height;
    final computedIconSize = (height * 0.44).clamp(12.0, 22.0);
    final maxIconSize = (height - 6).clamp(10.0, 22.0);
    final iconSize = computedIconSize > maxIconSize
        ? maxIconSize
        : computedIconSize;
    final horizontalPadding = widget.collapsed ? 0.0 : 10.0;
    final fontSize = (height * 0.33).clamp(10.0, 14.0);

    final arrowSize = (height * 0.30).clamp(12.0, 18.0);
    final arrowColor = selected ? onBase : onBase.withValues(alpha: 0.70);

    final child = Container(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? onBase.withValues(alpha: 0.16)
              : onBase.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisAlignment: widget.collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(widget.item.icon, size: iconSize, color: iconColor),
              if (widget.item.showIndicator)
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
          if (!widget.collapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  color: iconColor,
                  fontSize: fontSize,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: arrowSize,
              color: arrowColor,
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: widget.collapsed ? widget.item.title : '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
          hoverColor: hoverBg,
          child: Center(child: child),
        ),
      ),
    );
  }
}
