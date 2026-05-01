import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../auth/app_role.dart';
import '../auth/auth_provider.dart';
import '../location/location_tracker_provider.dart';
import '../models/user_model.dart';
import '../routing/routes.dart';
import '../theme/role_branding.dart';
import '../utils/date_time_formatters.dart';
import 'app_navigation.dart';
import 'user_avatar.dart';

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

class ResponsiveShell extends ConsumerStatefulWidget {
  const ResponsiveShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends ConsumerState<ResponsiveShell> {
  // Default: collapsed. User can expand; collapses automatically on navigation.
  bool _collapsed = true;
  String _lastKnownLocation = '';

  void _toggleSidebar() {
    if (!mounted) return;
    setState(() => _collapsed = !_collapsed);
  }

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

    // Auto-collapse when the user navigates to a different screen.
    if (_lastKnownLocation.isNotEmpty && _lastKnownLocation != location) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_collapsed) setState(() => _collapsed = true);
      });
    }
    _lastKnownLocation = location;

    // Force sidebar collapsed and locked on CRM WhatsApp screen.
    final isCrmScreen = location == Routes.whatsappCrm;
    final effectiveCollapsed = isCrmScreen ? true : _collapsed;
    final effectiveToggle = isCrmScreen ? () {} : _toggleSidebar;

    return Material(
      color: Colors.transparent,
      child: Row(
        children: [
          DesktopSidebar(
            collapsed: effectiveCollapsed,
            currentUser: user,
            sections: sections,
            currentLocation: location,
            onToggleSidebar: effectiveToggle,
            onNavigate: (route) => context.go(route),
          ),
          Expanded(
            child: Column(
              children: [
                if (showShellAppBar)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: DesktopShellAppBar(
                      collapsed: effectiveCollapsed,
                      title: title,
                      currentUser: user,
                      onToggleSidebar: effectiveToggle,
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

    return StreamBuilder<DateTime>(
      stream: Stream<DateTime>.periodic(
        const Duration(seconds: 15),
        (_) => DateTime.now(),
      ),
      initialData: now,
      builder: (context, snapshot) {
        final dateTime = snapshot.data ?? DateTime.now();
        final timeText = formatRdTime(dateTime);

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
    final branding = resolveRoleBranding(
      currentUser?.appRole ?? AppRole.unknown,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 14 : 18),
      decoration: BoxDecoration(
        gradient: branding.appBarDarkGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final showRangeBadge = !collapsed && availableWidth >= 1120;
          final showUserMeta = !collapsed && availableWidth >= 860;

          return Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
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
                      'Espacio de trabajo FULLTECH',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      branding.departmentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (showRangeBadge) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle, size: 8, color: Colors.white),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '$title · $today',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: showUserMeta ? 260 : 56),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: collapsed ? 8 : 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(
                        radius: 15,
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        imageUrl: photoUrl,
                        child: Text(
                          userInitials(currentUser),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (showUserMeta) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                (currentUser?.nombreCompleto ?? 'Usuario')
                                    .toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                branding.departmentName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.74),
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
            ],
          );
        },
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
    final width = collapsed ? 80.0 : 256.0;
    final branding = resolveRoleBranding(
      currentUser?.appRole ?? AppRole.unknown,
    );
    const onBase = Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        gradient: branding.drawerGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            // ── Brand / toggle header ────────────────────────────────
            GestureDetector(
              onTap: onToggleSidebar,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 64,
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 14),
                child: collapsed
                    ? Center(
                        child: Tooltip(
                          message: 'Expandir menú',
                          preferBelow: false,
                          verticalOffset: 28,
                          textStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: onBase.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: onBase.withValues(alpha: 0.14),
                              ),
                            ),
                            child: const Icon(
                              Icons.business_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(
                              Icons.business_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'FULLTECH',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                    color: onBase,
                                  ),
                                ),
                                Text(
                                  branding.departmentName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: onBase.withValues(alpha: 0.68),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.keyboard_double_arrow_left_rounded,
                            size: 16,
                            color: onBase.withValues(alpha: 0.55),
                          ),
                        ],
                      ),
              ),
            ),

            // ── Top separator ────────────────────────────────────────
            Divider(height: 1, color: onBase.withValues(alpha: 0.08)),

            // ── Navigation items ─────────────────────────────────────
            Expanded(
              child: ListView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                children: [
                  for (final section in sections) ...[
                    // Section label (expanded only)
                    if (!collapsed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                section.title.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: onBase.withValues(alpha: 0.50),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.9,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        child: Divider(
                          height: 1,
                          color: onBase.withValues(alpha: 0.08),
                        ),
                      ),

                    // Items
                    for (final item in section.items)
                      _DesktopSidebarItem(
                        collapsed: collapsed,
                        item: item,
                        selected: isNavigationRouteActive(
                          currentLocation,
                          item.route,
                        ),
                        onTap: () => onNavigate(item.route),
                      ),
                  ],
                ],
              ),
            ),

            // ── Bottom separator ────────────────────────────────────
            Divider(height: 1, color: onBase.withValues(alpha: 0.08)),

            // ── User / logout footer ─────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                collapsed ? 8 : 10,
                8,
                collapsed ? 8 : 10,
                12,
              ),
              child: Column(
                children: [
                  // Profile
                  _SidebarFooterButton(
                    collapsed: collapsed,
                    tooltip: 'Mi perfil',
                    icon: Icons.person_outline_rounded,
                    label: currentUser?.nombreCompleto ?? 'Perfil',
                    sublabel: branding.departmentName,
                    useAvatar: true,
                    avatarInitials: userInitials(currentUser),
                    onTap: () => context.push(Routes.profile),
                  ),
                  const SizedBox(height: 4),
                  // Logout
                  _SidebarFooterButton(
                    collapsed: collapsed,
                    tooltip: 'Cerrar sesión',
                    icon: Icons.logout_rounded,
                    label: 'Cerrar sesión',
                    isDestructive: true,
                    onTap: () async {
                      await ref.read(authStateProvider.notifier).logout();
                    },
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

// ── Footer action button ──────────────────────────────────────────────────────

class _SidebarFooterButton extends StatefulWidget {
  const _SidebarFooterButton({
    required this.collapsed,
    required this.tooltip,
    required this.icon,
    required this.label,
    this.sublabel,
    this.useAvatar = false,
    this.avatarInitials = '',
    this.isDestructive = false,
    required this.onTap,
  });

  final bool collapsed;
  final String tooltip;
  final IconData icon;
  final String label;
  final String? sublabel;
  final bool useAvatar;
  final String avatarInitials;
  final bool isDestructive;
  final VoidCallback onTap;

  @override
  State<_SidebarFooterButton> createState() => _SidebarFooterButtonState();
}

class _SidebarFooterButtonState extends State<_SidebarFooterButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onBase = Colors.white;
    final bg = _hovered
        ? Colors.white.withValues(alpha: widget.isDestructive ? 0.12 : 0.10)
        : Colors.white.withValues(alpha: 0.06);
    final fgColor = widget.isDestructive ? Colors.red.shade200 : onBase;

    Widget content = Container(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 0 : 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: widget.collapsed
          ? Center(child: Icon(widget.icon, size: 18, color: fgColor))
          : Row(
              children: [
                widget.useAvatar
                    ? CircleAvatar(
                        radius: 13,
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        child: Text(
                          widget.avatarInitials,
                          style: TextStyle(
                            color: onBase,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      )
                    : Icon(widget.icon, size: 17, color: fgColor),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: fgColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      if (widget.sublabel != null)
                        Text(
                          widget.sublabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: onBase.withValues(alpha: 0.50),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );

    if (widget.collapsed) {
      content = Tooltip(
        message: widget.tooltip,
        preferBelow: false,
        verticalOffset: 28,
        textStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: content,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(onTap: widget.onTap, child: content),
    );
  }
}

class _DesktopSidebarItem extends StatefulWidget {
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
  State<_DesktopSidebarItem> createState() => _DesktopSidebarItemState();
}

class _DesktopSidebarItemState extends State<_DesktopSidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onBase = Colors.white;
    final selected = widget.selected;
    final collapsed = widget.collapsed;

    Widget content;
    if (collapsed) {
      // ─────────────────────────────────────────────────────────────
      // COLLAPSED: premium icon pill
      // - Selected:  bright white icon, frosted bg, glow shadow
      // - Hovered:   dim glow + slight scale
      // - Default:   muted icon, transparent bg
      // ─────────────────────────────────────────────────────────────
      final iconOpacity = selected ? 1.0 : (_hovered ? 0.92 : 0.60);
      final containerBg = selected
          ? Colors.white.withValues(alpha: 0.18)
          : _hovered
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.transparent;

      content = SizedBox(
        height: 50,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: containerBg,
              borderRadius: BorderRadius.circular(15),
              border: selected
                  ? Border.all(color: onBase.withValues(alpha: 0.28), width: 1)
                  : _hovered
                  ? Border.all(color: onBase.withValues(alpha: 0.10), width: 1)
                  : null,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.10),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedScale(
                  scale: selected ? 1.10 : (_hovered ? 1.05 : 1.0),
                  duration: const Duration(milliseconds: 180),
                  child: AnimatedOpacity(
                    opacity: iconOpacity,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(widget.item.icon, size: 22, color: onBase),
                  ),
                ),
                if (widget.item.showIndicator)
                  Positioned(
                    right: 7,
                    top: 7,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.error.withValues(
                              alpha: 0.50,
                            ),
                            blurRadius: 4,
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
    } else {
      // ─────────────────────────────────────────────────────────────
      // EXPANDED: icon pill + label, premium look
      // ─────────────────────────────────────────────────────────────
      final iconOpacityExpanded = selected ? 1.0 : (_hovered ? 0.92 : 0.68);
      final labelColor = Colors.white;
      final expandedBg = selected
          ? Colors.white.withValues(alpha: 0.14)
          : _hovered
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.white.withValues(alpha: 0.04);
      final iconBoxBg = selected
          ? Colors.white.withValues(alpha: 0.22)
          : _hovered
              ? Colors.white.withValues(alpha: 0.13)
              : Colors.white.withValues(alpha: 0.08);

      content = SizedBox(
        height: 44,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: expandedBg,
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? Border.all(
                    color: Colors.black.withValues(alpha: 0.13),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            children: [
              // Left accent bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: selected ? 3.5 : 0,
                height: 20,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.40),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
              SizedBox(width: selected ? 8 : 11),
              // Icon in pill container
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBoxBg,
                  borderRadius: BorderRadius.circular(10),
                  border: selected
                      ? Border.all(
                          color: Colors.black.withValues(alpha: 0.18),
                          width: 1,
                        )
                      : null,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedOpacity(
                      opacity: iconOpacityExpanded,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        widget.item.icon,
                        size: 18,
                        color: Colors.black,
                      ),
                    ),
                    if (widget.item.showIndicator)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.error.withValues(
                                  alpha: 0.50,
                                ),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 11),
              // Label
              Expanded(
                child: Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: labelColor,
                    fontSize: 15.0,
                    letterSpacing: selected ? 0.18 : 0.02,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 2.5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget wrapped = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(onTap: widget.onTap, child: content),
    );

    // Collapsed: styled tooltip to the right
    if (collapsed) {
      return Tooltip(
        message: widget.item.title,
        preferBelow: false,
        verticalOffset: 30,
        textStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.2,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: wrapped,
      );
    }
    return wrapped;
  }
}
