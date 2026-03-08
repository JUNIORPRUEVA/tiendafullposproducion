import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/error_banner.dart';
import '../../../../features/contabilidad/widgets/app_card.dart';
import '../../application/work_scheduling_admin_controller.dart';
import '../../application/work_scheduling_week_controller.dart';
import '../../data/work_scheduling_repository.dart';
import '../../horarios_models.dart';
import '../widgets/section_header.dart';
import '../widgets/work_status_pill.dart';
import '../widgets/work_status_style.dart';

class WorkSchedulingAdminExceptionsPage extends ConsumerWidget {
  const WorkSchedulingAdminExceptionsPage({super.key});

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
        SectionHeader(
          title: 'Excepciones',
          subtitle: 'Vacaciones, permisos, festivos, bloqueos.',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Nueva',
                onPressed: adminState.loading
                    ? null
                    : () => _openExceptionEditor(context, ref, weekStartIso),
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: adminState.loading ? null : refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (adminState.error != null) ...[
          ErrorBanner(message: adminState.error!),
          const SizedBox(height: 10),
        ],
        if (adminState.exceptions.isEmpty)
          AppCard(
            child: Text(
              'No hay excepciones cargadas para esta semana.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...adminState.exceptions.map((e) {
            final pill = workStatusStyleForRequestState(
              'approved',
              Theme.of(context).colorScheme,
            );

            return AppCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              child: InkWell(
                onTap: adminState.loading
                    ? null
                    : () => _openExceptionEditor(
                        context,
                        ref,
                        weekStartIso,
                        existing: e,
                      ),
                borderRadius: BorderRadius.circular(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${e.type} • ${e.dateFrom} → ${e.dateTo}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${e.userName ?? 'GLOBAL'}${(e.note ?? '').trim().isEmpty ? '' : ' • ${e.note}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    WorkStatusPill(style: pill, compact: true),
                    const SizedBox(width: 6),
                    IconButton(
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
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
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
                  ],
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
    DateTime from = existing != null
        ? parseDateOnly(existing.dateFrom)
        : parseDateOnly(weekStartIso);
    DateTime to = existing != null
        ? parseDateOnly(existing.dateTo)
        : parseDateOnly(weekStartIso);
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
              title: Text(
                existing == null ? 'Nueva excepción' : 'Editar excepción',
              ),
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
