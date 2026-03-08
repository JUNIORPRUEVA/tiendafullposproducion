import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/primary_button.dart';
import '../../features/contabilidad/widgets/app_card.dart';
import 'application/work_scheduling_admin_controller.dart';
import 'application/work_scheduling_week_controller.dart';
import 'data/work_scheduling_repository.dart';
import 'horarios_models.dart';

class HorariosScreen extends ConsumerStatefulWidget {
  const HorariosScreen({super.key});

  @override
  ConsumerState<HorariosScreen> createState() => _HorariosScreenState();
}

class _HorariosScreenState extends ConsumerState<HorariosScreen> {
  bool _loadedAdminBasics = false;
  String? _loadedExceptionsWeekStart;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final user = ref.read(authStateProvider).user;
    final isAdmin = (user?.role ?? '').toUpperCase() == 'ADMIN';
    if (!isAdmin) return;

    final admin = ref.read(workSchedulingAdminControllerProvider.notifier);
    if (!_loadedAdminBasics) {
      _loadedAdminBasics = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        admin.loadBasics();
      });
    }

    final weekStart = ref.read(workSchedulingWeekControllerProvider).weekStart;
    final weekStartIso = dateOnly(weekStart);
    if (_loadedExceptionsWeekStart != weekStartIso) {
      _loadedExceptionsWeekStart = weekStartIso;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        admin.loadExceptionsForWeek(weekStartIso);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final isAdmin = (user?.role ?? '').toUpperCase() == 'ADMIN';

    return DefaultTabController(
      length: isAdmin ? 5 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Horarios'),
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          bottom: isAdmin
              ? const TabBar(
                  tabs: [
                    Tab(text: 'Calendario'),
                    Tab(text: 'Empleados'),
                    Tab(text: 'Cobertura'),
                    Tab(text: 'Excepciones'),
                    Tab(text: 'Reportes'),
                  ],
                )
              : null,
        ),
        drawer: AppDrawer(currentUser: user),
        body: isAdmin
            ? const TabBarView(
                children: [
                  _CalendarTab(),
                  _EmployeesTab(),
                  _CoverageTab(),
                  _ExceptionsTab(),
                  _ReportsTab(),
                ],
              )
            : const _CalendarTab(),
      ),
    );
  }
}

class _CalendarTab extends ConsumerWidget {
  const _CalendarTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final isAdmin = (user?.role ?? '').toUpperCase() == 'ADMIN';

    final state = ref.watch(workSchedulingWeekControllerProvider);
    final controller = ref.read(workSchedulingWeekControllerProvider.notifier);

    final weekStart = state.weekStart;
    final weekEnd = weekStart.add(const Duration(days: 6));
    final week = state.week;

    return RefreshIndicator(
      onRefresh: () => controller.load(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Semana anterior',
                onPressed: state.loading ? null : controller.prevWeek,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${dateOnly(weekStart)} → ${dateOnly(weekEnd)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Semana siguiente',
                onPressed: state.loading ? null : controller.nextWeek,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (state.error != null) ...[
            ErrorBanner(message: state.error!),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: state.loading ? null : controller.load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
            const SizedBox(height: 10),
          ],
          if (week == null)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No hay horarios generados para esta semana.',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAdmin
                        ? 'Genera la semana para asignar días libres y validar cobertura mínima.'
                        : 'Espera a que administración genere la semana.',
                  ),
                  if (isAdmin) ...[
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Generar semana',
                      loading: state.loading,
                      onPressed: () => controller.generateWeek(mode: 'REPLACE'),
                    ),
                  ],
                ],
              ),
            )
          else ...[
            if (week.warnings.isNotEmpty) ...[
              AppCard(
                margin: const EdgeInsets.only(bottom: 12),
                child: _WarningsBox(warnings: week.warnings),
              ),
            ],
            if (isAdmin) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.loading
                          ? null
                          : () => controller.generateWeek(mode: 'KEEP_MANUAL'),
                      icon: const Icon(Icons.auto_fix_high_outlined),
                      label: const Text('Regenerar (mantener manual)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: state.loading
                          ? null
                          : () => controller.generateWeek(mode: 'REPLACE'),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Regenerar (reemplazar)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            _WeekTable(
              isAdmin: isAdmin,
              week: week,
              weekStart: weekStart,
            ),
          ],
        ],
      ),
    );
  }
}

class _WarningsBox extends StatelessWidget {
  final List<Map<String, dynamic>> warnings;

  const _WarningsBox({required this.warnings});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colorScheme.error),
            const SizedBox(width: 8),
            const Text(
              'Validación',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...warnings.map((w) {
          final type = (w['type'] ?? '').toString();
          if (type == 'COVERAGE_SHORTAGE') {
            final role = (w['role'] ?? '').toString();
            final weekday = (w['weekday'] as num?)?.toInt() ?? 0;
            final date = (w['date'] ?? '').toString();
            final missing = (w['missing'] as num?)?.toInt() ?? 0;
            final min = (w['min_required'] as num?)?.toInt() ?? 0;
            final working = (w['working'] as num?)?.toInt() ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• Falta cobertura: $role ($date ${weekdayLabelEs(weekday)}): $working/$min (faltan $missing)',
                style: TextStyle(color: colorScheme.error),
              ),
            );
          }
          if (type == 'NO_DAY_OFF_THIS_WEEK') {
            final userId = (w['user_id'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• Usuario sin día libre esta semana: $userId'),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('• $type'),
          );
        }),
      ],
    );
  }
}

class _WeekTable extends ConsumerWidget {
  final bool isAdmin;
  final WorkWeekSchedule week;
  final DateTime weekStart;

  const _WeekTable({
    required this.isAdmin,
    required this.week,
    required this.weekStart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final weekDates = List.generate(
      7,
      (i) => dateOnly(weekStart.add(Duration(days: i))),
    );

    final byUser = <String, List<WorkDayAssignment>>{};
    for (final a in week.days) {
      byUser.putIfAbsent(a.userId, () => []).add(a);
    }

    final users = byUser.entries.toList()
      ..sort((a, b) {
        final an = (a.value.isNotEmpty ? a.value.first.userName : '');
        final bn = (b.value.isNotEmpty ? b.value.first.userName : '');
        return an.toLowerCase().compareTo(bn.toLowerCase());
      });

    Map<String, WorkDayAssignment> mapByDate(List<WorkDayAssignment> list) {
      final out = <String, WorkDayAssignment>{};
      for (final a in list) {
        out[a.date] = a;
      }
      return out;
    }

    Future<void> openManualSheet(WorkDayAssignment assignment) async {
      final weekCtrl = ref.read(workSchedulingWeekControllerProvider.notifier);
      final reasonCtrl = TextEditingController(text: 'Ajuste manual');

      final otherDates = weekDates.where((d) => d != assignment.date).toList();
      String moveToDate = otherDates.isNotEmpty ? otherDates.first : assignment.date;

      // Swap candidates: users who have a DAY_OFF in the week.
      final dayOffByUser = <String, List<String>>{};
      for (final entry in byUser.entries) {
        final offDates = entry.value
            .where((a) => a.status == 'DAY_OFF')
            .map((a) => a.date)
            .toSet()
            .toList()
          ..sort();
        if (offDates.isNotEmpty) dayOffByUser[entry.key] = offDates;
      }
      final swapUserIds = dayOffByUser.keys.where((id) => id != assignment.userId).toList();
      swapUserIds.sort();
      String? swapUserId = swapUserIds.isNotEmpty ? swapUserIds.first : null;
      String? swapUserDayOffDate =
          (swapUserId != null && (dayOffByUser[swapUserId]?.isNotEmpty ?? false))
              ? dayOffByUser[swapUserId]!.first
              : null;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              final inset = MediaQuery.viewInsetsOf(ctx);
              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 16 + inset.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cambios manuales',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${assignment.userName}\nDía libre actual: ${assignment.date}',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Motivo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: moveToDate,
                      items: otherDates
                          .map(
                            (d) => DropdownMenuItem(value: d, child: Text(d)),
                          )
                          .toList(),
                      onChanged: (v) => setModalState(() {
                        moveToDate = v ?? moveToDate;
                      }),
                      decoration: const InputDecoration(
                        labelText: 'Mover día libre a',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    PrimaryButton(
                      label: 'Mover día libre',
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await weekCtrl.manualMoveDayOff(
                          userId: assignment.userId,
                          fromDate: assignment.date,
                          toDate: moveToDate,
                          reason: reasonCtrl.text.trim().isEmpty
                              ? 'Ajuste manual'
                              : reasonCtrl.text.trim(),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    if (swapUserId != null && swapUserDayOffDate != null) ...[
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: swapUserId,
                        items: swapUserIds
                            .map((id) {
                              final name = byUser[id]?.first.userName ?? id;
                              return DropdownMenuItem(
                                value: id,
                                child: Text(name),
                              );
                            })
                            .toList(),
                        onChanged: (v) => setModalState(() {
                          swapUserId = v;
                          final dates = dayOffByUser[v] ?? const [];
                          swapUserDayOffDate =
                              dates.isNotEmpty ? dates.first : null;
                        }),
                        decoration: const InputDecoration(
                          labelText: 'Intercambiar con',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: swapUserDayOffDate,
                        items: (dayOffByUser[swapUserId] ?? const [])
                            .map(
                              (d) => DropdownMenuItem(
                                value: d,
                                child: Text(d),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setModalState(() {
                          swapUserDayOffDate = v;
                        }),
                        decoration: const InputDecoration(
                          labelText: 'Día libre del otro empleado',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      PrimaryButton(
                        label: 'Intercambiar días libres',
                        onPressed: () async {
                          final bId = swapUserId;
                          final bDate = swapUserDayOffDate;
                          if (bId == null || bDate == null) return;
                          Navigator.pop(ctx);
                          await weekCtrl.manualSwapDayOff(
                            userAId: assignment.userId,
                            userADayOffDate: assignment.date,
                            userBId: bId,
                            userBDayOffDate: bDate,
                            reason: reasonCtrl.text.trim().isEmpty
                                ? 'Ajuste manual'
                                : reasonCtrl.text.trim(),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      );

      reasonCtrl.dispose();
    }

    Widget cellFor(Map<String, WorkDayAssignment> byDate, String date) {
      final assignment = byDate[date];
      if (assignment == null) {
        return const SizedBox(height: 44, child: Center(child: Text('—')));
      }

      final isDayOff = assignment.status == 'DAY_OFF';
      final isExceptionOff = assignment.status == 'EXCEPTION_OFF';
      final isWork = assignment.status == 'WORK';

      final bg = isDayOff
          ? Color.alphaBlend(
              Colors.green.withValues(alpha: 0.12),
              colorScheme.surface,
            )
          : isExceptionOff
              ? Color.alphaBlend(
                  Colors.orange.withValues(alpha: 0.12),
                  colorScheme.surface,
                )
              : colorScheme.surface;

      final borderColor = assignment.conflictFlags.isNotEmpty
          ? colorScheme.error.withValues(alpha: 0.7)
          : colorScheme.outlineVariant.withValues(alpha: 0.6);

      final label = isDayOff
          ? 'LIBRE'
          : isExceptionOff
              ? 'EXC.'
              : isWork
                  ? '${minutesToHm(assignment.startMinute)}-${minutesToHm(assignment.endMinute)}'
                  : '—';

      return InkWell(
        onTap: (!isAdmin || !isDayOff) ? null : () => openManualSheet(assignment),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: assignment.conflictFlags.isNotEmpty
                        ? colorScheme.error
                        : null,
                  ),
                ),
              ),
              if (assignment.manualOverride) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.edit_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 14,
        dataRowMinHeight: 64,
        dataRowMaxHeight: 88,
        columns: [
          const DataColumn(
            label: Text(
              'Empleado',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          for (int i = 0; i < 7; i++)
            DataColumn(
              label: Text(
                '${weekdayLabelEs(i)}\n${weekDates[i].substring(5)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
        rows: [
          for (final u in users)
            DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 190,
                    child: Text(
                      u.value.isNotEmpty ? u.value.first.userName : '',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                for (final d in weekDates)
                  DataCell(
                    SizedBox(
                      width: 130,
                      child: cellFor(mapByDate(u.value), d),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EmployeesTab extends ConsumerWidget {
  const _EmployeesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workSchedulingAdminControllerProvider);
    final controller = ref.read(workSchedulingAdminControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.error != null) ...[
          ErrorBanner(message: state.error!),
          const SizedBox(height: 10),
        ],
        AppCard(
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Empleados y configuración',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: state.loading ? null : controller.loadBasics,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...state.employees.map((e) {
          return AppCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                e.nombreCompleto,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('${e.role}${e.blocked ? ' • BLOQUEADO' : ''}'),
              trailing: Switch(
                value: e.schedule.enabled,
                onChanged: state.loading
                    ? null
                    : (v) => controller.saveEmployeeConfig(e.id, enabled: v),
              ),
              onTap: () => _openEmployeeEditor(context, ref, e),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _openEmployeeEditor(
    BuildContext context,
    WidgetRef ref,
    WorkEmployee employee,
  ) async {
    final admin = ref.read(workSchedulingAdminControllerProvider.notifier);
    final state = ref.read(workSchedulingAdminControllerProvider);
    final profiles = state.profiles;

    String? selectedProfileId = employee.schedule.scheduleProfileId;
    int? fixed = employee.schedule.fixedDayOffWeekday;
    int? preferred = employee.schedule.preferredDayOffWeekday;
    final disallowed = employee.schedule.disallowedDayOffWeekdays.toSet();
    final unavailable = employee.schedule.unavailableWeekdays.toSet();
    final notesCtrl = TextEditingController(text: employee.schedule.notes ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(employee.nombreCompleto),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedProfileId,
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Perfil por defecto'),
                    ),
                    ...profiles.map(
                      (p) => DropdownMenuItem<String>(
                        value: p.id,
                        child: Text(p.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => selectedProfileId = v,
                  decoration: const InputDecoration(
                    labelText: 'Perfil de horario',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: fixed,
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('Sin día libre fijo'),
                    ),
                    for (int i = 0; i < 7; i++)
                      DropdownMenuItem<int>(
                        value: i,
                        child: Text('Fijo: ${weekdayLabelEs(i)}'),
                      ),
                  ],
                  onChanged: (v) => fixed = v,
                  decoration: const InputDecoration(
                    labelText: 'Día libre fijo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: preferred,
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('Sin preferencia'),
                    ),
                    for (int i = 0; i < 7; i++)
                      DropdownMenuItem<int>(
                        value: i,
                        child: Text('Prefiere: ${weekdayLabelEs(i)}'),
                      ),
                  ],
                  onChanged: (v) => preferred = v,
                  decoration: const InputDecoration(
                    labelText: 'Día libre preferido',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                _WeekdayChips(
                  title: 'No permitir día libre en',
                  selected: disallowed,
                ),
                const SizedBox(height: 12),
                _WeekdayChips(
                  title: 'No disponible para trabajar',
                  selected: unavailable,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notas',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await admin.saveEmployeeConfig(
                  employee.id,
                  scheduleProfileId: selectedProfileId,
                  fixedDayOffWeekday: fixed,
                  preferredDayOffWeekday: preferred,
                  disallowedDayOffWeekdays: disallowed.toList()..sort(),
                  unavailableWeekdays: unavailable.toList()..sort(),
                  notes: notesCtrl.text.trim(),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    notesCtrl.dispose();
  }
}

class _WeekdayChips extends StatefulWidget {
  final String title;
  final Set<int> selected;

  const _WeekdayChips({required this.title, required this.selected});

  @override
  State<_WeekdayChips> createState() => _WeekdayChipsState();
}

class _WeekdayChipsState extends State<_WeekdayChips> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < 7; i++)
              FilterChip(
                label: Text(weekdayLabelEs(i)),
                selected: widget.selected.contains(i),
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      widget.selected.add(i);
                    } else {
                      widget.selected.remove(i);
                    }
                  });
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _CoverageTab extends ConsumerStatefulWidget {
  const _CoverageTab();

  @override
  ConsumerState<_CoverageTab> createState() => _CoverageTabState();
}

class _CoverageTabState extends ConsumerState<_CoverageTab> {
  final Map<String, TextEditingController> _ctrls = {};

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workSchedulingAdminControllerProvider);
    final controller = ref.read(workSchedulingAdminControllerProvider.notifier);

    for (final r in state.coverageRules) {
      final key = '${r.role}:${r.weekday}';
      _ctrls.putIfAbsent(
        key,
        () => TextEditingController(text: r.minRequired.toString()),
      );
    }

    final roles = state.coverageRules.map((e) => e.role).toSet().toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.error != null) ...[
          ErrorBanner(message: state.error!),
          const SizedBox(height: 10),
        ],
        AppCard(
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Cobertura mínima por rol/día',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: state.loading
                    ? null
                    : () {
                        final next = <WorkCoverageRule>[];
                        for (final role in roles) {
                          for (int weekday = 0; weekday < 7; weekday++) {
                            final key = '$role:$weekday';
                            final txt = _ctrls[key]?.text.trim() ?? '0';
                            final v = int.tryParse(txt) ?? 0;
                            next.add(
                              WorkCoverageRule(
                                role: role,
                                weekday: weekday,
                                minRequired: v < 0 ? 0 : v,
                              ),
                            );
                          }
                        }
                        controller.saveCoverageRules(next);
                      },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Rol')),
              DataColumn(label: Text('Lun')),
              DataColumn(label: Text('Mar')),
              DataColumn(label: Text('Mié')),
              DataColumn(label: Text('Jue')),
              DataColumn(label: Text('Vie')),
              DataColumn(label: Text('Sáb')),
              DataColumn(label: Text('Dom')),
            ],
            rows: [
              for (final role in roles)
                DataRow(
                  cells: [
                    DataCell(Text(role)),
                    for (int weekday = 0; weekday < 7; weekday++)
                      DataCell(
                        SizedBox(
                          width: 52,
                          child: TextField(
                            controller: _ctrls['$role:$weekday'],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExceptionsTab extends ConsumerWidget {
  const _ExceptionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminState = ref.watch(workSchedulingAdminControllerProvider);
    final admin = ref.read(workSchedulingAdminControllerProvider.notifier);
    final repo = ref.read(workSchedulingRepositoryProvider);
    final weekStart = ref.watch(workSchedulingWeekControllerProvider).weekStart;
    final weekStartIso = dateOnly(weekStart);

    Future<void> refresh() => admin.loadExceptionsForWeek(weekStartIso);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (adminState.error != null) ...[
          ErrorBanner(message: adminState.error!),
          const SizedBox(height: 10),
        ],
        AppCard(
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Excepciones',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Nueva',
                onPressed: adminState.loading
                    ? null
                    : () => _openExceptionEditor(
                          context,
                          ref,
                          weekStartIso,
                        ),
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: adminState.loading ? null : refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...adminState.exceptions.map((e) {
          return AppCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${e.type} • ${e.dateFrom} → ${e.dateTo}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${e.userName ?? 'GLOBAL'}${(e.note ?? '').trim().isEmpty ? '' : ' • ${e.note}'}',
              ),
              onTap: adminState.loading
                  ? null
                  : () => _openExceptionEditor(
                        context,
                        ref,
                        weekStartIso,
                        existing: e,
                      ),
              trailing: IconButton(
                tooltip: 'Eliminar',
                onPressed: adminState.loading
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Eliminar excepción'),
                            content: const Text('¿Seguro?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await repo.deleteException(e.id);
                        await refresh();
                      },
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _openExceptionEditor(
    BuildContext context,
    WidgetRef ref,
    String weekStartIso, {
    WorkScheduleException? existing,
  }) async {
    final adminState = ref.read(workSchedulingAdminControllerProvider);
    final admin = ref.read(workSchedulingAdminControllerProvider.notifier);
    final repo = ref.read(workSchedulingRepositoryProvider);

    final employees = adminState.employees;

    String? userId = existing?.userId;
    String type = existing?.type ?? 'HOLIDAY';
    DateTime from = existing != null ? parseDateOnly(existing.dateFrom) : parseDateOnly(weekStartIso);
    DateTime to = existing != null ? parseDateOnly(existing.dateTo) : parseDateOnly(weekStartIso);
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    const types = [
      'HOLIDAY',
      'VACATION',
      'SICK',
      'LEAVE',
      'LICENSE',
      'ABSENCE',
      'BLOCKED_DAY',
    ];

    Future<void> pickFrom() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: from,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked != null) from = picked;
    }

    Future<void> pickTo() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: to,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked != null) to = picked;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text(existing == null ? 'Nueva excepción' : 'Editar excepción'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String?>(
                      value: userId,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('GLOBAL (todos)'),
                        ),
                        ...employees.map(
                          (e) => DropdownMenuItem<String?>(
                            value: e.id,
                            child: Text(e.nombreCompleto),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => userId = v),
                      decoration: const InputDecoration(
                        labelText: 'Empleado',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: type,
                      items: types
                          .map(
                            (t) => DropdownMenuItem<String>(
                              value: t,
                              child: Text(t),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => type = v ?? type),
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await pickFrom();
                              setState(() {});
                            },
                            child: Text('Desde: ${dateOnly(from)}'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await pickTo();
                              setState(() {});
                            },
                            child: Text('Hasta: ${dateOnly(to)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Nota',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final note = noteCtrl.text.trim();
                    if (existing == null) {
                      await repo.createException(
                        userId: userId,
                        type: type,
                        dateFrom: dateOnly(from),
                        dateTo: dateOnly(to),
                        note: note.isEmpty ? null : note,
                      );
                    } else {
                      await repo.updateException(
                        id: existing.id,
                        type: type,
                        dateFrom: dateOnly(from),
                        dateTo: dateOnly(to),
                        note: note.isEmpty ? null : note,
                      );
                    }
                    await admin.loadExceptionsForWeek(weekStartIso);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    noteCtrl.dispose();
  }
}

class _ReportsTab extends ConsumerWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workSchedulingAdminControllerProvider);
    final controller = ref.read(workSchedulingAdminControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.error != null) ...[
          ErrorBanner(message: state.error!),
          const SizedBox(height: 10),
        ],
        AppCard(
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Reportes y auditoría',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: state.loading ? null : controller.loadAuditAndReports,
                icon: const Icon(Icons.refresh),
                label: const Text('Cargar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cambios por empleado (raw)',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (state.reportMostChanges.isEmpty)
                const Text('Sin datos')
              else
                ...state.reportMostChanges
                    .take(20)
                    .map((r) => Text('• ${r.toString()}')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Días con baja cobertura (raw)',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (state.reportLowCoverage.isEmpty)
                const Text('Sin datos')
              else
                ...state.reportLowCoverage
                    .take(20)
                    .map((r) => Text('• ${r.toString()}')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Auditoría (últimos)',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (state.audit.isEmpty)
                const Text('Sin auditoría en el rango')
              else
                ...state.audit.take(30).map(
                      (a) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '• ${a.createdAt.toIso8601String()} ${a.action} (${a.actorName})',
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}
