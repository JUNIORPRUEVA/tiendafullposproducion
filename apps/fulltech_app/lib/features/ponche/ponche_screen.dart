import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/punch_model.dart';
import './application/punch_controller.dart';
import './models/attendance_models.dart';

class PoncheScreen extends ConsumerStatefulWidget {
  const PoncheScreen({super.key});

  @override
  ConsumerState<PoncheScreen> createState() => _PoncheScreenState();
}

class _PoncheScreenState extends ConsumerState<PoncheScreen> {
  void _showPunchOptions(PunchState state) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '¿Qué deseas registrar?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ...PunchType.values.map(
                (type) => ListTile(
                  leading: Icon(_iconFor(type), color: AppTheme.primaryColor),
                  title: Text(type.label),
                  onTap: state.creating
                      ? null
                      : () {
                          Navigator.pop(context);
                          _handlePunch(type);
                        },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showHistory(PunchState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          builder: (context, controller) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Historial de ponches',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (state.loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (state.items.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('Aún no hay ponches registrados'),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      controller: controller,
                      itemCount: state.items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final punch = state.items[index];
                        final time = DateFormat(
                          'dd/MM/yyyy · hh:mm a',
                        ).format(punch.timestamp.toLocal());
                        return ListTile(
                          leading: Icon(
                            _iconFor(punch.type),
                            color: AppTheme.primaryColor,
                          ),
                          title: Text(punch.type.label),
                          subtitle: Text(time),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handlePunch(PunchType type) async {
    try {
      final punch = await ref
          .read(punchControllerProvider.notifier)
          .register(type);
      if (!mounted) return;
      final time = DateFormat('hh:mm a').format(punch.timestamp.toLocal());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ponche "${type.label}" registrado a las $time'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'No se pudo registrar el ponche';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final isAdmin = auth.user?.role == 'ADMIN';
    final punchState = ref.watch(punchControllerProvider);
    final attendanceState = isAdmin
        ? ref.watch(attendanceDashboardControllerProvider)
        : null;

    return DefaultTabController(
      length: isAdmin ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ponche'),
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          bottom: isAdmin
              ? const TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  tabs: [
                    Tab(text: 'Mi Ponche'),
                    Tab(text: 'Administrativo'),
                  ],
                )
              : null,
        ),
        body: isAdmin
            ? TabBarView(
                children: [
                  _buildUserTab(punchState),
                  if (attendanceState != null)
                    _buildAdminTab(attendanceState)
                  else
                    const SizedBox.shrink(),
                ],
              )
            : _buildUserTab(punchState),
      ),
    );
  }

  Widget _buildUserTab(PunchState state) {
    final lastPunch = state.items.isNotEmpty ? state.items.first : null;
    final statusLabel = _statusLabelFrom(lastPunch);
    final statusColor = _statusColorFrom(lastPunch);
    final statusIcon = _statusIconFrom(lastPunch);
    final chipForeground = statusColor.computeLuminance() > 0.75
      ? Colors.black87
      : statusColor;
    final lastStamp = lastPunch != null
      ? DateFormat('dd/MM/yyyy · hh:mm a').format(lastPunch.timestamp.toLocal())
        : null;
    final lastLabel = lastPunch != null
        ? '${lastPunch.type.label} · $lastStamp'
        : 'Todavía no hay registros';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.error != null) ...[
            Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  state.error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Estado actual',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Chip(
                backgroundColor: statusColor.withAlpha((0.15 * 255).round()),
                avatar: Icon(statusIcon, color: chipForeground),
                label: Text(
                  statusLabel,
                  style: TextStyle(
                    color: chipForeground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withAlpha((0.18 * 255).round()),
              foregroundColor: Colors.white,
              elevation: 8,
              minimumSize: const Size.fromHeight(72),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(36),
              ),
              textStyle: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            onPressed: state.creating ? null : () => _showPunchOptions(state),
            child: state.creating
                ? const SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('PONCHAR'),
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(lastLabel, style: const TextStyle(color: Colors.white70)),
              if (lastStamp != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Registrado a las $lastStamp',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: () => _showHistory(state),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text(
                'Historial',
                style: TextStyle(decoration: TextDecoration.underline),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminTab(AttendanceDashboardState state) {
    final theme = Theme.of(context);
    final summary = state.summary;
    final List<Widget> kpis = summary != null
        ? [
            _MetricCard(
              title: 'Tardes hoy',
              value: summary.totals.tardyCount.toString(),
            ),
            _MetricCard(
              title: 'Salidas tempranas hoy',
              value: summary.totals.earlyLeaveCount.toString(),
            ),
            _MetricCard(
              title: 'Horas no trabajadas',
              value: _formatHours(summary.totals.notWorkedMinutes),
            ),
            _MetricCard(
              title: 'Usuarios con incidencias',
              value: summary.users
                  .where((u) => u.aggregate.incidentsCount > 0)
                  .length
                  .toString(),
            ),
          ]
        : <Widget>[];
    final List<_IncidentItem> incidents = summary != null
        ? _extractIncidents(summary)
        : <_IncidentItem>[];

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(attendanceDashboardControllerProvider.notifier).refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FilterSection(state: state, summary: summary),
            const SizedBox(height: 18),
            if (state.loading)
              const Center(child: CircularProgressIndicator())
            else if (state.error != null)
              Text(
                state.error!,
                style: TextStyle(color: theme.colorScheme.error),
              )
            else ...[
              Wrap(spacing: 12, runSpacing: 12, children: kpis),
              const SizedBox(height: 18),
              const Text(
                'Incidencias',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (incidents.isEmpty)
                const Center(
                  child: Text('Sin incidencias para los filtros actuales'),
                )
              else
                ListView.separated(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: incidents.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final incident = incidents[index];
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      onTap: () => _showIncidentDetail(incident),
                      leading: CircleAvatar(
                        backgroundColor: _incidentColor(
                          incident.type,
                        ).withAlpha((0.2 * 255).round()),
                        child: Icon(
                          _statusIconForIncident(incident.type),
                          color: _incidentColor(incident.type),
                        ),
                      ),
                      title: Text(incident.userName),
                      subtitle: Text(_incidentSubtitle(incident)),
                      trailing: Chip(
                        label: Text(_incidentLabel(incident.type)),
                        backgroundColor: _incidentColor(
                          incident.type,
                        ).withAlpha((0.1 * 255).round()),
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _showIncidentDetail(_IncidentItem incident) {
    final controller = ref.read(attendanceDashboardControllerProvider.notifier);
    controller.loadDetail(incident.userId);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          builder: (context, controllerScroll) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 16,
              ),
              child: Consumer(
                builder: (context, ref, _) {
                  final dashboard = ref.watch(
                    attendanceDashboardControllerProvider,
                  );
                  final detail = dashboard.detail;

                  if (dashboard.detailLoading &&
                      dashboard.detailUserId == incident.userId) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (dashboard.detailError != null &&
                      dashboard.detailUserId == incident.userId) {
                    return Center(child: Text(dashboard.detailError!));
                  }
                  if (detail == null ||
                      dashboard.detailUserId != incident.userId) {
                    return const Center(
                      child: Text(
                        'Selecciona una incidencia para ver detalles',
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    controller: controllerScroll,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          detail.user.nombreCompleto,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          detail.user.email,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _MetricChip(
                              label: 'Horas trabajadas',
                              value: _formatHours(detail.totals.workedMinutes),
                            ),
                            _MetricChip(
                              label: 'Horas no trabajadas',
                              value: _formatHours(
                                detail.totals.notWorkedMinutes,
                              ),
                            ),
                            _MetricChip(
                              label: 'Tardanzas',
                              value: '${detail.totals.tardinessMinutes} min',
                            ),
                            _MetricChip(
                              label: 'Salidas tempranas',
                              value: '${detail.totals.earlyLeaveMinutes} min',
                            ),
                            _MetricChip(
                              label: 'Días incompletos',
                              value: detail.totals.incompleteDays.toString(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Días',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        ...detail.days.map((day) {
                          return Card(
                            child: ListTile(
                              title: Text(
                                DateFormat(
                                  'dd/MM/yyyy',
                                ).format(DateTime.parse(day.date)),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Entrada: ${_formatTime(day.entry)} • Salida: ${_formatTime(day.exit)}',
                                  ),
                                  Text(
                                    'Lunch: ${day.lunchMinutes} min • Permiso: ${day.permisoMinutes} min',
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                        const Text(
                          'Ponches',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ...detail.punches.map((punch) {
                          final timestamp = DateFormat(
                            'dd/MM/yyyy hh:mm a',
                          ).format(punch.timestamp.toLocal());
                          return ListTile(
                            leading: Icon(
                              _iconFor(punch.type),
                              color: AppTheme.primaryColor,
                            ),
                            title: Text(punch.type.label),
                            subtitle: Text(timestamp),
                          );
                        }),
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    ).whenComplete(() => controller.clearDetail());
  }

  IconData _statusIconFrom(PunchModel? punch) {
    switch (punch?.type) {
      case PunchType.entradaLabor:
      case PunchType.entradaAlmuerzo:
      case PunchType.entradaPermiso:
        return Icons.login;
      case PunchType.salidaLabor:
        return Icons.exit_to_app;
      case PunchType.salidaAlmuerzo:
      case PunchType.salidaPermiso:
        return Icons.pause_circle_filled;
      default:
        return Icons.circle_outlined;
    }
  }

  Color _statusColorFrom(PunchModel? punch) {
    switch (punch?.type) {
      case PunchType.entradaLabor:
      case PunchType.entradaAlmuerzo:
      case PunchType.entradaPermiso:
        return Colors.green;
      case PunchType.salidaLabor:
        return Colors.red;
      case PunchType.salidaAlmuerzo:
      case PunchType.salidaPermiso:
        return Colors.orange;
      default:
        return Colors.white;
    }
  }

  String _statusLabelFrom(PunchModel? punch) {
    switch (punch?.type) {
      case PunchType.entradaLabor:
      case PunchType.entradaAlmuerzo:
      case PunchType.entradaPermiso:
        return 'En jornada';
      case PunchType.salidaLabor:
        return 'Fuera';
      case PunchType.salidaAlmuerzo:
        return 'En almuerzo';
      case PunchType.salidaPermiso:
        return 'En permiso';
      default:
        return 'Fuera';
    }
  }

  IconData _statusIconForIncident(String type) {
    switch (type) {
      case 'TARDY':
        return Icons.timelapse;
      case 'EARLY':
        return Icons.access_time;
      case 'INCOMPLETE':
        return Icons.warning;
      default:
        return Icons.info;
    }
  }

  Color _incidentColor(String type) {
    switch (type) {
      case 'TARDY':
        return Colors.orange;
      case 'EARLY':
        return Colors.blueGrey;
      case 'INCOMPLETE':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _incidentLabel(String type) {
    switch (type) {
      case 'TARDY':
        return 'Tarde';
      case 'EARLY':
        return 'Temprano';
      case 'INCOMPLETE':
        return 'Incompleto';
      default:
        return 'Incidencia';
    }
  }

  String _incidentSubtitle(_IncidentItem incident) {
    final sign = incident.type == 'EARLY' ? '-' : '+';
    final timeLabel = incident.timestamp != null
        ? DateFormat('dd/MM/yyyy · hh:mm a').format(
            incident.timestamp!.toLocal(),
          )
        : incident.dayLabel;
    return '$sign${incident.minutes} min · $timeLabel';
  }

  List<_IncidentItem> _extractIncidents(AttendanceSummaryModel summary) {
    final items = <_IncidentItem>[];
    for (final user in summary.users) {
      for (final day in user.days) {
        for (final incident in day.incidents) {
          final timestamp = incident.referenceTime ?? day.entry ?? day.exit;
          items.add(
            _IncidentItem(
              userId: user.user.id,
              userName: user.user.nombreCompleto,
              role: user.user.role,
              type: incident.type,
              minutes: incident.minutes,
              timestamp: timestamp,
              dayLabel: day.date,
            ),
          );
        }
      }
    }
    items.sort((a, b) {
      final order = _incidentPriority(b.type) - _incidentPriority(a.type);
      if (order != 0) return order;
      final minuteDiff = b.minutes - a.minutes;
      if (minuteDiff != 0) return minuteDiff;
      final left = b.timestamp ?? DateTime(0);
      final right = a.timestamp ?? DateTime(0);
      return left.compareTo(right);
    });
    return items;
  }

  int _incidentPriority(String type) {
    switch (type) {
      case 'TARDY':
        return 3;
      case 'EARLY':
        return 2;
      case 'INCOMPLETE':
        return 1;
      default:
        return 0;
    }
  }

  String _formatHours(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return '${hours}h ${remainder}m';
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return DateFormat('hh:mm a').format(time.toLocal());
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;

  const _MetricCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
  }
}

class _FilterSection extends ConsumerWidget {
  const _FilterSection({required this.state, required this.summary});

  final AttendanceDashboardState state;
  final AttendanceSummaryModel? summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(attendanceDashboardControllerProvider.notifier);
    final userItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
      if (summary != null)
        ...summary!.users.map(
          (entry) => DropdownMenuItem<String?>(
            value: entry.user.id,
            child: Text(entry.user.nombreCompleto),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AttendanceFilterOption.values.map((option) {
            final label = option == AttendanceFilterOption.today
                ? 'Hoy'
                : option == AttendanceFilterOption.yesterday
                ? 'Ayer'
                : 'Intervalo';
            return ChoiceChip(
              label: Text(label),
              selected: state.filterOption == option,
              onSelected: (_) => controller.applyFilters(filterOption: option),
            );
          }).toList(),
        ),
        if (state.filterOption == AttendanceFilterOption.range) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              _DatePickerButton(
                label: state.customFrom != null
                    ? DateFormat('dd/MM/yyyy').format(state.customFrom!)
                    : 'Desde',
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: state.customFrom ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    controller.applyFilters(
                      filterOption: AttendanceFilterOption.range,
                      customFrom: picked,
                    );
                  }
                },
              ),
              const SizedBox(width: 8),
              _DatePickerButton(
                label: state.customTo != null
                    ? DateFormat('dd/MM/yyyy').format(state.customTo!)
                    : 'Hasta',
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: state.customTo ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    controller.applyFilters(
                      filterOption: AttendanceFilterOption.range,
                      customTo: picked,
                    );
                  }
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: state.selectedUserId,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por usuario',
                ),
                items: userItems,
                onChanged: (val) =>
                    controller.applyFilters(selectedUserId: val),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () =>
                  controller.applyFilters(incidentsOnly: !state.incidentsOnly),
              child: Text(
                state.incidentsOnly ? 'Ver todo' : 'Solo incidencias',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DatePickerButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DatePickerButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
        ),
        child: Text(label, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _IncidentItem {
  final String userId;
  final String userName;
  final String role;
  final String type;
  final int minutes;
  final DateTime? timestamp;
  final String dayLabel;

  _IncidentItem({
    required this.userId,
    required this.userName,
    required this.role,
    required this.type,
    required this.minutes,
    required this.timestamp,
    required this.dayLabel,
  });
}

IconData _iconFor(PunchType type) {
  return switch (type) {
    PunchType.entradaLabor => Icons.login,
    PunchType.salidaLabor => Icons.exit_to_app,
    PunchType.salidaPermiso => Icons.meeting_room_outlined,
    PunchType.entradaPermiso => Icons.door_back_door,
    PunchType.salidaAlmuerzo => Icons.fastfood,
    PunchType.entradaAlmuerzo => Icons.restaurant,
  };
}
