import 'package:flutter/material.dart';

import '../operations_models.dart';
import 'operations_filters.dart';

class OperationsMetricItem {
  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color tint;

  const OperationsMetricItem({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.tint,
  });
}

class OperationsFilterChipData {
  final String label;
  final IconData icon;
  final bool highlighted;

  const OperationsFilterChipData({
    required this.label,
    required this.icon,
    this.highlighted = false,
  });
}

enum _OperationsMenuAction { checklist, rules }

class OperationsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const OperationsAppBar({
    super.key,
    required this.gradient,
    required this.canManageChecklist,
    required this.onOpenQuickCreate,
    required this.onOpenMap,
    required this.onOpenRules,
    required this.onOpenProfile,
    this.userName,
    this.photoUrl,
    this.onOpenChecklist,
  });

  final Gradient gradient;
  final bool canManageChecklist;
  final VoidCallback onOpenQuickCreate;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenRules;
  final VoidCallback onOpenProfile;
  final VoidCallback? onOpenChecklist;
  final String? userName;
  final String? photoUrl;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      titleSpacing: 4,
      toolbarHeight: preferredSize.height,
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
      ),
      leading: Builder(
        builder: (context) {
          return IconButton(
            tooltip: 'Menú',
            onPressed: Scaffold.of(context).openDrawer,
            icon: const Icon(Icons.menu_rounded),
            style: IconButton.styleFrom(
              foregroundColor: scheme.onPrimary,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
            ),
          );
        },
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Operaciones',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Nueva orden',
          onPressed: onOpenQuickCreate,
          icon: const Icon(Icons.add_task_rounded),
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            foregroundColor: scheme.onPrimary,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        const SizedBox(width: 1),
        IconButton(
          tooltip: 'Mapa clientes',
          onPressed: onOpenMap,
          icon: const Icon(Icons.map_outlined),
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            foregroundColor: scheme.onPrimary,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        PopupMenuButton<_OperationsMenuAction>(
          tooltip: 'Acciones',
          onSelected: (value) {
            switch (value) {
              case _OperationsMenuAction.checklist:
                onOpenChecklist?.call();
                break;
              case _OperationsMenuAction.rules:
                onOpenRules();
                break;
            }
          },
          itemBuilder: (context) {
            return [
              if (canManageChecklist)
                const PopupMenuItem<_OperationsMenuAction>(
                  value: _OperationsMenuAction.checklist,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.checklist_rtl_outlined),
                    title: Text('Checklist'),
                  ),
                ),
              const PopupMenuItem<_OperationsMenuAction>(
                value: _OperationsMenuAction.rules,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.rule_folder_outlined),
                  title: Text('Reglas'),
                ),
              ),
            ];
          },
          icon: const Icon(Icons.more_horiz_rounded),
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            foregroundColor: scheme.onPrimary,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 1, right: 6),
          child: _ProfileAvatar(
            userName: userName,
            photoUrl: photoUrl,
            onTap: onOpenProfile,
          ),
        ),
      ],
    );
  }
}

class SearchBarWidget extends StatelessWidget {
  const SearchBarWidget({
    super.key,
    required this.controller,
    required this.onOpenFilters,
    required this.onSubmitted,
    this.filterButtonKey,
    this.hintText = 'Buscar cliente, orden o tecnico',
  });

  final TextEditingController controller;
  final VoidCallback onOpenFilters;
  final ValueChanged<String> onSubmitted;
  final Key? filterButtonKey;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.search_rounded,
                color: scheme.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                onSubmitted: onSubmitted,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hintText,
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (controller.text.trim().isNotEmpty)
              IconButton(
                tooltip: 'Limpiar búsqueda',
                onPressed: controller.clear,
                icon: const Icon(Icons.close_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
            IconButton(
              key: filterButtonKey,
              tooltip: 'Filtros',
              onPressed: onOpenFilters,
              icon: const Icon(Icons.tune_rounded),
              style: IconButton.styleFrom(
                minimumSize: const Size(34, 34),
                foregroundColor: scheme.primary,
                backgroundColor: scheme.primary.withValues(alpha: 0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FiltersBar extends StatelessWidget {
  const FiltersBar({
    super.key,
    required this.chips,
    required this.activeCount,
    required this.onOpenFilters,
    required this.onRefresh,
    this.filterButtonKey,
  });

  final List<OperationsFilterChipData> chips;
  final int activeCount;
  final VoidCallback onOpenFilters;
  final VoidCallback onRefresh;
  final Key? filterButtonKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _CompactActionChip(
            key: filterButtonKey,
            icon: Icons.filter_alt_outlined,
            label: activeCount > 0 ? 'Filtros $activeCount' : 'Filtros',
            highlighted: activeCount > 0,
            onTap: onOpenFilters,
          ),
          const SizedBox(width: 6),
          for (final chip in chips) ...[
            _CompactActionChip(
              icon: chip.icon,
              label: chip.label,
              highlighted: chip.highlighted,
              onTap: onOpenFilters,
            ),
            const SizedBox(width: 6),
          ],
          _CompactActionChip(
            icon: Icons.refresh_rounded,
            label: 'Actualizar',
            onTap: onRefresh,
            foregroundColor: scheme.onSurface,
          ),
        ],
      ),
    );
  }
}

class MetricsRow extends StatelessWidget {
  const MetricsRow({super.key, required this.items});

  final List<OperationsMetricItem> items;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _MetricCard(item: items[index]),
            if (index < items.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = _statusBadgeTheme(status, theme.colorScheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badge.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: badge.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 12, color: badge.foreground),
          const SizedBox(width: 4),
          Text(
            badge.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: badge.foreground,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class PhaseBadge extends StatelessWidget {
  const PhaseBadge({super.key, required this.phase, this.onChangePhase});

  final String phase;
  final VoidCallback? onChangePhase;

  @override
  Widget build(BuildContext context) {
    final normalized = phase.trim().toLowerCase();
    if (phase.trim().isEmpty ||
        phase.trim() == '—' ||
        normalized == 'reserva') {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = _phaseBadgeTheme(normalized, scheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tone.icon, size: 12, color: tone.foreground),
          const SizedBox(width: 4),
          Text(
            phase,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone.foreground,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
            ),
          ),
          if (onChangePhase != null) ...[
            const SizedBox(width: 2),
            InkWell(
              onTap: onChangePhase,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.all(1.5),
                child: Icon(
                  Icons.flag_outlined,
                  size: 12,
                  color: tone.foreground,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.onView,
    required this.onChangeState,
    this.onChat,
    this.onCall,
  });

  final VoidCallback onView;
  final Future<void> Function() onChangeState;
  final VoidCallback? onChat;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onView,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(34),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            icon: const Icon(Icons.visibility_outlined, size: 15),
            label: const Text('Ver'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => onChangeState(),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(34),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            icon: const Icon(Icons.swap_horiz_rounded, size: 15),
            label: const Text('Estado'),
          ),
        ),
        if (onChat != null) ...[
          const SizedBox(width: 6),
          _ActionIconButton(
            tooltip: 'Chat',
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: onChat!,
          ),
        ],
        if (onCall != null) ...[
          const SizedBox(width: 6),
          _ActionIconButton(
            tooltip: 'Llamar',
            icon: Icons.call_outlined,
            onPressed: onCall!,
          ),
        ],
      ],
    );
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.service,
    required this.subtitle,
    required this.technicianText,
    required this.statusText,
    required this.phaseText,
    required this.onView,
    required this.onChangeState,
    this.scheduledText,
    this.createdByShort,
    this.onChangePhase,
    this.onOpenMaps,
    this.onChat,
    this.onCall,
  });

  final ServiceModel service;
  final String subtitle;
  final String technicianText;
  final String statusText;
  final String phaseText;
  final String? scheduledText;
  final String? createdByShort;
  final VoidCallback onView;
  final Future<void> Function() onChangeState;
  final VoidCallback? onChangePhase;
  final VoidCallback? onOpenMaps;
  final VoidCallback? onChat;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final customerName = service.customerName.trim().isEmpty
        ? 'Cliente'
        : service.customerName.trim();
    final address = service.customerAddress.trim();
    final priorityLabel = 'P${service.priority}';

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surface,
            scheme.surface,
            scheme.primary.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.70),
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(status: statusText),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if ((createdByShort ?? '').trim().isNotEmpty)
                  _InfoPill(icon: Icons.badge_outlined, label: createdByShort!),
                PhaseBadge(phase: phaseText, onChangePhase: onChangePhase),
                _InfoPill(
                  icon: Icons.priority_high_rounded,
                  label: priorityLabel,
                  tint: service.priority <= 1
                      ? scheme.error
                      : (service.priority == 2
                            ? scheme.tertiary
                            : scheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (scheduledText != null && scheduledText!.trim().isNotEmpty) ...[
              _InfoRowWidget(icon: Icons.event_outlined, label: scheduledText!),
              const SizedBox(height: 4),
            ],
            if (technicianText.trim().isNotEmpty) ...[
              _InfoRowWidget(
                icon: Icons.engineering_outlined,
                label: technicianText,
              ),
              const SizedBox(height: 4),
            ],
            if (address.isNotEmpty)
              _InfoRowWidget(
                icon: Icons.place_outlined,
                label: address,
                trailing: onOpenMaps == null
                    ? null
                    : IconButton(
                        tooltip: 'Abrir Maps',
                        onPressed: onOpenMaps,
                        icon: const Icon(Icons.map_outlined, size: 16),
                        style: IconButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(30, 30),
                          foregroundColor: scheme.primary,
                          backgroundColor: scheme.primary.withValues(
                            alpha: 0.08,
                          ),
                        ),
                      ),
              ),
            const SizedBox(height: 8),
            ActionRow(
              onView: onView,
              onChangeState: onChangeState,
              onChat: onChat,
              onCall: onCall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});

  final OperationsMetricItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 118,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: item.tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: item.tint.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: item.tint.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.icon, size: 16, color: item.tint),
                  ),
                  const Spacer(),
                  Text(
                    item.value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactActionChip extends StatelessWidget {
  const _CompactActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint =
        foregroundColor ?? (highlighted ? scheme.primary : scheme.onSurface);

    return Material(
      color: highlighted
          ? scheme.primary.withValues(alpha: 0.10)
          : scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: tint),
              const SizedBox(width: 5),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tint,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label, this.tint});

  final IconData icon;
  final String label;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = tint ?? scheme.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRowWidget extends StatelessWidget {
  const _InfoRowWidget({
    required this.icon,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.76),
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ],
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      style: IconButton.styleFrom(
        minimumSize: const Size(34, 34),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: scheme.primary,
        backgroundColor: scheme.primary.withValues(alpha: 0.08),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.userName,
    required this.photoUrl,
    required this.onTap,
  });

  final String? userName;
  final String? photoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = _getInitials((userName ?? 'Usuario').trim());
    final trimmedUrl = photoUrl?.trim() ?? '';

    Widget child;
    if (trimmedUrl.isNotEmpty) {
      child = ClipOval(
        child: Image.network(
          trimmedUrl,
          width: 34,
          height: 34,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _ProfileFallback(initials: initials),
        ),
      );
    } else {
      child = _ProfileFallback(initials: initials);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(color: scheme.onPrimary.withValues(alpha: 0.18)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ProfileFallback extends StatelessWidget {
  const _ProfileFallback({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: Colors.white.withValues(alpha: 0.22),
      child: Text(
        initials.isEmpty ? 'U' : initials,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String datePresetLabel(OperationsDatePreset preset) {
  switch (preset) {
    case OperationsDatePreset.today:
      return 'Hoy';
    case OperationsDatePreset.week:
      return 'Semana';
    case OperationsDatePreset.month:
      return 'Mes';
    case OperationsDatePreset.custom:
      return 'Personalizado';
  }
}

String statusFilterLabel(OperationsStatusFilter status) {
  switch (status) {
    case OperationsStatusFilter.all:
      return 'Todos';
    case OperationsStatusFilter.pending:
      return 'Pendientes';
    case OperationsStatusFilter.inProgress:
      return 'En proceso';
    case OperationsStatusFilter.completed:
      return 'Completadas';
    case OperationsStatusFilter.cancelled:
      return 'Canceladas';
  }
}

String priorityFilterLabel(OperationsPriorityFilter priority) {
  switch (priority) {
    case OperationsPriorityFilter.all:
      return 'Todas';
    case OperationsPriorityFilter.high:
      return 'Alta';
    case OperationsPriorityFilter.normal:
      return 'Normal';
    case OperationsPriorityFilter.low:
      return 'Baja';
  }
}

({
  Color background,
  Color border,
  Color foreground,
  IconData icon,
  String label,
})
_statusBadgeTheme(String raw, ColorScheme scheme) {
  final normalized = raw.trim().toLowerCase();
  switch (normalized) {
    case 'reserved':
    case 'reserva':
    case 'survey':
    case 'levantamiento':
    case 'scheduled':
    case 'pendiente':
    case 'pending':
    case 'warranty':
      return (
        background: scheme.error.withValues(alpha: 0.10),
        border: scheme.error.withValues(alpha: 0.20),
        foreground: scheme.error,
        icon: Icons.schedule_rounded,
        label: 'Pendiente',
      );
    case 'in_progress':
    case 'in-progress':
    case 'en proceso':
    case 'en_proceso':
      return (
        background: scheme.tertiary.withValues(alpha: 0.12),
        border: scheme.tertiary.withValues(alpha: 0.20),
        foreground: scheme.tertiary,
        icon: Icons.sync_rounded,
        label: 'En proceso',
      );
    case 'completed':
    case 'completado':
    case 'completed_by_tech':
    case 'closed':
    case 'cerrado':
      return (
        background: scheme.primary.withValues(alpha: 0.10),
        border: scheme.primary.withValues(alpha: 0.18),
        foreground: scheme.primary,
        icon: Icons.check_circle_outline_rounded,
        label: 'Completada',
      );
    case 'cancelled':
    case 'cancelado':
      return (
        background: scheme.outline.withValues(alpha: 0.12),
        border: scheme.outline.withValues(alpha: 0.20),
        foreground: scheme.onSurfaceVariant,
        icon: Icons.block_outlined,
        label: 'Cancelada',
      );
    default:
      return (
        background: scheme.secondary.withValues(alpha: 0.10),
        border: scheme.secondary.withValues(alpha: 0.18),
        foreground: scheme.secondary,
        icon: Icons.inventory_2_outlined,
        label: raw.trim().isEmpty ? 'Servicio' : raw.trim(),
      );
  }
}

({Color background, Color border, Color foreground, IconData icon})
_phaseBadgeTheme(String normalized, ColorScheme scheme) {
  switch (normalized) {
    case 'levantamiento':
      return (
        background: scheme.secondary.withValues(alpha: 0.10),
        border: scheme.secondary.withValues(alpha: 0.18),
        foreground: scheme.secondary,
        icon: Icons.straighten_rounded,
      );
    case 'instalacion':
    case 'instalación':
      return (
        background: scheme.primary.withValues(alpha: 0.10),
        border: scheme.primary.withValues(alpha: 0.18),
        foreground: scheme.primary,
        icon: Icons.home_repair_service_outlined,
      );
    case 'mantenimiento':
      return (
        background: scheme.tertiary.withValues(alpha: 0.12),
        border: scheme.tertiary.withValues(alpha: 0.20),
        foreground: scheme.tertiary,
        icon: Icons.build_circle_outlined,
      );
    case 'garantia':
    case 'garantía':
      return (
        background: scheme.error.withValues(alpha: 0.08),
        border: scheme.error.withValues(alpha: 0.16),
        foreground: scheme.error,
        icon: Icons.verified_outlined,
      );
    default:
      return (
        background: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        border: scheme.outlineVariant.withValues(alpha: 0.4),
        foreground: scheme.onSurface,
        icon: Icons.flag_outlined,
      );
  }
}

String _getInitials(String input) {
  final parts = input
      .split(RegExp(r'\s+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return 'U';
  if (parts.length == 1) {
    final value = parts.first;
    return value.length >= 2
        ? value.substring(0, 2).toUpperCase()
        : value.toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}
