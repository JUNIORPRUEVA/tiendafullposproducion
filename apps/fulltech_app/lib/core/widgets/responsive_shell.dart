import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../features/amonestaciones/application/warnings_controller.dart';
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

class DesktopShellAppBar extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = DateFormat('EEEE, d MMMM', 'es').format(DateTime.now());
    final photoUrl = (currentUser?.fotoPersonalUrl ?? '').trim();
    final branding = resolveRoleBranding(
      currentUser?.appRole ?? AppRole.unknown,
    );
    final pendingWarningsCount = ref.watch(myPendingWarningsCountProvider);
    final showPendingWarningsIcon = pendingWarningsCount > 0;

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
                constraints: BoxConstraints(
                  maxWidth: showUserMeta
                      ? 260
                      : (showPendingWarningsIcon ? 100 : 56),
                ),
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
                      if (showPendingWarningsIcon) ...[
                        _PendingWarningsIconButton(
                          count: pendingWarningsCount,
                          onTap: () => context.go(Routes.misAmonestacionesPendientes),
                        ),
                        const SizedBox(width: 8),
                      ],
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

class _PendingWarningsIconButton extends StatelessWidget {
  const _PendingWarningsIconButton({
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
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
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
              decoration: BoxDecoration(
                color: const Color(0xFFFF5A5F),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
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

class _SidebarMenuGroup {
  const _SidebarMenuGroup({
    required this.key,
    required this.title,
    required this.icon,
    required this.items,
  });

  final String key;
  final String title;
  final IconData icon;
  final List<AppNavigationItem> items;
}

List<_SidebarMenuGroup> _buildDesktopSidebarGroups(
  List<AppNavigationSection> sections,
) {
  final allItems = <AppNavigationItem>[
    for (final section in sections) ...section.items,
  ];
  final routeToItem = {
    for (final item in allItems) item.route: item,
  };

  List<AppNavigationItem> pick(List<String> routes) {
    return [
      for (final route in routes)
        if (routeToItem.containsKey(route)) routeToItem[route]!,
    ];
  }

  final groups = <_SidebarMenuGroup>[
    _SidebarMenuGroup(
      key: 'principal',
      title: 'Principal',
      icon: Icons.dashboard_outlined,
      items: pick([
        Routes.serviceOrders,
        Routes.clientes,
        Routes.cotizaciones,
        Routes.catalogo,
        Routes.ventas,
      ]),
    ),
    _SidebarMenuGroup(
      key: 'administracion',
      title: 'Administración',
      icon: Icons.admin_panel_settings_outlined,
      items: pick([
        Routes.ponche,
        Routes.nomina,
        Routes.serviceOrderCommissions,
        Routes.misPagos,
        Routes.users,
        Routes.amonestaciones,
        Routes.administracion,
      ]),
    ),
    _SidebarMenuGroup(
      key: 'contabilidad',
      title: 'Contabilidad',
      icon: Icons.account_balance_outlined,
      items: pick([
        Routes.contabilidad,
        Routes.documentFlows,
      ]),
    ),
    _SidebarMenuGroup(
      key: 'comunicacion',
      title: 'Comunicación',
      icon: Icons.chat_bubble_outline_rounded,
      items: pick([
        Routes.whatsapp,
        Routes.whatsappCrm,
        Routes.mediaGallery,
      ]),
    ),
    _SidebarMenuGroup(
      key: 'sistema',
      title: 'Sistema',
      icon: Icons.settings_suggest_outlined,
      items: pick([
        Routes.ai,
        Routes.manualInterno,
        Routes.configuracion,
      ]),
    ),
  ];

  final knownRoutes = <String>{
    for (final group in groups)
      for (final item in group.items) item.route,
  };
  final extras = allItems
      .where((item) => !knownRoutes.contains(item.route))
      .toList(growable: false);
  if (extras.isNotEmpty) {
    final sistemaIndex = groups.indexWhere((group) => group.key == 'sistema');
    if (sistemaIndex >= 0) {
      final sistema = groups[sistemaIndex];
      groups[sistemaIndex] = _SidebarMenuGroup(
        key: sistema.key,
        title: sistema.title,
        icon: sistema.icon,
        items: [...sistema.items, ...extras],
      );
    }
  }

  return groups.where((group) => group.items.isNotEmpty).toList(growable: false);
}

String? _resolveActiveGroupKey(
  List<_SidebarMenuGroup> groups,
  String currentLocation,
) {
  for (final group in groups) {
    for (final item in group.items) {
      if (isNavigationRouteActive(currentLocation, item.route)) {
        return group.key;
      }
    }
  }
  return groups.isEmpty ? null : groups.first.key;
}

bool _groupContainsActiveRoute(
  _SidebarMenuGroup group,
  String currentLocation,
) {
  for (final item in group.items) {
    if (isNavigationRouteActive(currentLocation, item.route)) {
      return true;
    }
  }
  return false;
}

class DesktopSidebar extends ConsumerStatefulWidget {
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
  ConsumerState<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends ConsumerState<DesktopSidebar> {
  String? _openGroupKey;

  @override
  void initState() {
    super.initState();
    final groups = _buildDesktopSidebarGroups(widget.sections);
    _openGroupKey = _resolveActiveGroupKey(groups, widget.currentLocation);
  }

  @override
  void didUpdateWidget(covariant DesktopSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLocation == widget.currentLocation &&
        oldWidget.sections == widget.sections) {
      return;
    }
    final groups = _buildDesktopSidebarGroups(widget.sections);
    final next = _resolveActiveGroupKey(groups, widget.currentLocation);
    if (next != null && next != _openGroupKey) {
      setState(() => _openGroupKey = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = widget.collapsed ? 80.0 : 256.0;
    final branding = resolveRoleBranding(
      widget.currentUser?.appRole ?? AppRole.unknown,
    );
    const onBase = Colors.white;
    const panelTop = Color(0xFF0F172A);
    const panelBottom = Color(0xFF111C31);
    const slate400 = Color(0xFF94A3B8);
    const slate500 = Color(0xFF64748B);
    final groups = _buildDesktopSidebarGroups(widget.sections);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [panelTop, panelBottom],
        ),
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
              onTap: widget.onToggleSidebar,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 62,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.collapsed ? 0 : 14,
                ),
                child: widget.collapsed
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
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: onBase.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: onBase.withValues(alpha: 0.10),
                              ),
                            ),
                            child: const Icon(
                              Icons.business_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
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
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: onBase,
                                  ),
                                ),
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
                          Icon(
                            Icons.keyboard_double_arrow_left_rounded,
                            size: 16,
                            color: slate500,
                          ),
                        ],
                      ),
              ),
            ),

            // ── Top separator ────────────────────────────────────────
            Divider(height: 1, color: onBase.withValues(alpha: 0.07)),

            // ── Navigation items ─────────────────────────────────────
            Expanded(
              child: ListView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                children: [
                  if (widget.collapsed)
                    for (final group in groups)
                      _DesktopSidebarCollapsedGroupButton(
                        title: group.title,
                        icon: group.icon,
                        selected: _groupContainsActiveRoute(
                          group,
                          widget.currentLocation,
                        ),
                        showIndicator: group.items.any(
                          (item) => item.showIndicator,
                        ),
                        onTap: () {
                          final selectedInGroup = group.items.where(
                            (item) => isNavigationRouteActive(
                              widget.currentLocation,
                              item.route,
                            ),
                          );
                          final target = selectedInGroup.isNotEmpty
                              ? selectedInGroup.first.route
                              : group.items.first.route;
                          widget.onNavigate(target);
                        },
                      )
                  else
                    for (final group in groups) ...[
                      _DesktopSidebarGroupHeader(
                        title: group.title,
                        icon: group.icon,
                        open: _openGroupKey == group.key,
                        active: _groupContainsActiveRoute(
                          group,
                          widget.currentLocation,
                        ),
                        onTap: () {
                          final containsActive = _groupContainsActiveRoute(
                            group,
                            widget.currentLocation,
                          );
                          setState(() {
                            if (_openGroupKey == group.key) {
                              _openGroupKey = containsActive ? group.key : null;
                            } else {
                              _openGroupKey = group.key;
                            }
                          });
                        },
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: _openGroupKey == group.key
                            ? Padding(
                                padding: const EdgeInsets.only(
                                  left: 8,
                                  right: 2,
                                  top: 4,
                                  bottom: 14,
                                ),
                                child: Column(
                                  children: [
                                    for (final item in group.items)
                                      _DesktopSidebarItem(
                                        collapsed: false,
                                        isSubItem: true,
                                        item: item,
                                        selected: isNavigationRouteActive(
                                          widget.currentLocation,
                                          item.route,
                                        ),
                                        onTap: () => widget.onNavigate(item.route),
                                      ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                ],
              ),
            ),

            // ── Bottom separator ────────────────────────────────────
            Divider(height: 1, color: onBase.withValues(alpha: 0.07)),

            // ── User / logout footer ─────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                widget.collapsed ? 8 : 10,
                8,
                widget.collapsed ? 8 : 10,
                12,
              ),
              child: Column(
                children: [
                  // Profile
                  _SidebarFooterButton(
                    collapsed: widget.collapsed,
                    tooltip: 'Mi perfil',
                    icon: Icons.person_outline_rounded,
                    label: widget.currentUser?.nombreCompleto ?? 'Perfil',
                    sublabel: branding.departmentName,
                    useAvatar: true,
                    avatarInitials: userInitials(widget.currentUser),
                    onTap: () => context.push(Routes.profile),
                  ),
                  const SizedBox(height: 4),
                  // Logout
                  _SidebarFooterButton(
                    collapsed: widget.collapsed,
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

class _DesktopSidebarGroupHeader extends StatelessWidget {
  const _DesktopSidebarGroupHeader({
    required this.title,
    required this.icon,
    required this.open,
    required this.active,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool open;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const normal = Color(0xFF94A3B8);
    const activeColor = Color(0xFFFFFFFF);

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Row(
              children: [
                Icon(icon, size: 20, color: active ? activeColor : normal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? activeColor : normal,
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: open ? 0.0 : -0.25,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopSidebarCollapsedGroupButton extends StatefulWidget {
  const _DesktopSidebarCollapsedGroupButton({
    required this.title,
    required this.icon,
    required this.selected,
    required this.showIndicator,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final bool showIndicator;
  final VoidCallback onTap;

  @override
  State<_DesktopSidebarCollapsedGroupButton> createState() =>
      _DesktopSidebarCollapsedGroupButtonState();
}

class _DesktopSidebarCollapsedGroupButtonState
    extends State<_DesktopSidebarCollapsedGroupButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    const normal = Color(0xFF94A3B8);
    const activeColor = Color(0xFFFFFFFF);

    final icon = SizedBox(
      height: 48,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: widget.selected
                ? Colors.white.withValues(alpha: 0.12)
                : (_hovered
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: widget.selected ? activeColor : normal,
              ),
              if (widget.showIndicator)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: activeColor, width: 1.1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Tooltip(
      message: widget.title,
      preferBelow: false,
      verticalOffset: 30,
      textStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 12,
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
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(onTap: widget.onTap, child: icon),
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
    const slate400 = Color(0xFF94A3B8);
    final bg = _hovered
      ? Colors.white.withValues(alpha: widget.isDestructive ? 0.08 : 0.07)
      : Colors.transparent;
    final fgColor = widget.isDestructive ? Colors.red.shade200 : slate400;

    Widget content = Container(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 0 : 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
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
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
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
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                      if (widget.sublabel != null)
                        Text(
                          widget.sublabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: slate400,
                            fontFamily: 'Inter',
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
    this.isSubItem = false,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final bool collapsed;
  final bool isSubItem;
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
    const normalText = Color(0xFF94A3B8);
    final selected = widget.selected;
    final collapsed = widget.collapsed;

    Widget content;
    if (collapsed) {
      content = SizedBox(
        height: 46,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.12)
                  : (_hovered
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  widget.item.icon,
                  size: 18,
                  color: selected ? onBase : normalText,
                ),
                if (widget.item.showIndicator)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        shape: BoxShape.circle,
                        border: Border.all(color: onBase, width: 1.1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      final itemBg = selected
          ? Colors.white.withValues(alpha: 0.12)
          : (_hovered
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.transparent);

      content = SizedBox(
        height: widget.isSubItem ? 42 : 46,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: widget.isSubItem ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: itemBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                width: 3,
                height: 24,
                decoration: BoxDecoration(
                  color: selected ? theme.colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              SizedBox(width: selected ? 10 : 13),
              Icon(
                widget.item.icon,
                size: widget.isSubItem ? 17 : 19,
                color: selected ? onBase : normalText,
              ),
              SizedBox(width: widget.isSubItem ? 8 : 10),
              Expanded(
                child: Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? onBase : normalText,
                    fontSize: widget.isSubItem ? 13 : 14,
                  ),
                ),
              ),
              if (widget.item.showIndicator)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
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
