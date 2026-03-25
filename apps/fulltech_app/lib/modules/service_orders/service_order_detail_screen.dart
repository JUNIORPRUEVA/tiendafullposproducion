import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import 'application/service_order_detail_controller.dart';
import 'service_order_models.dart';
import 'widgets/client_location_card.dart';
import 'widgets/evidence_item_widget.dart';

class ServiceOrderDetailScreen extends ConsumerWidget {
  const ServiceOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = serviceOrderDetailControllerProvider(orderId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final order = state.order;
    final pendingUploads =
        order?.evidences.where((item) => item.isPendingUpload).length ?? 0;
    final currentUser = ref.watch(authStateProvider).user;
    final currentUserId = currentUser?.id ?? '';
    final role = currentUser?.appRole ?? AppRole.unknown;
    final canSeeTechnicalArea = role.isTechnician || role.isAdmin;
    final canEditOrder =
      order != null && (role.isAdmin || currentUserId == order.createdById);

    return Scaffold(
      appBar: AppBar(
        leading: AppNavigator.maybeBackButton(
          context,
          fallbackRoute: Routes.serviceOrders,
        ),
        title: const Text('Detalle de orden'),
        actions: [
          if (canEditOrder)
            IconButton(
              onPressed: state.loading || state.working
                  ? null
                  : () async {
                      final updated = await context.push<bool>(
                        Routes.serviceOrderCreate,
                        extra: ServiceOrderCreateArgs(editSource: order),
                      );
                      if (updated == true) {
                        await controller.refresh();
                        if (!context.mounted) return;
                        await AppFeedback.showInfo(
                          context,
                          'Orden actualizada',
                        );
                      }
                    },
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar orden',
            ),
          IconButton(
            onPressed: state.loading || state.working
                ? null
                : controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: order == null
              ? _DetailWarmupShell(message: state.error)
              : RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ListView(
                    key: ValueKey(order.id),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
                    children: [
                      _HeroHeader(
                        order: order,
                        clientName: state.client?.nombre,
                      ),
                      const SizedBox(height: 20),
                      if (state.actionError != null) ...[
                        _MessageBanner(message: state.actionError!),
                        const SizedBox(height: 16),
                      ],
                      SectionCard(
                        icon: Icons.tune_rounded,
                        title: 'Estado operativo',
                        subtitle:
                            'Actualiza el avance de la orden y revisa su contexto operativo.',
                        trailing: canSeeTechnicalArea
                            ? FilledButton.tonalIcon(
                                onPressed: state.working
                                    ? null
                                    : () => _editOperationalNotes(
                                        context,
                                        ref,
                                        provider,
                                      ),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(Icons.edit_note_rounded),
                                label: const Text('Gestionar orden'),
                              )
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<ServiceOrderStatus>(
                              initialValue: order.status,
                              decoration: const InputDecoration(
                                labelText: 'Estado',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  [
                                        order.status,
                                        ...order.status.allowedNextStatuses,
                                      ]
                                      .fold<List<ServiceOrderStatus>>([], (
                                        acc,
                                        status,
                                      ) {
                                        if (!acc.contains(status)) {
                                          acc.add(status);
                                        }
                                        return acc;
                                      })
                                      .map(
                                        (status) =>
                                            DropdownMenuItem<
                                              ServiceOrderStatus
                                            >(
                                              value: status,
                                              child: Text(status.label),
                                            ),
                                      )
                                      .toList(growable: false),
                              onChanged: state.working
                                  ? null
                                  : (value) async {
                                      if (value == null ||
                                          value == order.status) {
                                        return;
                                      }

                                      try {
                                        await controller.updateStatus(value);
                                        if (!context.mounted) return;
                                        await AppFeedback.showInfo(
                                          context,
                                          'Estado actualizado',
                                        );
                                      } catch (_) {
                                        if (!context.mounted) return;
                                        await AppFeedback.showError(
                                          context,
                                          ref.read(provider).actionError ??
                                              'No se pudo actualizar el estado',
                                        );
                                      }
                                    },
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _MetaPill(
                                  icon: Icons.person_outline,
                                  text: state.client?.nombre ?? order.clientId,
                                ),
                                _MetaPill(
                                  icon: Icons.build_outlined,
                                  text: order.serviceType.label,
                                ),
                                _MetaPill(
                                  icon: Icons.category_outlined,
                                  text: order.category.label,
                                ),
                              ],
                            ),
                            if (state.client != null) ...[
                              const SizedBox(height: 16),
                              ClientLocationCard(
                                client: state.client,
                                title: 'Ubicacion del cliente',
                              ),
                            ],
                            if (canSeeTechnicalArea) ...[
                              const SizedBox(height: 16),
                              _ReadOnlyField(
                                label: 'Nota técnica',
                                value: order.technicalNote,
                              ),
                              const SizedBox(height: 12),
                              _ReadOnlyField(
                                label: 'Requisitos extra',
                                value: order.extraRequirements,
                              ),
                              const SizedBox(height: 12),
                              _ReadOnlyField(
                                label: 'Técnico asignado',
                                value: order.assignedToId == null
                                    ? null
                                    : state
                                              .usersById[order.assignedToId!]
                                              ?.nombreCompleto ??
                                          order.assignedToId,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SectionCard(
                        icon: Icons.forum_rounded,
                        title: 'Referencia',
                        subtitle:
                            'Información base y contexto compartido para preparar el trabajo.',
                        child: order.referenceItems.isEmpty
                            ? const _EmptySectionState(
                                icon: Icons.chat_bubble_outline_rounded,
                                title: 'Sin referencia aún',
                                message:
                                    'Todavía no se han cargado referencias para esta orden.',
                              )
                            : Column(
                                children: order.referenceItems
                                    .asMap()
                                    .entries
                                    .map(
                                      (entry) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: _FadeSlideIn(
                                          delayMs: 40 * entry.key,
                                          child: EvidenceCard(
                                            evidence: entry.value,
                                            variant:
                                                EvidenceCardVariant.reference,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                      ),
                      const SizedBox(height: 18),
                      SectionCard(
                        icon: Icons.hardware_rounded,
                        title: 'Evidencia técnica',
                        subtitle:
                            'Archivos y notas del trabajo ejecutado en campo.',
                        trailing: canSeeTechnicalArea
                            ? MenuAnchor(
                                menuChildren: [
                                  MenuItemButton(
                                    onPressed: () => _addTextEvidence(
                                      context,
                                      ref,
                                      provider,
                                    ),
                                    child: const Text('Agregar texto'),
                                  ),
                                  MenuItemButton(
                                    onPressed: () => _addImageEvidence(
                                      context,
                                      ref,
                                      provider,
                                    ),
                                    child: const Text('Subir imagen'),
                                  ),
                                  MenuItemButton(
                                    onPressed: () => _addVideoEvidence(
                                      context,
                                      ref,
                                      provider,
                                    ),
                                    child: const Text('Subir video'),
                                  ),
                                ],
                                builder: (context, menuController, child) {
                                  return OutlinedButton.icon(
                                    onPressed: state.working
                                        ? null
                                        : () {
                                            if (menuController.isOpen) {
                                              menuController.close();
                                            } else {
                                              menuController.open();
                                            }
                                          },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.add_photo_alternate_outlined,
                                    ),
                                    label: const Text('Nueva evidencia'),
                                  );
                                },
                              )
                            : null,
                        child: order.technicalEvidenceItems.isEmpty
                            ? const _EmptySectionState(
                                icon: Icons.camera_alt_outlined,
                                title: 'Sin evidencia técnica',
                                message:
                                    'Agrega archivos del trabajo cuando el técnico empiece a documentar la visita.',
                              )
                            : Column(
                                children: order.technicalEvidenceItems
                                    .asMap()
                                    .entries
                                    .map(
                                      (entry) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: _FadeSlideIn(
                                          delayMs: 40 * entry.key,
                                          child: EvidenceCard(
                                            evidence: entry.value,
                                            variant:
                                                EvidenceCardVariant.technical,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                      ),
                      const SizedBox(height: 18),
                      if (pendingUploads > 0) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                pendingUploads == 1
                                    ? '1 archivo subiendose en segundo plano...'
                                    : '$pendingUploads archivos subiendose en segundo plano...',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                      SectionCard(
                        icon: Icons.description_outlined,
                        title: 'Reporte técnico',
                        subtitle:
                            'Resumen final del trabajo realizado en la orden.',
                        trailing: canSeeTechnicalArea
                            ? FilledButton.tonalIcon(
                                onPressed: state.working
                                    ? null
                                    : () => _addReport(context, ref, provider),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(Icons.note_add_outlined),
                                label: const Text('Agregar reporte'),
                              )
                            : null,
                        child: order.reports.isEmpty
                            ? const _EmptySectionState(
                                icon: Icons.note_alt_outlined,
                                title: 'Sin reporte aún',
                                message:
                                    'Cuando el trabajo esté documentado, el reporte aparecerá aquí.',
                              )
                            : Column(
                                children: order.reports
                                    .asMap()
                                    .entries
                                    .map(
                                      (entry) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: _FadeSlideIn(
                                          delayMs: 50 * entry.key,
                                          child: _ReportCard(
                                            report: entry.value,
                                            authorName: state
                                                .usersById[entry
                                                    .value
                                                    .createdById]
                                                ?.nombreCompleto,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
      bottomNavigationBar: order == null || !order.isCloneSourceAllowed
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: FilledButton.icon(
                  onPressed: () async {
                    final created = await context.push<bool>(
                      Routes.serviceOrderCreate,
                      extra: ServiceOrderCreateArgs(cloneSource: order),
                    );
                    if (created == true) {
                      if (!context.mounted) return;
                      context.pop(true);
                    }
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Crear nueva orden desde esta'),
                ),
              ),
            ),
    );
  }
}

Future<void> _addTextEvidence(
  BuildContext context,
  WidgetRef ref,
  AutoDisposeStateNotifierProvider<
    ServiceOrderDetailController,
    ServiceOrderDetailState
  >
  provider,
) async {
  final text = await _promptMultilineInput(
    context,
    title: 'Nueva evidencia en texto',
    hintText:
        'Describe el trabajo realizado, hallazgos o avances del servicio.',
    confirmLabel: 'Guardar',
  );
  if (text == null || text.trim().isEmpty) {
    return;
  }

  try {
    await ref.read(provider.notifier).addTextEvidence(text.trim());
    if (!context.mounted) return;
    await AppFeedback.showInfo(context, 'Evidencia agregada');
  } catch (_) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      ref.read(provider).actionError ?? 'No se pudo guardar la evidencia',
    );
  }
}

Future<void> _addImageEvidence(
  BuildContext context,
  WidgetRef ref,
  AutoDisposeStateNotifierProvider<
    ServiceOrderDetailController,
    ServiceOrderDetailState
  >
  provider,
) async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: false,
    type: FileType.image,
    withData: kIsWeb,
  );
  final file = result?.files.singleOrNull;
  if (file == null) {
    return;
  }

  final bytes = file.bytes;
  final path = kIsWeb ? null : file.path;
  if ((bytes == null || bytes.isEmpty) &&
      (path == null || path.trim().isEmpty)) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      'No se pudo leer la imagen seleccionada',
    );
    return;
  }

  try {
    await ref
        .read(provider.notifier)
        .addImageEvidence(
          bytes: bytes ?? const <int>[],
          fileName: file.name,
          path: path,
        );
    if (!context.mounted) return;
    await AppFeedback.showInfo(
      context,
      'Imagen agregada. Se esta subiendo en segundo plano.',
    );
  } catch (_) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      ref.read(provider).actionError ?? 'No se pudo subir la imagen',
    );
  }
}

Future<void> _addVideoEvidence(
  BuildContext context,
  WidgetRef ref,
  AutoDisposeStateNotifierProvider<
    ServiceOrderDetailController,
    ServiceOrderDetailState
  >
  provider,
) async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: false,
    type: FileType.video,
    withData: kIsWeb,
  );
  final file = result?.files.singleOrNull;
  if (file == null) {
    return;
  }

  final bytes = file.bytes;
  final path = kIsWeb ? null : file.path;
  if ((bytes == null || bytes.isEmpty) &&
      (path == null || path.trim().isEmpty)) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      'No se pudo leer el video seleccionado',
    );
    return;
  }

  try {
    await ref
        .read(provider.notifier)
        .addVideoEvidence(fileName: file.name, bytes: bytes, path: path);
    if (!context.mounted) return;
    await AppFeedback.showInfo(
      context,
      'Video agregado. Se esta subiendo en segundo plano.',
    );
  } catch (_) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      ref.read(provider).actionError ?? 'No se pudo subir el video',
    );
  }
}

Future<void> _addReport(
  BuildContext context,
  WidgetRef ref,
  AutoDisposeStateNotifierProvider<
    ServiceOrderDetailController,
    ServiceOrderDetailState
  >
  provider,
) async {
  final reportType = await _pickReportType(context);
  if (reportType == null) {
    return;
  }
  if (!context.mounted) return;

  final report = await _promptMultilineInput(
    context,
    title: reportType.label,
    hintText: _reportHintText(reportType),
    confirmLabel: 'Guardar reporte',
  );
  if (report == null || report.trim().isEmpty) {
    return;
  }

  try {
    await ref.read(provider.notifier).addReport(reportType, report.trim());
    if (!context.mounted) return;
    await AppFeedback.showInfo(context, 'Reporte agregado');
  } catch (_) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      ref.read(provider).actionError ?? 'No se pudo guardar el reporte',
    );
  }
}

Future<ServiceReportType?> _pickReportType(BuildContext context) {
  return showModalBottomSheet<ServiceReportType>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tipo de reporte',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Selecciona el tipo de reporte que se agregará a esta orden.',
                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              _ReportTypeAction(
                type: ServiceReportType.requerimientoCliente,
                subtitle:
                    'Para solicitudes o requerimientos adicionales del cliente',
                icon: Icons.assignment_ind_outlined,
                onTap: () => Navigator.pop(
                  sheetContext,
                  ServiceReportType.requerimientoCliente,
                ),
              ),
              const SizedBox(height: 10),
              _ReportTypeAction(
                type: ServiceReportType.servicioFinalizado,
                subtitle:
                    'Para documentar el cierre o resultado final del servicio',
                icon: Icons.task_alt_outlined,
                onTap: () => Navigator.pop(
                  sheetContext,
                  ServiceReportType.servicioFinalizado,
                ),
              ),
              const SizedBox(height: 10),
              _ReportTypeAction(
                type: ServiceReportType.otros,
                subtitle:
                    'Para otras observaciones importantes relacionadas con la orden',
                icon: Icons.notes_outlined,
                onTap: () =>
                    Navigator.pop(sheetContext, ServiceReportType.otros),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _reportHintText(ServiceReportType type) {
  switch (type) {
    case ServiceReportType.requerimientoCliente:
      return 'Describe el requerimiento del cliente, solicitud adicional o necesidad levantada';
    case ServiceReportType.servicioFinalizado:
      return 'Resume el trabajo finalizado, materiales usados y resultado entregado';
    case ServiceReportType.otros:
      return 'Describe cualquier otra observación, hallazgo o nota importante';
  }
}

Future<String?> _promptMultilineInput(
  BuildContext context, {
  required String title,
  required String hintText,
  required String confirmLabel,
}) async {
  final formKey = GlobalKey<FormState>();
  var draftValue = '';
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            initialValue: draftValue,
            minLines: 4,
            maxLines: 7,
            autofocus: true,
            decoration: InputDecoration(
              hintText: hintText,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => draftValue = value,
            validator: (value) {
              if ((value ?? '').trim().isEmpty) {
                return 'Este campo es obligatorio';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) {
                return;
              }
              Navigator.of(dialogContext).pop(draftValue.trim());
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result;
}

Future<Map<String, String?>?> _promptOperationalNotes(
  BuildContext context, {
  required String? initialTechnicalNote,
  required String? initialExtraRequirements,
}) async {
  final technicalController = TextEditingController(
    text: initialTechnicalNote ?? '',
  );
  final requirementsController = TextEditingController(
    text: initialExtraRequirements ?? '',
  );

  final result = await showDialog<Map<String, String?>>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Gestionar orden'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: technicalController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Nota técnica',
                  hintText: 'Detalle del trabajo técnico o seguimiento interno',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: requirementsController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Solicitudes del cliente',
                  hintText:
                      'Requisitos, observaciones o solicitudes adicionales',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop({
                'technicalNote': technicalController.text.trim(),
                'extraRequirements': requirementsController.text.trim(),
              });
            },
            child: const Text('Guardar cambios'),
          ),
        ],
      );
    },
  );

  technicalController.dispose();
  requirementsController.dispose();
  return result;
}

Future<void> _editOperationalNotes(
  BuildContext context,
  WidgetRef ref,
  AutoDisposeStateNotifierProvider<
    ServiceOrderDetailController,
    ServiceOrderDetailState
  >
  provider,
) async {
  final state = ref.read(provider);
  final order = state.order;
  if (order == null) {
    return;
  }

  final payload = await _promptOperationalNotes(
    context,
    initialTechnicalNote: order.technicalNote,
    initialExtraRequirements: order.extraRequirements,
  );
  if (payload == null) {
    return;
  }

  try {
    await ref
        .read(provider.notifier)
        .updateOperationalDetails(
          technicalNote: payload['technicalNote'],
          extraRequirements: payload['extraRequirements'],
        );
    if (!context.mounted) return;
    await AppFeedback.showInfo(context, 'Orden actualizada');
  } catch (_) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      ref.read(provider).actionError ??
          'No se pudieron guardar los cambios operativos',
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.order, required this.clientName});

  final ServiceOrderModel order;
  final String? clientName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF102542), Color(0xFF0F7B6C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22102542),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  clientName ?? order.clientId,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              StatusBadge(status: order.status, inverted: true),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Detalle operativo de la orden para seguimiento en campo.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderTag(
                icon: Icons.category_outlined,
                text: order.category.label,
              ),
              _HeaderTag(
                icon: Icons.build_circle_outlined,
                text: order.serviceType.label,
              ),
              _HeaderTag(
                icon: Icons.schedule_rounded,
                text: DateFormat(
                  'dd/MM/yyyy h:mm a',
                  'es_DO',
                ).format(order.createdAt.toLocal()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.inverted = false});

  final ServiceOrderStatus status;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: inverted
            ? Colors.white.withValues(alpha: 0.16)
            : status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: inverted
              ? Colors.white.withValues(alpha: 0.24)
              : status.color.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: inverted ? Colors.white : status.color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _HeaderTag extends StatelessWidget {
  const _HeaderTag({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    required this.icon,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102542).withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if ((subtitle ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _DetailWarmupShell extends StatelessWidget {
  const _DetailWarmupShell({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF102542), Color(0xFF0F7B6C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22102542),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Detalle operativo',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message ??
                    'La vista local del modulo se prepara mientras la sincronizacion continua en segundo plano.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.84),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _PlaceholderChip(label: 'Sincronizacion silenciosa'),
                  _PlaceholderChip(label: 'Datos locales'),
                  _PlaceholderChip(label: 'Actualizacion en segundo plano'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _DetailPlaceholderCard(
          title: 'Estado operativo',
          subtitle: 'Recuperando la informacion principal de la orden.',
          icon: Icons.tune_rounded,
          lineCount: 3,
        ),
        const SizedBox(height: 18),
        const _DetailPlaceholderCard(
          title: 'Referencia',
          subtitle: 'Mostrando el contexto disponible sin bloquear la vista.',
          icon: Icons.forum_rounded,
          lineCount: 3,
        ),
        const SizedBox(height: 18),
        const _DetailPlaceholderCard(
          title: 'Reporte tecnico',
          subtitle: 'Los datos nuevos llegan cuando termina la sincronizacion.',
          icon: Icons.description_outlined,
          lineCount: 2,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'La sincronizacion sigue en segundo plano para no interrumpir el trabajo.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DetailPlaceholderCard extends StatelessWidget {
  const _DetailPlaceholderCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.lineCount,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int lineCount;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      child: Column(
        children: List.generate(
          lineCount,
          (index) => Padding(
            padding: EdgeInsets.only(bottom: index == lineCount - 1 ? 0 : 12),
            child: _PlaceholderLine(
              widthFactor: index == lineCount - 1 ? 0.56 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderLine extends StatelessWidget {
  const _PlaceholderLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFF102542).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _PlaceholderChip extends StatelessWidget {
  const _PlaceholderChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

enum EvidenceCardVariant { reference, technical }

class EvidenceCard extends StatelessWidget {
  const EvidenceCard({
    super.key,
    required this.evidence,
    required this.variant,
  });

  final ServiceOrderEvidenceModel evidence;
  final EvidenceCardVariant variant;

  @override
  Widget build(BuildContext context) {
    final tint = variant == EvidenceCardVariant.reference
        ? const Color(0xFFF3F5FB)
        : Colors.white;
    final borderColor = variant == EvidenceCardVariant.reference
        ? const Color(0xFFE0E7F3)
        : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.8);
    final iconColor = evidence.type.isText
        ? const Color(0xFF5B5F97)
        : evidence.type.isImage
        ? const Color(0xFF0F8C6B)
        : const Color(0xFF2563EB);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    evidence.type.isText
                        ? Icons.notes_rounded
                        : evidence.type.isImage
                        ? Icons.image_outlined
                        : Icons.videocam_outlined,
                    size: 18,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    evidence.type.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  DateFormat(
                    'dd/MM h:mm a',
                    'es_DO',
                  ).format(evidence.createdAt.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (evidence.isPendingUpload) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ] else if (evidence.hasUploadError) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            EvidenceItemWidget(
              type: evidence.type,
              url: evidence.type.isText ? null : evidence.content,
              text: evidence.type.isText ? evidence.content : null,
              createdAt: evidence.createdAt,
              localPath: evidence.localPath,
              previewBytes: evidence.previewBytes,
              fileName: evidence.fileName,
              showHeader: false,
              showSurface: false,
            ),
            if (evidence.isPendingUpload) ...[
              const SizedBox(height: 8),
              Text(
                'Subiendo al servidor en segundo plano...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else if (evidence.hasUploadError) ...[
              const SizedBox(height: 8),
              Text(
                'La subida fallo. Puedes reintentar agregando el archivo nuevamente.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            (value ?? '').trim().isEmpty ? 'Sin información' : value!,
          ),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 8), Text(text)],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.authorName});

  final ServiceOrderReportModel report;
  final String? authorName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAF9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE9E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: report.type.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: report.type.color.withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              report.type.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: report.type.color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            report.report,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${authorName ?? report.createdById} · ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(report.createdAt.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportTypeAction extends StatelessWidget {
  const _ReportTypeAction({
    required this.type,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final ServiceReportType type;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            color: theme.colorScheme.surfaceContainerLow,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: type.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: type.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message),
    );
  }
}

class _EmptySectionState extends StatelessWidget {
  const _EmptySectionState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, innerChild) {
        final dy = (1 - value) * 10;
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: Offset(0, dy), child: innerChild),
        );
      },
      child: child,
    );
  }
}
