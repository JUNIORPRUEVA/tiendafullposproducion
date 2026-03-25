import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../cotizaciones/cotizacion_models.dart';
import 'application/service_order_detail_controller.dart';
import 'service_order_models.dart';
import 'widgets/client_location_card.dart';
import 'widgets/evidence_item_widget.dart';

class ServiceOrderDetailScreen extends ConsumerStatefulWidget {
  const ServiceOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<ServiceOrderDetailScreen> createState() =>
      _ServiceOrderDetailScreenState();
}

class _ServiceOrderDetailScreenState
    extends ConsumerState<ServiceOrderDetailScreen> {
  String? _expandedSection = 'quotation-section';

  void _toggleSection(String sectionKey) {
    setState(() {
      _expandedSection = _expandedSection == sectionKey ? null : sectionKey;
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderId = widget.orderId;
    final provider = serviceOrderDetailControllerProvider(orderId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final order = state.order;
    final pendingUploads =
        order?.evidences.where((item) => item.isPendingUpload).length ?? 0;
    final currentUser = ref.watch(authStateProvider).user;
    final currentUserId = currentUser?.id ?? '';
    final role = currentUser?.appRole ?? AppRole.unknown;
    final isAdmin = role.isAdmin;
    final canSeeTechnicalArea = role.isTechnician || role.isAdmin;
    final canEditOrder =
      order != null && (role.isAdmin || currentUserId == order.createdById);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Detalle de orden',
        fallbackRoute: Routes.serviceOrders,
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          if (isAdmin)
            IconButton(
              onPressed: state.loading || state.working || order == null
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) {
                          return AlertDialog(
                            title: const Text('Eliminar orden'),
                            content: Text(
                              'Esta acción eliminará la orden actual y no se puede deshacer.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(dialogContext).pop(false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(dialogContext).pop(true),
                                child: const Text('Eliminar'),
                              ),
                            ],
                          );
                        },
                      );
                      if (confirmed != true) return;

                      try {
                        await controller.deleteOrder();
                        if (!context.mounted) return;
                        await AppFeedback.showInfo(
                          context,
                          'Orden eliminada',
                        );
                        if (!context.mounted) return;
                        context.pop(true);
                      } catch (_) {
                        if (!context.mounted) return;
                        await AppFeedback.showError(
                          context,
                          ref.read(provider).actionError ??
                              'No se pudo eliminar la orden',
                        );
                      }
                    },
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar orden',
            ),
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
                      ExpandableSectionCard(
                        storageKey: 'client-section',
                        expanded: _expandedSection == 'client-section',
                        onToggle: () => _toggleSection('client-section'),
                        icon: Icons.person_rounded,
                        title: 'Cliente',
                        subtitle: 'Información del cliente vinculada a esta orden.',
                        collapsedSummary: _buildClientSummary(state),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_buildClientFacts(state).isNotEmpty)
                              _AdaptiveInfoGrid(items: _buildClientFacts(state)),
                            if (state.client != null) ...[
                              const SizedBox(height: 16),
                              ClientLocationCard(
                                client: state.client,
                                title: 'Ubicación del cliente',
                              ),
                            ] else if (_buildClientFacts(state).isEmpty) ...[
                              const _EmptySectionState(
                                icon: Icons.person_off_outlined,
                                title: 'Sin datos adicionales del cliente',
                                message:
                                    'La orden no tiene más información de cliente disponible para mostrar.',
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      ExpandableSectionCard(
                        storageKey: 'quotation-section',
                        expanded: _expandedSection == 'quotation-section',
                        onToggle: () => _toggleSection('quotation-section'),
                        icon: Icons.request_quote_outlined,
                        title: 'Cotización',
                        subtitle: 'Resumen de la cotización vinculada.',
                        collapsedSummary: _buildQuotationSummary(state.quotation),
                        child: state.quotation == null
                            ? const _EmptySectionState(
                                icon: Icons.receipt_long_outlined,
                                title: 'Sin cotización disponible',
                                message:
                                    'No se encontró una cotización vinculada o aún no se pudo cargar.',
                              )
                            : _QuotationSection(quotation: state.quotation!),
                      ),
                      const SizedBox(height: 18),
                      ExpandableSectionCard(
                        storageKey: 'order-section',
                        expanded: _expandedSection == 'order-section',
                        onToggle: () => _toggleSection('order-section'),
                        icon: Icons.tune_rounded,
                        title: 'Información de la orden',
                        subtitle: 'Resumen operativo y detalles completos.',
                        collapsedSummary: _buildOrderSummary(order, state),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (canSeeTechnicalArea) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.tonalIcon(
                                  onPressed: state.working
                                      ? null
                                      : () => _editOperationalNotes(
                                          context,
                                          ref,
                                          provider,
                                        ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(Icons.edit_note_rounded),
                                  label: const Text('Gestionar orden'),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _MetaPill(
                                  icon: Icons.flag_outlined,
                                  text: order.status.label,
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
                            if (_buildOrderFacts(order, state).isNotEmpty) ...[
                              const SizedBox(height: 14),
                              _AdaptiveInfoGrid(
                                items: _buildOrderFacts(order, state),
                              ),
                            ],
                            if (_hasContent(order.technicalNote)) ...[
                              const SizedBox(height: 12),
                              _ReadOnlyField(
                                label: 'Nota técnica',
                                value: order.technicalNote,
                              ),
                            ],
                            if (_hasContent(order.extraRequirements)) ...[
                              const SizedBox(height: 12),
                              _ReadOnlyField(
                                label: 'Requisitos extra',
                                value: order.extraRequirements,
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
                      ExpandableSectionCard(
                        storageKey: 'reports-section',
                        expanded: _expandedSection == 'reports-section',
                        onToggle: () => _toggleSection('reports-section'),
                        icon: Icons.description_outlined,
                        title: 'Reporte técnico',
                        subtitle: 'Resumen final del trabajo realizado.',
                        collapsedSummary: _buildReportsSummary(order.reports),
                        child: order.reports.isEmpty
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (canSeeTechnicalArea) ...[
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: FilledButton.tonalIcon(
                                        onPressed: state.working
                                            ? null
                                            : () => _addReport(
                                                context,
                                                ref,
                                                provider,
                                              ),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(Icons.note_add_outlined),
                                        label: const Text('Agregar reporte'),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  const _EmptySectionState(
                                    icon: Icons.note_alt_outlined,
                                    title: 'Sin reporte aún',
                                    message:
                                        'Cuando el trabajo esté documentado, el reporte aparecerá aquí.',
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (canSeeTechnicalArea) ...[
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: FilledButton.tonalIcon(
                                        onPressed: state.working
                                            ? null
                                            : () => _addReport(
                                                context,
                                                ref,
                                                provider,
                                              ),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(Icons.note_add_outlined),
                                        label: const Text('Agregar reporte'),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  ...order.reports
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
                                      ),
                                ],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14102542),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Orden de servicio',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _buildOrderHeadline(order, clientName),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(status: order.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Resumen principal de la orden para consulta rápida.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderTag(
                icon: Icons.confirmation_number_outlined,
                text: _shortOrderId(order.id),
              ),
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
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

class ExpandableSectionCard extends StatelessWidget {
  const ExpandableSectionCard({
    super.key,
    required this.storageKey,
    required this.expanded,
    required this.onToggle,
    required this.title,
    required this.child,
    required this.icon,
    required this.collapsedSummary,
    this.subtitle,
  });

  final String storageKey;
  final bool expanded;
  final VoidCallback onToggle;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final String collapsedSummary;

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
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Row(
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
                          if (collapsedSummary.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              collapsedSummary,
                              maxLines: expanded ? null : 2,
                              overflow: expanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: child,
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 220),
            ),
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
    if (!_hasContent(value)) {
      return const SizedBox.shrink();
    }

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
          child: Text(value!.trim()),
        ),
      ],
    );
  }
}

class _AdaptiveInfoGrid extends StatelessWidget {
  const _AdaptiveInfoGrid({required this.items});

  final List<_InfoItemData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 720 ? 3 : width >= 420 ? 2 : 1;
        final gap = 10.0;
        final itemWidth = (width - ((columns - 1) * gap)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: _InfoTile(item: item),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.item});

  final _InfoItemData item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                item.icon,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ],
      ),
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

class _QuotationSection extends StatelessWidget {
  const _QuotationSection({required this.quotation});

  final CotizacionModel quotation;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFCFDFE), Color(0xFFF4F8FC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E4F4)),
      ),
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
                      'Cotización vinculada',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Documento asociado a esta orden de servicio.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const _DocumentBadge(label: 'Cotización'),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetaPill(
                icon: Icons.badge_outlined,
                text: 'No. ${_shortQuotationId(quotation.id)}',
              ),
              _MetaPill(
                icon: Icons.schedule_rounded,
                text: DateFormat(
                  'dd/MM/yyyy h:mm a',
                  'es_DO',
                ).format(quotation.createdAt.toLocal()),
              ),
              _MetaPill(
                icon: Icons.inventory_2_outlined,
                text: '${quotation.items.length} items',
              ),
            ],
          ),
          if (_hasContent(quotation.note)) ...[
            const SizedBox(height: 16),
            _ReadOnlyField(
              label: 'Observación',
              value: quotation.note,
            ),
          ],
          const SizedBox(height: 16),
          if (quotation.items.isEmpty)
            const _EmptySectionState(
              icon: Icons.inventory_2_outlined,
              title: 'Sin items en la cotización',
              message: 'La cotización vinculada no tiene productos o servicios cargados.',
            )
          else
            Column(
              children: quotation.items
                  .asMap()
                  .entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _QuotationItemCard(
                        index: entry.key + 1,
                        item: entry.value,
                        money: money,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD7E4F4)),
            ),
            child: Column(
              children: [
                _QuotationTotalRow(
                  label: 'Subtotal',
                  value: money.format(quotation.subtotal),
                ),
                if (quotation.includeItbis) ...[
                  const SizedBox(height: 8),
                  _QuotationTotalRow(
                    label: 'ITBIS',
                    value: money.format(quotation.itbisAmount),
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1),
                ),
                _QuotationTotalRow(
                  label: 'Total',
                  value: money.format(quotation.total),
                  emphasized: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotationItemCard extends StatelessWidget {
  const _QuotationItemCard({
    required this.index,
    required this.item,
    required this.money,
  });

  final int index;
  final CotizacionItem item;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7E4F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FA),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$index',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.nombre,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetaPill(
                icon: Icons.tag_outlined,
                text: 'Cantidad ${item.qty.toStringAsFixed(item.qty % 1 == 0 ? 0 : 2)}',
              ),
              _MetaPill(
                icon: Icons.attach_money_rounded,
                text: 'Unitario ${money.format(item.unitPrice)}',
              ),
              _MetaPill(
                icon: Icons.calculate_outlined,
                text: 'Total ${money.format(item.total)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuotationTotalRow extends StatelessWidget {
  const _QuotationTotalRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final textStyle = emphasized
        ? Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          )
        : Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          );

    return Row(
      children: [
        Expanded(child: Text(label, style: textStyle)),
        Text(value, style: textStyle),
      ],
    );
  }
}

class _DocumentBadge extends StatelessWidget {
  const _DocumentBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0FA),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFC9D9EE)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF163A63),
        ),
      ),
    );
  }
}

String _buildClientSummary(ServiceOrderDetailState state) {
  final parts = <String>[];
  if (_hasContent(state.client?.telefono)) {
    parts.add(state.client!.telefono.trim());
  }
  if (_hasContent(state.client?.correo)) {
    parts.add(state.client!.correo!.trim());
  }
  if (_hasContent(state.client?.direccion)) {
    parts.add('Dirección disponible');
  }
  if (parts.isEmpty && state.client != null && _hasContent(state.client!.nombre)) {
    parts.add(state.client!.nombre.trim());
  }
  return parts.isEmpty ? 'Toca para ver detalles del cliente.' : parts.join(' · ');
}

String _buildQuotationSummary(CotizacionModel? quotation) {
  if (quotation == null) {
    return 'Sin cotización vinculada.';
  }

  final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
  return 'Total ${money.format(quotation.total)}';
}

String _buildOrderSummary(
  ServiceOrderModel order,
  ServiceOrderDetailState state,
) {
  final parts = <String>[order.status.label, order.serviceType.label];
  final technicianName = order.assignedToId == null
      ? null
      : state.usersById[order.assignedToId!]?.nombreCompleto ?? order.assignedToId;
  if (_hasContent(technicianName)) {
    parts.add(technicianName!.trim());
  }
  return parts.join(' · ');
}

String _buildReportsSummary(List<ServiceOrderReportModel> reports) {
  if (reports.isEmpty) {
    return 'Sin reportes registrados.';
  }
  if (reports.length == 1) {
    return '1 reporte registrado';
  }
  return '${reports.length} reportes registrados';
}

class _InfoItemData {
  const _InfoItemData({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

List<_InfoItemData> _buildClientFacts(ServiceOrderDetailState state) {
  final items = <_InfoItemData>[];

  if (_hasContent(state.client?.telefono)) {
    items.add(
      _InfoItemData(
        label: 'Teléfono',
        value: state.client!.telefono.trim(),
        icon: Icons.call_outlined,
      ),
    );
  }
  if (_hasContent(state.client?.correo)) {
    items.add(
      _InfoItemData(
        label: 'Correo',
        value: state.client!.correo!.trim(),
        icon: Icons.mail_outline_rounded,
      ),
    );
  }
  if (_hasContent(state.client?.direccion)) {
    items.add(
      _InfoItemData(
        label: 'Dirección',
        value: state.client!.direccion!.trim(),
        icon: Icons.home_outlined,
      ),
    );
  }

  return items;
}

List<_InfoItemData> _buildOrderFacts(
  ServiceOrderModel order,
  ServiceOrderDetailState state,
) {
  final items = <_InfoItemData>[
    _InfoItemData(
      label: 'Creada por',
      value: (state.usersById[order.createdById]?.nombreCompleto ??
              order.createdById)
          .trim(),
      icon: Icons.person_outline_rounded,
    ),
    _InfoItemData(
      label: 'Fecha de creación',
      value: DateFormat(
        'dd/MM/yyyy h:mm a',
        'es_DO',
      ).format(order.createdAt.toLocal()),
      icon: Icons.calendar_today_outlined,
    ),
    _InfoItemData(
      label: 'Última actualización',
      value: DateFormat(
        'dd/MM/yyyy h:mm a',
        'es_DO',
      ).format(order.updatedAt.toLocal()),
      icon: Icons.update_rounded,
    ),
  ];

  final technicianName = order.assignedToId == null
      ? null
      : state.usersById[order.assignedToId!]?.nombreCompleto ??
          order.assignedToId;
  if (_hasContent(technicianName)) {
    items.insert(
      1,
      _InfoItemData(
        label: 'Técnico asignado',
        value: technicianName!.trim(),
        icon: Icons.engineering_outlined,
      ),
    );
  }

  return items;
}

bool _hasContent(String? value) {
  return (value ?? '').trim().isNotEmpty;
}

String _shortQuotationId(String id) {
  final normalized = id.trim().toUpperCase();
  if (normalized.length <= 8) return normalized;
  return normalized.substring(0, 8);
}

String _shortOrderId(String id) {
  final normalized = id.trim().toUpperCase();
  if (normalized.isEmpty) return 'SIN ID';
  if (normalized.length <= 10) return normalized;
  return normalized.substring(0, 10);
}

String _buildOrderHeadline(ServiceOrderModel order, String? clientName) {
  final cleanClientName = (clientName ?? '').trim();
  if (cleanClientName.isNotEmpty) {
    return cleanClientName;
  }
  return 'Orden registrada';
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
