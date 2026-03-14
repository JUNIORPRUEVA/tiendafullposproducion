import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/error_banner.dart';
import '../../../../features/contabilidad/widgets/app_card.dart';
import '../../application/work_scheduling_admin_controller.dart';
import '../../horarios_models.dart';
import '../widgets/section_header.dart';
import '../widgets/work_avatar.dart';

class WorkSchedulingAdminEmployeesPage extends ConsumerWidget {
  const WorkSchedulingAdminEmployeesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workSchedulingAdminControllerProvider);
    final controller = ref.read(workSchedulingAdminControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionHeader(
          title: 'Empleados',
          subtitle: 'Perfiles y preferencias de asignación.',
          trailing: IconButton(
            tooltip: 'Actualizar',
            onPressed: state.loading ? null : controller.loadBasics,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: 12),
        if (state.error != null) ...[
          ErrorBanner(message: state.error!),
          const SizedBox(height: 10),
        ],
        ...state.employees.map(
          (e) => AppCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            child: InkWell(
              onTap: state.loading
                  ? null
                  : () => _openEmployeeEditor(context, ref, e),
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  WorkAvatar(name: e.nombreCompleto, photoUrl: null),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.nombreCompleto,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            if (e.blocked)
                              Text(
                                'BLOQUEADO',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.role,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.schedule.enabled
                              ? 'Asignación activa'
                              : 'Asignación desactivada',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Switch(
                    value: e.schedule.enabled,
                    onChanged: state.loading
                        ? null
                        : (v) =>
                              controller.saveEmployeeConfig(e.id, enabled: v),
                  ),
                ],
              ),
            ),
          ),
        ),
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
    final notesCtrl = TextEditingController(
      text: employee.schedule.notes ?? '',
    );

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
                  initialValue: selectedProfileId,
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
                  initialValue: fixed,
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
                  initialValue: preferred,
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
        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900)),
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
