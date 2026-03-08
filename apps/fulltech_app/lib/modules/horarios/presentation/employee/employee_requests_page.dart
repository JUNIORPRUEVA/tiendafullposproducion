import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/contabilidad/widgets/app_card.dart';
import '../../application/work_scheduling_requests_controller.dart';
import '../../horarios_models.dart';
import '../widgets/section_header.dart';
import '../widgets/work_status_pill.dart';
import '../widgets/work_status_style.dart';

class WorkSchedulingEmployeeRequestsPage extends ConsumerWidget {
  const WorkSchedulingEmployeeRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workSchedulingRequestsControllerProvider);
    final controller = ref.read(
      workSchedulingRequestsControllerProvider.notifier,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionHeader(
          title: 'Mis solicitudes',
          subtitle:
              'Solicita cambios o permisos. (UI lista para integrar backend)',
          trailing: FilledButton.icon(
            onPressed: () => _openCreate(context, controller),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nueva'),
          ),
        ),
        const SizedBox(height: 12),
        if (state.items.isEmpty)
          const AppCard(child: Text('No tienes solicitudes aún.'))
        else
          ...state.items.map((r) {
            final style = workStatusStyleForRequestState(
              r.status,
              Theme.of(context).colorScheme,
            );
            return AppCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.typeLabel,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text('Actual: ${r.fromDate} → Solicitado: ${r.toDate}'),
                        const SizedBox(height: 6),
                        Text(
                          r.reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  WorkStatusPill(style: style, compact: false),
                ],
              ),
            );
          }),
      ],
    );
  }

  Future<void> _openCreate(BuildContext context, dynamic controller) async {
    String type = 'day_off_change';
    DateTime from = DateTime.now();
    DateTime to = DateTime.now().add(const Duration(days: 1));
    final reasonCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Nueva solicitud'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: type,
                      items: const [
                        DropdownMenuItem(
                          value: 'day_off_change',
                          child: Text('Cambio de día libre'),
                        ),
                        DropdownMenuItem(
                          value: 'special_leave',
                          child: Text('Permiso especial'),
                        ),
                        DropdownMenuItem(
                          value: 'block_date',
                          child: Text('Bloqueo de fecha'),
                        ),
                      ],
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
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: from,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => from = picked);
                              }
                            },
                            child: Text('Actual: ${dateOnly(from)}'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: to,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => to = picked);
                              }
                            },
                            child: Text('Solicitado: ${dateOnly(to)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Motivo',
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
                  onPressed: () {
                    final reason = reasonCtrl.text.trim();
                    if (reason.isEmpty) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Escribe un motivo.')),
                      );
                      return;
                    }
                    controller.create(
                      type: type,
                      fromDate: dateOnly(from),
                      toDate: dateOnly(to),
                      reason: reason,
                    );
                    Navigator.pop(ctx);
                  },
                  child: const Text('Enviar'),
                ),
              ],
            );
          },
        );
      },
    );

    reasonCtrl.dispose();
  }
}
