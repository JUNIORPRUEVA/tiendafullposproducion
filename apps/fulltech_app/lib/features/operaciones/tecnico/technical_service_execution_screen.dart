import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/routes.dart';
import '../operations_models.dart';
import '../presentation/status_chip.dart';
import 'technical_service_execution_controller.dart';

class TechnicalServiceExecutionScreen extends ConsumerStatefulWidget {
  final String serviceId;

  const TechnicalServiceExecutionScreen({super.key, required this.serviceId});

  @override
  ConsumerState<TechnicalServiceExecutionScreen> createState() =>
      _TechnicalServiceExecutionScreenState();
}

class _TechnicalServiceExecutionScreenState
    extends ConsumerState<TechnicalServiceExecutionScreen> {
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '—';
    final v = dt.toLocal();
    final h = v.hour.toString().padLeft(2, '0');
    final m = v.minute.toString().padLeft(2, '0');
    return '${v.day}/${v.month}/${v.year} $h:$m';
  }

  Future<void> _openAddChangeDialog(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    final typeCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final extraCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    bool clientApproved = false;

    double? parseNum(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      return double.tryParse(t.replaceAll(',', '.'));
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Agregar cambio'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tipo (ej: material, repuesto, visita)',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: extraCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Costo extra',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 6),
                StatefulBuilder(
                  builder: (context, setState) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Aprobado por cliente'),
                      value: clientApproved,
                      onChanged: (v) => setState(() => clientApproved = v),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final type = typeCtrl.text.trim();
                final desc = descCtrl.text.trim();
                await ctrl.addChange(
                  type: type,
                  description: desc,
                  quantity: parseNum(qtyCtrl.text),
                  extraCost: parseNum(extraCtrl.text),
                  clientApproved: clientApproved,
                  note: noteCtrl.text,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Agregar'),
            ),
          ],
        );
      },
    );

    typeCtrl.dispose();
    descCtrl.dispose();
    qtyCtrl.dispose();
    extraCtrl.dispose();
    noteCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(
      technicalExecutionControllerProvider(widget.serviceId),
    );
    final ctrl = ref.read(
      technicalExecutionControllerProvider(widget.serviceId).notifier,
    );

    final auth = ref.watch(authStateProvider);
    final userId = (auth.user?.id ?? '').trim();

    final service = st.service;
    if (_notesCtrl.text != st.notes) {
      _notesCtrl.text = st.notes;
      _notesCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _notesCtrl.text.length),
      );
    }

    final title = service == null
        ? 'Servicio'
        : (service.customerName.trim().isEmpty
              ? 'Servicio'
              : service.customerName.trim());

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(Routes.operacionesTecnico);
          },
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (st.saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Guardar',
              onPressed: () => ctrl.saveNow(),
              icon: const Icon(Icons.save_outlined),
            ),
        ],
      ),
      body: st.loading
          ? const Center(child: CircularProgressIndicator())
          : service == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(st.error ?? 'No se pudo cargar el servicio'),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ctrl.load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                children: [
                  if (st.error != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(st.error!),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  service.title.trim().isEmpty
                                      ? service.description
                                      : service.title,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ),
                              const SizedBox(width: 8),
                              StatusChip(
                                status: service.orderState.isEmpty
                                    ? service.status
                                    : service.orderState,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Fase: ${phaseLabel(service.currentPhase)}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(service.customerAddress),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ejecución',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => ctrl.markArrivedNow(),
                                icon: const Icon(Icons.place_outlined),
                                label: const Text('Llegada'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => ctrl.markStartedNow(),
                                icon: const Icon(
                                  Icons.play_circle_outline_rounded,
                                ),
                                label: const Text('Iniciar'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => ctrl.markFinishedNow(),
                                icon: const Icon(
                                  Icons.check_circle_outline_rounded,
                                ),
                                label: const Text('Finalizar'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text('Llegada: ${_fmtDateTime(st.arrivedAt)}'),
                          Text('Inicio: ${_fmtDateTime(st.startedAt)}'),
                          Text('Fin: ${_fmtDateTime(st.finishedAt)}'),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Aprobado por cliente'),
                            value: st.clientApproved,
                            onChanged: (v) => ctrl.toggleClientApproved(v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Notas técnicas',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _notesCtrl,
                            minLines: 3,
                            maxLines: 6,
                            onChanged: ctrl.updateNotes,
                            decoration: const InputDecoration(
                              hintText:
                                  'Escribe lo que hiciste y observaciones...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Checklist',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          if (service.steps.isEmpty)
                            const Text('Sin checklist')
                          else
                            ...service.steps.map(
                              (step) => CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(step.stepLabel),
                                value: step.isDone,
                                onChanged: (v) {
                                  if (v == null) return;
                                  ctrl.toggleStep(step, v);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Evidencias',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => ctrl.uploadEvidence(),
                                icon: const Icon(Icons.upload_file_outlined),
                                label: const Text('Subir'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (service.files.isEmpty)
                            const Text('Sin evidencias')
                          else
                            ...service.files.map(
                              (f) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.insert_drive_file_outlined,
                                ),
                                title: Text(
                                  f.fileType,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  f.fileUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Cambios / Novedades',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _openAddChangeDialog(context, ctrl),
                                icon: const Icon(Icons.add),
                                label: const Text('Agregar'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (st.changes.isEmpty)
                            const Text('Sin cambios')
                          else
                            ...st.changes.map((c) {
                              final canDelete =
                                  userId.isNotEmpty &&
                                  c.createdByUserId == userId;

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${c.type}: ${c.description}'),
                                subtitle: Text(
                                  [
                                    if (c.quantity != null)
                                      'Qty: ${c.quantity}',
                                    if (c.extraCost != null)
                                      'Extra: ${c.extraCost}',
                                    if (c.clientApproved == true) 'Aprobado',
                                    if ((c.note ?? '').trim().isNotEmpty)
                                      'Nota: ${c.note}',
                                  ].join(' • '),
                                ),
                                trailing: canDelete
                                    ? IconButton(
                                        tooltip: 'Eliminar',
                                        onPressed: () => ctrl.deleteChange(c),
                                        icon: const Icon(Icons.delete_outline),
                                      )
                                    : null,
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Historial',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          if (service.updates.isEmpty)
                            const Text('Sin historial')
                          else
                            ...service.updates
                                .take(20)
                                .map(
                                  (u) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(u.message),
                                    subtitle: Text(
                                      '${u.changedBy} • ${_fmtDateTime(u.createdAt)}',
                                    ),
                                  ),
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
}
