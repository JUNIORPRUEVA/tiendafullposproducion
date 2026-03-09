import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/errors/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/punch_model.dart';
import './application/punch_controller.dart';
import './data/punch_repository.dart';
import './models/attendance_models.dart';

class PoncheScreen extends ConsumerStatefulWidget {
  const PoncheScreen({super.key});

  @override
  ConsumerState<PoncheScreen> createState() => _PoncheScreenState();
}

class _PoncheScreenState extends ConsumerState<PoncheScreen> {
  Future<AttendanceDetailModel>? _attendanceFuture;

  @override
  void initState() {
    super.initState();
    _attendanceFuture = _loadAttendanceDetail();
  }

  Future<AttendanceDetailModel> _loadAttendanceDetail() {
    return ref.read(punchRepositoryProvider).fetchMyAttendanceDetail();
  }

  String _formatMinutes(int minutes) {
    final sign = minutes < 0 ? '-' : '';
    final absolute = minutes.abs();
    final hours = absolute ~/ 60;
    final remainingMinutes = absolute % 60;
    return '$sign${hours}h ${remainingMinutes.toString().padLeft(2, '0')}m';
  }

  Color _balanceColor(int minutes) {
    if (minutes > 0) return Colors.green.shade700;
    if (minutes < 0) return Colors.red.shade700;
    return Colors.blueGrey;
  }

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
    setState(() {
      _attendanceFuture = _loadAttendanceDetail();
    });
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
                Expanded(
                  child: FutureBuilder<AttendanceDetailModel>(
                    future: _attendanceFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        return Center(
                          child: Text(
                            'No se pudo cargar el balance de horas.',
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        );
                      }

                      final detail = snapshot.data!;
                      final totals = detail.totals;
                      final balanceColor = _balanceColor(totals.balanceMinutes);
                      final recentPunches = detail.punches.take(12).toList();

                      if (detail.days.isEmpty && recentPunches.isEmpty) {
                        return const Center(
                          child: Text('Aún no hay ponches registrados'),
                        );
                      }

                      return ListView(
                        controller: controller,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _AttendanceSummaryTile(
                                  label: 'Horas a favor',
                                  value: _formatMinutes(totals.favorableMinutes),
                                  color: Colors.green.shade700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _AttendanceSummaryTile(
                                  label: 'Horas en contra',
                                  value: _formatMinutes(totals.unfavorableMinutes),
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _AttendanceSummaryTile(
                                  label: 'Balance neto',
                                  value: _formatMinutes(totals.balanceMinutes),
                                  color: balanceColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _AttendanceSummaryTile(
                                  label: 'Horas laboradas',
                                  value: _formatMinutes(totals.workedMinutes),
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Balance por día',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          ...detail.days.map(
                            (day) => _AttendanceDayCard(
                              day: day,
                              formatMinutes: _formatMinutes,
                              balanceColor: _balanceColor(day.balanceMinutes),
                            ),
                          ),
                          if (recentPunches.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Últimos registros',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            ...recentPunches.map(
                              (punch) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  _iconFor(punch.type),
                                  color: AppTheme.primaryColor,
                                ),
                                title: Text(punch.type.label),
                                subtitle: Text(
                                  DateFormat(
                                    'dd/MM/yyyy · hh:mm a',
                                  ).format(punch.timestamp.toLocal()),
                                ),
                              ),
                            ),
                          ],
                        ],
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
      setState(() {
        _attendanceFuture = _loadAttendanceDetail();
      });
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
    final punchState = ref.watch(punchControllerProvider);

    return Scaffold(
      drawer: AppDrawer(currentUser: auth.user),
      appBar: AppBar(
        title: const Text('Ponche'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _buildUserTab(punchState),
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
        ? DateFormat(
            'dd/MM/yyyy · hh:mm a',
          ).format(lastPunch.timestamp.toLocal())
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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
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
                    backgroundColor: statusColor.withAlpha(
                      (0.15 * 255).round(),
                    ),
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
                onPressed: state.creating
                    ? null
                    : () => _showPunchOptions(state),
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
                  Text(
                    lastLabel,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (lastStamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Registrado a las $lastStamp',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
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
        ),
      ),
    );
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
}

class _AttendanceSummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AttendanceSummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceDayCard extends StatelessWidget {
  final AttendanceDayMetrics day;
  final String Function(int minutes) formatMinutes;
  final Color balanceColor;

  const _AttendanceDayCard({
    required this.day,
    required this.formatMinutes,
    required this.balanceColor,
  });

  @override
  Widget build(BuildContext context) {
    final dateText = day.date.isEmpty
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy').format(DateTime.parse(day.date));
    final entryText = day.entry == null
        ? '---'
        : DateFormat('hh:mm a').format(day.entry!.toLocal());
    final exitText = day.exit == null
        ? '---'
        : DateFormat('hh:mm a').format(day.exit!.toLocal());
    final label = day.balanceMinutes > 0
        ? 'A favor'
        : day.balanceMinutes < 0
        ? 'En contra'
        : 'Al día';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    dateText,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: balanceColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$label: ${formatMinutes(day.balanceMinutes)}',
                    style: TextStyle(
                      color: balanceColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Entrada: $entryText · Salida: $exitText'),
            const SizedBox(height: 4),
            Text(
              'Laborado: ${formatMinutes(day.workedMinutesNet ?? 0)} · A favor: ${formatMinutes(day.favorableMinutes)} · En contra: ${formatMinutes(day.unfavorableMinutes)}',
            ),
            if (day.tardinessMinutes > 0 || day.earlyLeaveMinutes > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Tardanza: ${formatMinutes(day.tardinessMinutes)} · Salida temprana: ${formatMinutes(day.earlyLeaveMinutes)}',
                  style: TextStyle(color: Colors.orange.shade800),
                ),
              ),
            if (day.incomplete)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Jornada incompleta',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
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
