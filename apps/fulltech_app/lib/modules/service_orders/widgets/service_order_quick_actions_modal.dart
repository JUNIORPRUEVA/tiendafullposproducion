import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/ai_assistant/domain/models/ai_chat_context.dart';
import '../../../core/ai_assistant/domain/services/ai_assistant_service.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/utils/safe_url_launcher.dart';
import '../service_order_models.dart';
import '../application/service_order_card_actions_controller.dart';
import 'service_order_status_confirmation_dialog.dart';

enum _EvidencePickType { image, video }

enum _ActionTone { primary, secondary, neutral }

enum ServiceOrderQuickActionsPresentation { bottomSheet, mobileRightPanel }

class ServiceOrderQuickActionsConfig {
  const ServiceOrderQuickActionsConfig({
    this.clientCallUri,
    this.clientWhatsAppUri,
    this.locationUri,
    this.sellerConversationUri,
    this.supportConversationUri,
  });

  final Uri? clientCallUri;
  final Uri? clientWhatsAppUri;
  final Uri? locationUri;
  final Uri? sellerConversationUri;
  final Uri? supportConversationUri;
}

Future<void> showServiceOrderQuickActionsModal({
  required BuildContext context,
  required WidgetRef ref,
  required String orderId,
  required ServiceOrderModel order,
  required VoidCallback onOrderUpdated,
  ServiceOrderQuickActionsPresentation presentation =
      ServiceOrderQuickActionsPresentation.bottomSheet,
  ServiceOrderQuickActionsConfig actionConfig =
      const ServiceOrderQuickActionsConfig(),
}) async {
  if (presentation == ServiceOrderQuickActionsPresentation.mobileRightPanel) {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Panel de gestión',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (sheetContext, animation, secondaryAnimation) {
        return _ServiceOrderQuickActionsSheet(
          orderId: orderId,
          order: order,
          parentContext: context,
          onOrderUpdated: onOrderUpdated,
          actionConfig: actionConfig,
          presentation: presentation,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuart,
          reverseCurve: Curves.easeInQuart,
        );
        final scale = Tween<double>(
          begin: 0.965,
          end: 1,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          ),
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: scale,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.24, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (sheetContext) {
      return _ServiceOrderQuickActionsSheet(
        orderId: orderId,
        order: order,
        parentContext: context,
        onOrderUpdated: onOrderUpdated,
        actionConfig: actionConfig,
        presentation: presentation,
      );
    },
  );
}

class _ServiceOrderQuickActionsSheet extends ConsumerWidget {
  const _ServiceOrderQuickActionsSheet({
    required this.orderId,
    required this.order,
    required this.parentContext,
    required this.onOrderUpdated,
    required this.actionConfig,
    required this.presentation,
  });

  final String orderId;
  final ServiceOrderModel order;
  final BuildContext parentContext;
  final VoidCallback onOrderUpdated;
  final ServiceOrderQuickActionsConfig actionConfig;
  final ServiceOrderQuickActionsPresentation presentation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serviceOrderCardActionsProvider(orderId));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final isMobileRightPanel =
        presentation == ServiceOrderQuickActionsPresentation.mobileRightPanel;
    final targetWidth = screenSize.width >= 900
        ? 336.0
        : screenSize.width >= 600
        ? 322.0
        : (screenSize.width * 0.82).clamp(286.0, 332.0);
    final isTechnicianMobilePanel = isMobileRightPanel;
    final allowedStatuses = order.status.nextStatusesForRole(
      canFinalizeDirectly: true,
    );
    final statusSequence = isTechnicianMobilePanel
        ? <ServiceOrderStatus>[
            ServiceOrderStatus.enProceso,
            ServiceOrderStatus.enPausa,
            ServiceOrderStatus.finalizado,
          ]
        : <ServiceOrderStatus>[
            ServiceOrderStatus.pendiente,
            ServiceOrderStatus.enProceso,
            ServiceOrderStatus.enPausa,
            ServiceOrderStatus.finalizado,
            ServiceOrderStatus.pospuesta,
            ServiceOrderStatus.cancelado,
          ];
    final visibleStatusOptions = statusSequence.where((status) {
      return status == order.status || allowedStatuses.contains(status);
    }).toList(growable: false);
    final quickActionCards = <_ActionButton>[
      _ActionButton(
        icon: Icons.description_outlined,
        label: 'Reporte final',
        tone: _ActionTone.secondary,
        isLoading: state.loading,
        minHeight: 56,
        onTap: state.loading ? null : () => _addFinalReport(context, ref),
      ),
      _ActionButton(
        icon: Icons.videocam_outlined,
        label: 'Video',
        tone: _ActionTone.secondary,
        isLoading: state.loading,
        minHeight: 56,
        onTap: state.loading
            ? null
            : () => _addEvidence(context, ref, _EvidencePickType.video),
      ),
      _ActionButton(
        icon: Icons.image_outlined,
        label: 'Imagen',
        tone: _ActionTone.secondary,
        isLoading: state.loading,
        minHeight: 56,
        onTap: state.loading
            ? null
            : () => _addEvidence(context, ref, _EvidencePickType.image),
      ),
      if (isTechnicianMobilePanel)
        _ActionButton(
          icon: Icons.notes_rounded,
          label: 'Texto',
          tone: _ActionTone.secondary,
          isLoading: state.loading,
          minHeight: 56,
          onTap: state.loading ? null : () => _addTextEvidence(context, ref),
        ),
      if (actionConfig.clientCallUri != null)
        _ActionButton(
          icon: Icons.call_outlined,
          label: 'Llamar cliente',
          isLoading: state.loading,
          minHeight: 56,
          onTap: () => _openExternalAction(
            context,
            actionConfig.clientCallUri!,
            copiedMessage: 'No se pudo iniciar la llamada. Numero copiado.',
          ),
        ),
      if (actionConfig.clientWhatsAppUri != null)
        _ActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'WhatsApp cliente',
          isLoading: state.loading,
          minHeight: 56,
          onTap: () => _openExternalAction(
            context,
            actionConfig.clientWhatsAppUri!,
            isWhatsApp: true,
            copiedMessage: 'No se pudo abrir WhatsApp. Enlace copiado.',
          ),
        ),
      if (actionConfig.locationUri != null)
        _ActionButton(
          icon: Icons.location_searching_rounded,
          label: 'Ir al GPS',
          isLoading: state.loading,
          minHeight: 56,
          onTap: () => _openExternalAction(
            context,
            actionConfig.locationUri!,
            copiedMessage: 'No se pudo abrir el GPS. Enlace copiado.',
          ),
        ),
      if (actionConfig.sellerConversationUri != null)
        _ActionButton(
          icon: Icons.support_agent_rounded,
          label: 'Vendedor',
          isLoading: state.loading,
          minHeight: 56,
          onTap: () => _openExternalAction(
            context,
            actionConfig.sellerConversationUri!,
            copiedMessage:
                'No se pudo abrir el contacto del vendedor. Enlace copiado.',
          ),
        ),
      if (actionConfig.supportConversationUri != null)
        _ActionButton(
          icon: Icons.headset_mic_outlined,
          label: 'Servicio al cliente',
          isLoading: state.loading,
          minHeight: 56,
          onTap: () => _openExternalAction(
            context,
            actionConfig.supportConversationUri!,
            copiedMessage:
                'No se pudo abrir servicio al cliente. Enlace copiado.',
          ),
        ),
    ];
    final clientName = (order.client?.nombre ?? 'Cliente ${order.clientId}')
        .trim();
    final serviceSummary =
        '${order.serviceType.label} · ${order.category.label}';
    final scheduledAtLabel = _formatScheduledAt(order.scheduledFor);

    final statusSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.sync_alt_rounded,
          title: 'Cambiar estado',
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < visibleStatusOptions.length; index++) ...[
          _ActionButton(
            icon: _statusIcon(visibleStatusOptions[index]),
            label: visibleStatusOptions[index].label,
            tone: _statusTone(visibleStatusOptions[index]),
            isLoading: state.loading,
            selected: visibleStatusOptions[index] == order.status,
            minHeight: 58,
            onTap: state.loading || visibleStatusOptions[index] == order.status
                ? null
                : () => _changeStatusDirect(
                    context,
                    ref,
                    visibleStatusOptions[index],
                    successMessage:
                        'Orden marcada ${visibleStatusOptions[index].confirmationLabel}',
                requireDetailedConfirmation: isTechnicianMobilePanel,
                clientName: clientName,
                  ),
          ),
          if (index < visibleStatusOptions.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Divider(
                height: 1,
                thickness: 0.8,
                color: colorScheme.outlineVariant.withValues(alpha: 0.22),
              ),
            ),
        ],
      ],
    );

    final quickActionsSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.flash_on_rounded,
          title: isTechnicianMobilePanel ? 'Compromiso' : 'Acciones rápidas',
        ),
        const SizedBox(height: 8),
        if (isTechnicianMobilePanel)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.75),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Video: 1 a 2 videos · Imagen: 3 a 5 imágenes · Texto: obligatorio',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final tileWidth = (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: quickActionCards
                  .map(
                    (card) => SizedBox(
                      width: tileWidth,
                      child: card,
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ],
    );

    if (isMobileRightPanel) {
      final panelWidth = (screenSize.width * 0.82).clamp(
        screenSize.width * 0.78,
        screenSize.width * 0.86,
      );
      return SafeArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.surface,
                      colorScheme.surfaceContainerLow.withValues(alpha: 0.98),
                    ],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(26),
                    bottomLeft: Radius.circular(26),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2A102A43),
                      blurRadius: 28,
                      offset: Offset(-8, 0),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  clientName.isEmpty
                                      ? 'Cliente sin nombre'
                                      : clientName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.15,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close_rounded),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            serviceSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: order.status.color.withValues(
                                    alpha: 0.16,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  order.status.label,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: order.status.color,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (scheduledAtLabel != null)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 15,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      scheduledAtLabel,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.34),
                    ),
                    if (state.error != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(
                            alpha: 0.92,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          state.error!,
                          style: TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            statusSection,
                            const SizedBox(height: 14),
                            quickActionsSection,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Align(
          alignment: Alignment.bottomRight,
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: targetWidth),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.surface.withValues(alpha: 0.98),
                    const Color(0xFFF7FBFD),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.58),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18102542),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 34,
                        height: 3,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.58,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (state.error != null) ...[
                      Container(
                        margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(
                            alpha: 0.92,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          state.error!,
                          style: TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    statusSection,
                    const SizedBox(height: 10),
                    quickActionsSection,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeStatusDirect(
    BuildContext sheetContext,
    WidgetRef ref,
    ServiceOrderStatus selected, {
    required String successMessage,
    required bool requireDetailedConfirmation,
    required String clientName,
  }) async {
    if (selected == order.status) {
      return;
    }

    if (requireDetailedConfirmation && selected == ServiceOrderStatus.finalizado) {
      final validationMessage = _validateTechnicianCommitmentBeforeFinalize();
      if (validationMessage != null) {
        if (!sheetContext.mounted) return;
        await AppFeedback.showError(sheetContext, validationMessage);
        return;
      }
    }

    try {
      final didChange = requireDetailedConfirmation
          ? await _showTechnicianStatusConfirmDialog(
              sheetContext,
              current: order.status,
              selected: selected,
              clientName: clientName,
              onConfirm: () => ref
                  .read(serviceOrderCardActionsProvider(orderId).notifier)
                  .changeStatus(selected),
            )
          : await showServiceOrderStatusConfirmationDialog(
              context: sheetContext,
              status: selected,
              initialScheduledAt: order.scheduledFor,
              onConfirm: (scheduledAt) => ref
                  .read(serviceOrderCardActionsProvider(orderId).notifier)
                  .changeStatus(selected, scheduledAt: scheduledAt),
            );

      if (!didChange) {
        return;
      }

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);

      if (!parentContext.mounted) return;
      await AppFeedback.showInfo(parentContext, successMessage);
      onOrderUpdated();
    } catch (_) {
      if (!sheetContext.mounted) return;
      final error = ref.read(serviceOrderCardActionsProvider(orderId)).error;
      await AppFeedback.showError(
        sheetContext,
        error ?? 'No se pudo cambiar el estado',
      );
    }
  }

  Future<bool> _showTechnicianStatusConfirmDialog(
    BuildContext context, {
    required ServiceOrderStatus current,
    required ServiceOrderStatus selected,
    required String clientName,
    required Future<void> Function() onConfirm,
  }) async {
    var confirmed = false;
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> handleConfirm() async {
              if (isSubmitting) return;
              setState(() => isSubmitting = true);
              try {
                await onConfirm();
                confirmed = true;
              } finally {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              }
            }

            return AlertDialog(
              title: const Text('Confirmar cambio de estado'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Estás seguro de marcar esta orden como ${selected.confirmationLabel.toUpperCase()}?',
                  ),
                  const SizedBox(height: 10),
                  Text('Cliente: $clientName'),
                  const SizedBox(height: 4),
                  Text('Estado actual: ${current.label}'),
                  const SizedBox(height: 2),
                  Text('Estado nuevo: ${selected.label}'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: isSubmitting ? null : handleConfirm,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );

    return confirmed;
  }

  Future<void> _addEvidence(
    BuildContext sheetContext,
    WidgetRef ref,
    _EvidencePickType selectedType,
  ) async {
    final isVideo = selectedType == _EvidencePickType.video;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: !isVideo,
      type: isVideo ? FileType.video : FileType.image,
      withData: true,
    );

    final selectedFiles = result?.files ?? const <PlatformFile>[];
    if (selectedFiles.isEmpty) {
      return;
    }

    try {
      if (isVideo) {
        final file = selectedFiles.first;
        final bytes = file.bytes;
        final path = kIsWeb ? null : file.path;

        if ((bytes == null || bytes.isEmpty) &&
            (path == null || path.trim().isEmpty)) {
          if (!sheetContext.mounted) return;
          await AppFeedback.showError(
            sheetContext,
            'No se pudo leer el archivo',
          );
          return;
        }

        await ref
            .read(serviceOrderCardActionsProvider(orderId).notifier)
            .addVideoEvidence(
              fileName: file.name,
              bytes: bytes ?? const <int>[],
              path: path,
            );
      } else {
        var uploadedCount = 0;
        String? lastError;

        for (final file in selectedFiles) {
          final bytes = file.bytes;
          final path = kIsWeb ? null : file.path;

          if ((bytes == null || bytes.isEmpty) &&
              (path == null || path.trim().isEmpty)) {
            lastError = 'No se pudo leer uno de los archivos seleccionados';
            continue;
          }

          try {
            await ref
                .read(serviceOrderCardActionsProvider(orderId).notifier)
                .addImageEvidence(
                  fileName: file.name,
                  bytes: bytes ?? const <int>[],
                  path: path,
                );
            uploadedCount++;
          } catch (_) {
            lastError =
                ref.read(serviceOrderCardActionsProvider(orderId)).error ??
                'No se pudo subir una de las imagenes';
          }
        }

        if (uploadedCount == 0) {
          if (!sheetContext.mounted) return;
          await AppFeedback.showError(
            sheetContext,
            lastError ?? 'No se pudo subir ninguna imagen',
          );
          return;
        }

        if (!sheetContext.mounted) return;
        Navigator.pop(sheetContext);

        if (!parentContext.mounted) return;
        final totalSelected = selectedFiles.length;
        final uploadedMessage = uploadedCount == 1
            ? '1 imagen agregada correctamente'
            : '$uploadedCount imagenes agregadas correctamente';
        final summary = uploadedCount == totalSelected
            ? uploadedMessage
            : '$uploadedMessage. ${totalSelected - uploadedCount} no se pudieron subir.';
        await AppFeedback.showInfo(parentContext, summary);
        onOrderUpdated();
        return;
      }

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);

      if (!parentContext.mounted) return;
      await AppFeedback.showInfo(
        parentContext,
        isVideo
            ? 'Video agregado correctamente'
            : 'Imagen agregada correctamente',
      );
      onOrderUpdated();
    } catch (_) {
      if (!sheetContext.mounted) return;
      final error = ref.read(serviceOrderCardActionsProvider(orderId)).error;
      await AppFeedback.showError(
        sheetContext,
        error ?? 'No se pudo subir el archivo',
      );
    }
  }

  Future<void> _addFinalReport(BuildContext sheetContext, WidgetRef ref) async {
    const reportType = ServiceReportType.servicioFinalizado;
    if (!sheetContext.mounted) return;

    final reportText = await _promptMultilineInput(
      sheetContext,
      ref: ref,
      title: 'Reporte final',
      hintText: _reportHintText(reportType),
      confirmLabel: 'Guardar reporte',
    );

    if (reportText == null || reportText.trim().isEmpty) {
      return;
    }

    try {
      final normalizedReport = await _normalizeReportWithAi(
        ref,
        reportText,
      );

      await ref
          .read(serviceOrderCardActionsProvider(orderId).notifier)
          .addTechnicalReport(reportType, normalizedReport);

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);

      if (!parentContext.mounted) return;
      await AppFeedback.showInfo(parentContext, 'Reporte final guardado');
      onOrderUpdated();
    } catch (_) {
      if (!sheetContext.mounted) return;
      final error = ref.read(serviceOrderCardActionsProvider(orderId)).error;
      await AppFeedback.showError(
        sheetContext,
        error ?? 'No se pudo guardar el reporte',
      );
    }
  }

  Future<void> _addTextEvidence(BuildContext sheetContext, WidgetRef ref) async {
    if (!sheetContext.mounted) return;

    final textValue = await _promptMultilineInput(
      sheetContext,
      ref: ref,
      title: 'Texto de compromiso',
      hintText: 'Escribe la evidencia en texto obligatoria para completar la orden.',
      confirmLabel: 'Guardar texto',
    );

    if (textValue == null || textValue.trim().isEmpty) {
      return;
    }

    try {
        final normalizedText = await _normalizeReportWithAi(ref, textValue);

        await ref
          .read(serviceOrderCardActionsProvider(orderId).notifier)
          .addTextEvidence(normalizedText);

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);

      if (!parentContext.mounted) return;
      await AppFeedback.showInfo(parentContext, 'Texto guardado correctamente');
      onOrderUpdated();
    } catch (_) {
      if (!sheetContext.mounted) return;
      final error = ref.read(serviceOrderCardActionsProvider(orderId)).error;
      await AppFeedback.showError(
        sheetContext,
        error ?? 'No se pudo guardar el texto',
      );
    }
  }

  Future<void> _openExternalAction(
    BuildContext sheetContext,
    Uri uri, {
    bool isWhatsApp = false,
    required String copiedMessage,
  }) {
    if (isWhatsApp) {
      return safeOpenWhatsApp(sheetContext, uri, copiedMessage: copiedMessage);
    }
    return safeOpenUrl(sheetContext, uri, copiedMessage: copiedMessage);
  }

  static String _reportHintText(ServiceReportType type) {
    switch (type) {
      case ServiceReportType.requerimientoCliente:
        return 'Escribe el requerimiento del cliente, solicitud adicional o necesidad detectada';
      case ServiceReportType.servicioFinalizado:
        return 'Resume el trabajo realizado, materiales usados y resultado final del servicio';
      case ServiceReportType.otros:
        return 'Escribe cualquier observación, hallazgo o nota importante de la orden';
    }
  }

  Future<String> _normalizeReportWithAi(WidgetRef ref, String rawInput) async {
    final normalizedInput = rawInput.trim();
    if (normalizedInput.isEmpty) {
      return normalizedInput;
    }

    try {
      final aiService = ref.read(aiAssistantServiceProvider);
      final result = await aiService.chat(
        context: AiChatContext(
          module: 'service_orders',
          screenName: 'service_order_quick_actions',
          entityType: 'service_order',
          entityId: orderId,
        ),
        message:
            'Convierte este borrador en un reporte tecnico breve, claro y profesional en espanol. '
            'Mantiene solo hechos del texto, ordenalo por: Trabajo realizado, Hallazgos, Materiales/Pendientes, Resultado final. '
            'No inventes datos ni agregues saludos.\n\n'
            'Texto base:\n$normalizedInput',
        history: const [],
      );

      final aiText = result.content.trim();
      return aiText.isEmpty ? normalizedInput : aiText;
    } catch (error, stackTrace) {
      debugPrint('No se pudo normalizar reporte con IA: $error');
      debugPrint('$stackTrace');
      return normalizedInput;
    }
  }

  Future<String?> _promptMultilineInput(
    BuildContext context, {
    required WidgetRef ref,
    required String title,
    required String hintText,
    required String confirmLabel,
  }) async {
    final formKey = GlobalKey<FormState>();
    final textController = TextEditingController();
    final speech = stt.SpeechToText();
    var isListening = false;
    var isAiProcessing = false;
    var voiceSeedText = '';
    var voiceCaption = 'Toca el microfono para dictar por voz';

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (modalContext) {
        final theme = Theme.of(modalContext);
        final colorScheme = theme.colorScheme;
        final screenHeight = MediaQuery.sizeOf(modalContext).height;
        final bottomInset = MediaQuery.viewInsetsOf(modalContext).bottom;

        Future<void> stopVoice(StateSetter setModalState) async {
          if (!isListening) {
            return;
          }
          await speech.stop();
          if (!modalContext.mounted) {
            return;
          }
          setModalState(() {
            isListening = false;
            voiceCaption = 'Dictado finalizado';
          });
        }

        Future<void> startVoice(StateSetter setModalState) async {
          final available = await speech.initialize(
            onStatus: (status) {
              if (!modalContext.mounted) return;
              if (status == 'done' || status == 'notListening') {
                setModalState(() {
                  isListening = false;
                  voiceCaption = 'Dictado finalizado';
                });
              }
            },
            onError: (error) {
              if (!modalContext.mounted) return;
              setModalState(() {
                isListening = false;
                voiceCaption =
                    'No se pudo usar microfono. Puedes escribir manualmente.';
              });
            },
          );

          if (!available) {
            if (!modalContext.mounted) return;
            setModalState(() {
              voiceCaption =
                  'No hay reconocimiento de voz disponible en este dispositivo';
            });
            return;
          }

          voiceSeedText = textController.text.trim();
          setModalState(() {
            isListening = true;
            voiceCaption = 'Escuchando... habla normal y toca de nuevo para parar';
          });

          await speech.listen(
            partialResults: true,
            onResult: (result) {
              if (!modalContext.mounted) return;
              final recognized = result.recognizedWords.trim();
              if (recognized.isEmpty) {
                return;
              }

              final merged = [
                voiceSeedText,
                recognized,
              ].where((item) => item.isNotEmpty).join('\n');
              textController.value = TextEditingValue(
                text: merged,
                selection: TextSelection.collapsed(offset: merged.length),
              );
            },
          );
        }

        return SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SizedBox(
              height: screenHeight * 0.9,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: StatefulBuilder(
                  builder: (statefulContext, setModalState) {
                    return Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Habla o escribe; al guardar, la IA organiza el reporte automaticamente.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: isAiProcessing
                                      ? null
                                      : () async {
                                          if (isListening) {
                                            await stopVoice(setModalState);
                                          } else {
                                            await startVoice(setModalState);
                                          }
                                        },
                                  icon: Icon(
                                    isListening
                                        ? Icons.stop_circle_outlined
                                        : Icons.mic_none_rounded,
                                  ),
                                  label: Text(
                                    isListening ? 'Detener voz' : 'Grabar voz',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: isAiProcessing
                                      ? null
                                      : () async {
                                          final currentValue =
                                              textController.text.trim();
                                          if (currentValue.isEmpty) {
                                            return;
                                          }
                                          setModalState(() {
                                            isAiProcessing = true;
                                          });
                                          final polished =
                                              await _normalizeReportWithAi(
                                                ref,
                                                currentValue,
                                              );
                                          if (!modalContext.mounted) return;
                                          textController.value =
                                              TextEditingValue(
                                                text: polished,
                                                selection:
                                                    TextSelection.collapsed(
                                                      offset: polished.length,
                                                    ),
                                              );
                                          setModalState(() {
                                            isAiProcessing = false;
                                          });
                                        },
                                  icon: isAiProcessing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.auto_awesome_rounded),
                                  label: const Text('Ordenar IA'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            voiceCaption,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: TextFormField(
                              controller: textController,
                              minLines: null,
                              maxLines: null,
                              expands: true,
                              autofocus: true,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: InputDecoration(
                                hintText: hintText,
                                alignLabelWithHint: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                filled: true,
                                fillColor: colorScheme.surface,
                              ),
                              validator: (value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return 'Este campo es obligatorio';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await stopVoice(setModalState);
                                    if (!modalContext.mounted) return;
                                    Navigator.pop(modalContext);
                                  },
                                  child: const Text('Cancelar'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: isAiProcessing
                                      ? null
                                      : () async {
                                          if (!formKey.currentState!
                                              .validate()) {
                                            return;
                                          }
                                          await stopVoice(setModalState);
                                          setModalState(() {
                                            isAiProcessing = true;
                                          });
                                          final polished =
                                              await _normalizeReportWithAi(
                                                ref,
                                                textController.text,
                                              );
                                          if (!modalContext.mounted) return;
                                          Navigator.pop(
                                            modalContext,
                                            polished.trim(),
                                          );
                                        },
                                  child: Text(confirmLabel),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    textController.dispose();

    return result;
  }

  IconData _statusIcon(ServiceOrderStatus status) {
    switch (status) {
      case ServiceOrderStatus.pendiente:
        return Icons.schedule_send_rounded;
      case ServiceOrderStatus.enProceso:
        return Icons.play_circle_outline_rounded;
      case ServiceOrderStatus.enPausa:
        return Icons.pause_circle_outline_rounded;
      case ServiceOrderStatus.finalizado:
        return Icons.task_alt_rounded;
      case ServiceOrderStatus.pospuesta:
        return Icons.event_busy_rounded;
      case ServiceOrderStatus.cancelado:
        return Icons.cancel_outlined;
    }
  }

  _ActionTone _statusTone(ServiceOrderStatus status) {
    switch (status) {
      case ServiceOrderStatus.enProceso:
      case ServiceOrderStatus.finalizado:
        return _ActionTone.primary;
      case ServiceOrderStatus.enPausa:
      case ServiceOrderStatus.pospuesta:
        return _ActionTone.secondary;
      case ServiceOrderStatus.pendiente:
      case ServiceOrderStatus.cancelado:
        return _ActionTone.neutral;
    }
  }

  String? _formatScheduledAt(DateTime? scheduledAt) {
    if (scheduledAt == null) {
      return null;
    }
    final local = scheduledAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year} · $hour:$minute';
  }

  String? _validateTechnicianCommitmentBeforeFinalize() {
    final technicalEvidences = order.evidences
        .where((item) => item.type.isTechnicalEvidence)
        .toList(growable: false);
    final imageCount = technicalEvidences.where((item) => item.type.isImage).length;
    final videoCount = technicalEvidences.where((item) => item.type.isVideo).length;
    final hasTextEvidence = technicalEvidences.any(
      (item) => item.type.isText && item.content.trim().isNotEmpty,
    );
    final hasReportText = order.reports.any((item) => item.report.trim().isNotEmpty);

    final textComplete = hasTextEvidence || hasReportText;
    final imagesComplete = imageCount >= 3 && imageCount <= 5;
    final videosComplete = videoCount >= 1 && videoCount <= 2;

    if (textComplete && imagesComplete && videosComplete) {
      return null;
    }

    return 'Para finalizar esta orden debes completar el compromiso: texto obligatorio, 3 a 5 imágenes y 1 a 2 videos.';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isLoading,
    required this.onTap,
    this.tone = _ActionTone.neutral,
    this.selected = false,
    this.minHeight = 52,
  });

  final IconData icon;
  final String label;
  final bool isLoading;
  final VoidCallback? onTap;
  final _ActionTone tone;
  final bool selected;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onTap != null;
    final isPrimary = tone == _ActionTone.primary;
    final isSecondary = tone == _ActionTone.secondary;
    final tileColor = isPrimary
        ? const Color(0xFFF0F7FB)
        : isSecondary
        ? const Color(0xFFF8FBFD)
        : colorScheme.surface.withValues(alpha: 0.01);
    final leadingColor = isPrimary
        ? const Color(0xFF155E82)
        : isSecondary
        ? const Color(0xFF4B7E98)
        : colorScheme.primary;
    final iconContainerColor = isPrimary
        ? const Color(0xFF155E82).withValues(alpha: 0.10)
        : isSecondary
        ? const Color(0xFF4B7E98).withValues(alpha: 0.08)
        : colorScheme.primary.withValues(alpha: 0.08);
    final selectedColor = colorScheme.primary.withValues(alpha: 0.09);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled && !isLoading ? onTap : null,
        splashColor: leadingColor.withValues(alpha: 0.08),
        highlightColor: leadingColor.withValues(alpha: 0.05),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? selectedColor : tileColor,
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.26),
                    )
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 2.5,
                height: minHeight - 24,
                decoration: BoxDecoration(
                  color: selected
                      ? colorScheme.primary
                      : isPrimary
                      ? const Color(0xFF155E82)
                      : isSecondary
                      ? const Color(0xFFB7D0DE)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconContainerColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: isLoading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(leadingColor),
                          ),
                        )
                      : Icon(icon, color: leadingColor, size: 16),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: -0.1,
                    color: enabled
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              selected
                  ? Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    )
                  : Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: leadingColor.withValues(
                        alpha: enabled ? 0.72 : 0.4,
                      ),
                    ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 7),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}
