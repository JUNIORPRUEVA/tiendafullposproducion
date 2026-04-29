import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors/user_facing_error.dart';
import '../../core/models/punch_model.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/professional_recovery_card.dart';
import '../ponche/data/punch_repository.dart';
import '../ponche/models/attendance_models.dart';

enum _AdminRegistryMenuAction { filters, sync, panel }

enum _UserDetailDatePreset { hoy, manana, quincena, mes, personalizado }

class AdminPunchRegistryScreen extends ConsumerStatefulWidget {
  const AdminPunchRegistryScreen({super.key});

  @override
  ConsumerState<AdminPunchRegistryScreen> createState() =>
      _AdminPunchRegistryScreenState();
}

class _AdminPunchRegistryScreenState
    extends ConsumerState<AdminPunchRegistryScreen> {
  static const List<int> _autoRetrySecondsByAttempt = <int>[3, 6, 12];

  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  bool _showSummaryPanel = true;
  UserFacingError? _error;
  AttendanceSummaryModel? _summary;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  Timer? _autoRetryTimer;
  int _autoRetryAttempt = 0;
  int _autoRetryCountdown = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _autoRetryTimer?.cancel();

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _autoRetryCountdown = 0;
      });
    }

    try {
      final summary = await ref.read(punchRepositoryProvider).fetchAttendanceSummary(
            from: DateTime(_from.year, _from.month, _from.day),
            to: DateTime(_to.year, _to.month, _to.day),
          );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _autoRetryAttempt = 0;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = UserFacingError.from(error));
      _scheduleAutoRetryIfNeeded();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleAutoRetryIfNeeded() {
    final error = _error;
    if (error == null || !error.autoRetry) return;
    if (_autoRetryAttempt >= _autoRetrySecondsByAttempt.length) return;

    final seconds = _autoRetrySecondsByAttempt[_autoRetryAttempt];
    setState(() => _autoRetryCountdown = seconds);

    _autoRetryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_autoRetryCountdown <= 1) {
        timer.cancel();
        _autoRetryAttempt += 1;
        unawaited(_load());
        return;
      }
      setState(() => _autoRetryCountdown -= 1);
    });
  }

  Future<void> _retryNow() async {
    _autoRetryTimer?.cancel();
    if (mounted) setState(() => _autoRetryCountdown = 0);
    await _load();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _load();
  }

  Future<void> _handleBack() async {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    context.go(Routes.administracion);
  }

  Future<void> _handleMenuAction(_AdminRegistryMenuAction action) async {
    switch (action) {
      case _AdminRegistryMenuAction.filters:
        await _pickDateRange();
        break;
      case _AdminRegistryMenuAction.sync:
        await _load();
        break;
      case _AdminRegistryMenuAction.panel:
        if (!mounted) return;
        setState(() => _showSummaryPanel = !_showSummaryPanel);
        break;
    }
  }

  List<AttendanceUserSummary> get _visibleUsers {
    final users = _summary?.users ?? const <AttendanceUserSummary>[];
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return users;

    return users.where((item) {
      return item.user.nombreCompleto.toLowerCase().contains(query) ||
          item.user.email.toLowerCase().contains(query) ||
          item.user.role.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<void> _openUserDetail(AttendanceUserSummary summary) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AdminPunchUserDetailScreen(
          user: summary.user,
          initialFrom: _from,
          initialTo: _to,
        ),
      ),
    );
  }

  String _dateOnlyText(DateTime value) {
    return DateFormat('dd/MM/yyyy', 'es_DO').format(value);
  }

  String _formatMinutes(int minutes) {
    final sign = minutes < 0 ? '-' : '';
    final absolute = minutes.abs();
    final hours = absolute ~/ 60;
    final remainingMinutes = absolute % 60;
    return '$sign${hours}h ${remainingMinutes.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = _visibleUsers;
    final summary = _summary;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isPhone = constraints.maxWidth < 700;

            return Column(
              children: [
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Regresar',
                            onPressed: _handleBack,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (_) => setState(() {}),
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'Buscar usuario',
                                prefixIcon: const Icon(Icons.search_rounded),
                                filled: true,
                                fillColor: scheme.surface,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (isPhone)
                            PopupMenuButton<_AdminRegistryMenuAction>(
                              tooltip: 'Opciones',
                              onSelected: _handleMenuAction,
                              itemBuilder: (context) => [
                                const PopupMenuItem<_AdminRegistryMenuAction>(
                                  value: _AdminRegistryMenuAction.filters,
                                  child: _AdminTopMenuItem(
                                    icon: Icons.tune_rounded,
                                    label: 'Filtro',
                                  ),
                                ),
                                const PopupMenuItem<_AdminRegistryMenuAction>(
                                  value: _AdminRegistryMenuAction.sync,
                                  child: _AdminTopMenuItem(
                                    icon: Icons.sync_rounded,
                                    label: 'Sincronizar',
                                  ),
                                ),
                                PopupMenuItem<_AdminRegistryMenuAction>(
                                  value: _AdminRegistryMenuAction.panel,
                                  child: _AdminTopMenuItem(
                                    icon: _showSummaryPanel
                                        ? Icons.space_dashboard_rounded
                                        : Icons.space_dashboard_outlined,
                                    label: _showSummaryPanel
                                        ? 'Ocultar panel'
                                        : 'Mostrar panel',
                                  ),
                                ),
                              ],
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.more_vert_rounded),
                              ),
                            )
                          else ...[
                            _CompactTopActionButton(
                              icon: Icons.tune_rounded,
                              tooltip: 'Filtro',
                              onTap: _pickDateRange,
                            ),
                            const SizedBox(width: 6),
                            _CompactTopActionButton(
                              icon: Icons.sync_rounded,
                              tooltip: 'Sincronizar',
                              onTap: _load,
                            ),
                            const SizedBox(width: 6),
                            _CompactTopActionButton(
                              icon: _showSummaryPanel
                                  ? Icons.space_dashboard_rounded
                                  : Icons.space_dashboard_outlined,
                              tooltip: 'Panel',
                              onTap: () => setState(
                                () => _showSummaryPanel = !_showSummaryPanel,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_showSummaryPanel) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ponches por usuario',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${_dateOnlyText(_from)} - ${_dateOnlyText(_to)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _AdminPunchInfoChip(
                                    icon: Icons.group_outlined,
                                    label: 'Usuarios',
                                    value: '${visible.length}',
                                  ),
                                  _AdminPunchInfoChip(
                                    icon: Icons.warning_amber_rounded,
                                    label: 'Incidentes',
                                    value: '${summary?.totals.tardyCount ?? 0}',
                                  ),
                                  _AdminPunchInfoChip(
                                    icon: Icons.timelapse_outlined,
                                    label: 'Horas',
                                    value: _formatMinutes(
                                      summary?.totals.workedMinutes ?? 0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: _error != null
                      ? ProfessionalRecoveryCard(
                          error: _error!,
                          autoRetryCountdown: _autoRetryCountdown > 0
                              ? _autoRetryCountdown
                              : null,
                          isRetrying: _loading,
                          onRetryNow: _retryNow,
                        )
                      : visible.isEmpty
                          ? Center(
                              child: Text(
                                'No hay usuarios con ponches para mostrar en este período.',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (context, index) {
                                  final item = visible[index];
                                  final balance = item.aggregate.balanceMinutes;
                                  final accentColor = balance >= 0
                                      ? const Color(0xFF0F766E)
                                      : const Color(0xFFB91C1C);

                                  return _AdminPunchUserCard(
                                    summary: item,
                                    accentColor: accentColor,
                                    dateRangeLabel:
                                        '${_dateOnlyText(_from)} - ${_dateOnlyText(_to)}',
                                    workedLabel: _formatMinutes(
                                      item.aggregate.workedMinutes,
                                    ),
                                    balanceLabel: _formatMinutes(balance),
                                    incidentLabel:
                                        '${item.aggregate.incidentsCount} incidentes',
                                    onTap: () => _openUserDetail(item),
                                  );
                                },
                              ),
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdminPunchUserDetailScreen extends ConsumerStatefulWidget {
  const _AdminPunchUserDetailScreen({
    required this.user,
    required this.initialFrom,
    required this.initialTo,
  });

  final AttendanceUser user;
  final DateTime initialFrom;
  final DateTime initialTo;

  @override
  ConsumerState<_AdminPunchUserDetailScreen> createState() =>
      _AdminPunchUserDetailScreenState();
}

class _AdminPunchUserDetailScreenState
    extends ConsumerState<_AdminPunchUserDetailScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  bool _showHeaderPanel = true;
  UserFacingError? _error;
  AttendanceDetailModel? _detail;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  PunchType? _selectedType;

  @override
  void initState() {
    super.initState();
    _from = widget.initialFrom;
    _to = widget.initialTo;
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final detail = await ref.read(punchRepositoryProvider).fetchAttendanceDetail(
            widget.user.id,
            from: DateTime(_from.year, _from.month, _from.day),
            to: DateTime(_to.year, _to.month, _to.day),
          );
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = UserFacingError.from(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showFiltersSheet() async {
    final nextSearch = TextEditingController(text: _searchCtrl.text);
    DateTime tempFrom = _from;
    DateTime tempTo = _to;
    PunchType? tempType = _selectedType;
    bool applied = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final scheme = theme.colorScheme;

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickRange() async {
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange: DateTimeRange(start: tempFrom, end: tempTo),
                firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (picked == null) return;
              setModalState(() {
                tempFrom = DateTime(
                  picked.start.year,
                  picked.start.month,
                  picked.start.day,
                );
                tempTo = DateTime(
                  picked.end.year,
                  picked.end.month,
                  picked.end.day,
                );
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filtros del detalle',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nextSearch,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Buscar por tipo o fecha',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: scheme.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: pickRange,
                    icon: const Icon(Icons.date_range_rounded),
                    label: Text(
                      '${_dateOnlyText(tempFrom)} - ${_dateOnlyText(tempTo)}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AdminTypeFilterChip(
                        label: 'Todos',
                        selected: tempType == null,
                        onTap: () => setModalState(() => tempType = null),
                      ),
                      ...PunchType.values.map(
                        (type) => _AdminTypeFilterChip(
                          label: type.label,
                          selected: tempType == type,
                          onTap: () => setModalState(() => tempType = type),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        applied = true;
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Aplicar'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted) {
      nextSearch.dispose();
      return;
    }

    if (applied) {
      setState(() {
        _searchCtrl.text = nextSearch.text;
        _from = tempFrom;
        _to = tempTo;
        _selectedType = tempType;
      });
      await _load();
    }

    nextSearch.dispose();
  }

  String _dateOnlyText(DateTime value) {
    return DateFormat('dd/MM/yyyy', 'es_DO').format(value);
  }

  String _dateTimeText(DateTime value) {
    return DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(value.toLocal());
  }

  String _formatMinutes(int minutes) {
    final sign = minutes < 0 ? '-' : '';
    final absolute = minutes.abs();
    final hours = absolute ~/ 60;
    final remainingMinutes = absolute % 60;
    return '$sign${hours}h ${remainingMinutes.toString().padLeft(2, '0')}m';
  }

  List<PunchModel> get _visiblePunches {
    final detail = _detail;
    if (detail == null) return const <PunchModel>[];
    final query = _searchCtrl.text.trim().toLowerCase();

    final rows = [...detail.punches]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return rows.where((item) {
      if (_selectedType != null && item.type != _selectedType) {
        return false;
      }
      if (query.isEmpty) return true;
      return item.type.label.toLowerCase().contains(query) ||
          _dateTimeText(item.timestamp).toLowerCase().contains(query);
    }).toList(growable: false);
  }

  List<_PunchDayGroup> get _visibleDayGroups {
    final buckets = <DateTime, List<PunchModel>>{};
    for (final punch in _visiblePunches) {
      final day = DateTime(
        punch.timestamp.year,
        punch.timestamp.month,
        punch.timestamp.day,
      );
      buckets.putIfAbsent(day, () => <PunchModel>[]).add(punch);
    }

    final groups = buckets.entries.map((entry) {
      final punches = [...entry.value]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return _PunchDayGroup(date: entry.key, punches: punches);
    }).toList(growable: false)
      ..sort((a, b) => b.date.compareTo(a.date));
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detail = _detail;
    final visible = _visibleDayGroups;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Regresar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      _CompactTopActionButton(
                        icon: Icons.tune_rounded,
                        tooltip: 'Filtros',
                        onTap: _showFiltersSheet,
                      ),
                      const SizedBox(width: 6),
                      _CompactTopActionButton(
                        icon: _showHeaderPanel
                            ? Icons.space_dashboard_rounded
                            : Icons.space_dashboard_outlined,
                        tooltip: 'Panel',
                        onTap: () => setState(
                          () => _showHeaderPanel = !_showHeaderPanel,
                        ),
                      ),
                    ],
                  ),
                  if (_showHeaderPanel) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.user.nombreCompleto,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.user.role.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: scheme.primary,
                            ),
                          ),
                          if (detail != null) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _AdminPunchInfoChip(
                                  icon: Icons.calendar_month_rounded,
                                  label: 'Dias',
                                  value: '${visible.length}',
                                ),
                                _AdminPunchInfoChip(
                                  icon: Icons.access_time_rounded,
                                  label: 'Ponches',
                                  value: '${detail.punches.length}',
                                ),
                                _AdminPunchInfoChip(
                                  icon: Icons.timelapse_outlined,
                                  label: 'Horas',
                                  value: _formatMinutes(detail.totals.workedMinutes),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_dateOnlyText(_from)} - ${_dateOnlyText(_to)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? ProfessionalRecoveryCard(
                      error: _error!,
                      autoRetryCountdown: null,
                      isRetrying: _loading,
                      onRetryNow: _load,
                    )
                  : detail == null
                      ? const SizedBox.shrink()
                      : visible.isEmpty
                          ? Center(
                              child: Text(
                                'No hay ponches para este filtro.',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 18),
                                itemBuilder: (context, index) {
                                  final group = visible[index];
                                  return _AdminPunchDaySection(
                                    dateLabel: DateFormat(
                                      'EEEE, d MMMM yyyy',
                                      'es_DO',
                                    ).format(group.date),
                                    punches: group.punches,
                                    dateTextBuilder: _dateTimeText,
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminTopMenuItem extends StatelessWidget {
  const _AdminTopMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 10),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _CompactTopActionButton extends StatelessWidget {
  const _CompactTopActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20),
          ),
        ),
      ),
    );
  }
}

class _AdminPunchUserCard extends StatelessWidget {
  const _AdminPunchUserCard({
    required this.summary,
    required this.accentColor,
    required this.dateRangeLabel,
    required this.workedLabel,
    required this.balanceLabel,
    required this.incidentLabel,
    required this.onTap,
  });

  final AttendanceUserSummary summary;
  final Color accentColor;
  final String dateRangeLabel;
  final String workedLabel;
  final String balanceLabel;
  final String incidentLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.32),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 46,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.user.nombreCompleto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _AdminMiniLabel(text: summary.user.role.toUpperCase()),
                        _AdminMiniLabel(text: workedLabel),
                        _AdminMiniLabel(text: balanceLabel, color: accentColor),
                        _AdminMiniLabel(text: incidentLabel),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    dateRangeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminPunchDaySection extends StatelessWidget {
  const _AdminPunchDaySection({
    required this.dateLabel,
    required this.punches,
    required this.dateTextBuilder,
  });

  final String dateLabel;
  final List<PunchModel> punches;
  final String Function(DateTime value) dateTextBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _capitalize(dateLabel),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Text(
              '${punches.length} ponches',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...List.generate(punches.length, (index) {
          final punch = punches[index];
          return Column(
            children: [
              _AdminPunchLineItem(
                punch: punch,
                dateText: dateTextBuilder(punch.timestamp),
              ),
              if (index != punches.length - 1)
                Divider(
                  height: 12,
                  color: scheme.outlineVariant.withValues(alpha: 0.25),
                ),
            ],
          );
        }),
      ],
    );
  }
}

class _AdminPunchLineItem extends StatelessWidget {
  const _AdminPunchLineItem({required this.punch, required this.dateText});

  final PunchModel punch;
  final String dateText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                punch.type.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          DateFormat('h:mm a', 'es_DO').format(punch.timestamp.toLocal()),
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _AdminPunchInfoChip extends StatelessWidget {
  const _AdminPunchInfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminMiniLabel extends StatelessWidget {
  const _AdminMiniLabel({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurfaceVariant;

    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: effectiveColor,
      ),
    );
  }
}

class _AdminTypeFilterChip extends StatelessWidget {
  const _AdminTypeFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : scheme.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.35)
                  : scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _PunchDayGroup {
  const _PunchDayGroup({required this.date, required this.punches});

  final DateTime date;
  final List<PunchModel> punches;
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
