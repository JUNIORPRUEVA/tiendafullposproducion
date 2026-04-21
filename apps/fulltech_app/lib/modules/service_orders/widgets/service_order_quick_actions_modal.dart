import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/utils/safe_url_launcher.dart';
import '../service_order_models.dart';
import '../application/service_order_card_actions_controller.dart';
import 'service_order_status_confirmation_dialog.dart';

enum _EvidencePickType { image, video }

enum _ActionTone { primary, secondary, neutral }

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
  ServiceOrderQuickActionsConfig actionConfig =
      const ServiceOrderQuickActionsConfig(),
}) async {
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
  });

  final String orderId;
  final ServiceOrderModel order;
  final BuildContext parentContext;
  final VoidCallback onOrderUpdated;
  final ServiceOrderQuickActionsConfig actionConfig;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serviceOrderCardActionsProvider(orderId));
    final currentUser = ref.watch(authStateProvider).user;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final targetWidth = screenSize.width >= 900
        ? 336.0
        : screenSize.width >= 600
        ? 322.0
        : (screenSize.width * 0.82).clamp(286.0, 332.0);
    final canConfirmOrder =
        currentUser?.appRole.isTechnician == true &&
        order.status == ServiceOrderStatus.pendiente &&
        (order.assignedToId == null || order.assignedToId == currentUser?.id);
    final canMarkInProgress =
        order.status != ServiceOrderStatus.enProceso &&
        order.status
            .nextStatusesForRole(canFinalizeDirectly: true)
            .contains(ServiceOrderStatus.enProceso);
    final canMarkFinalized =
        order.status != ServiceOrderStatus.finalizado &&
        order.status
            .nextStatusesForRole(canFinalizeDirectly: true)
            .contains(ServiceOrderStatus.finalizado);
    final actionCards = <Widget>[
      if (canConfirmOrder)
        _ActionButton(
          icon: Icons.check_circle_outline_rounded,
          label: 'Confirmar',
          tone: _ActionTone.primary,
          isLoading: state.loading,
          onTap: state.loading ? null : () => _confirmOrder(context, ref),
        ),
      if (canMarkInProgress)
        _ActionButton(
          icon: Icons.play_circle_outline_rounded,
          label: 'En proceso',
          tone: _ActionTone.primary,
          isLoading: state.loading,
          onTap: state.loading
              ? null
              : () => _changeStatusDirect(
                  context,
                  ref,
                  ServiceOrderStatus.enProceso,
                  successMessage: 'Orden marcada en proceso',
                ),
        ),
      if (canMarkFinalized)
        _ActionButton(
          icon: Icons.task_alt_rounded,
          label: 'Finalizar',
          tone: _ActionTone.primary,
          isLoading: state.loading,
          onTap: state.loading
              ? null
              : () => _changeStatusDirect(
                  context,
                  ref,
                  ServiceOrderStatus.finalizado,
                  successMessage: 'Orden marcada finalizada',
                ),
        ),
      _ActionButton(
        icon: Icons.description_outlined,
        label: 'Reporte final',
        tone: _ActionTone.secondary,
        isLoading: state.loading,
        onTap: state.loading ? null : () => _addFinalReport(context, ref),
      ),
      _ActionButton(
        icon: Icons.videocam_outlined,
        label: 'Video',
        tone: _ActionTone.secondary,
        isLoading: state.loading,
        onTap: state.loading
            ? null
            : () => _addEvidence(context, ref, _EvidencePickType.video),
      ),
      _ActionButton(
        icon: Icons.image_outlined,
        label: 'Imagen',
        tone: _ActionTone.secondary,
        isLoading: state.loading,
        onTap: state.loading
            ? null
            : () => _addEvidence(context, ref, _EvidencePickType.image),
      ),
      if (actionConfig.clientCallUri != null)
        _ActionButton(
          icon: Icons.call_outlined,
          label: 'Llamar cliente',
          isLoading: state.loading,
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
          onTap: () => _openExternalAction(
            context,
            actionConfig.clientWhatsAppUri!,
            copiedMessage: 'No se pudo abrir WhatsApp. Enlace copiado.',
          ),
        ),
      if (actionConfig.locationUri != null)
        _ActionButton(
          icon: Icons.location_searching_rounded,
          label: 'Ir al GPS',
          isLoading: state.loading,
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
          onTap: () => _openExternalAction(
            context,
            actionConfig.supportConversationUri!,
            copiedMessage:
                'No se pudo abrir servicio al cliente. Enlace copiado.',
          ),
        ),
    ];

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
                    for (
                      var index = 0;
                      index < actionCards.length;
                      index++
                    ) ...[
                      actionCards[index],
                      if (index < actionCards.length - 1)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            10,
                            (actionCards[index] as _ActionButton).tone !=
                                    (actionCards[index + 1] as _ActionButton)
                                        .tone
                                ? 4
                                : 0,
                            10,
                            (actionCards[index] as _ActionButton).tone !=
                                    (actionCards[index + 1] as _ActionButton)
                                        .tone
                                ? 4
                                : 0,
                          ),
                          child: Divider(
                            height: 1,
                            thickness:
                                (actionCards[index] as _ActionButton).tone !=
                                    (actionCards[index + 1] as _ActionButton)
                                        .tone
                                ? 0.95
                                : 0.65,
                            color:
                                (actionCards[index] as _ActionButton).tone !=
                                    (actionCards[index + 1] as _ActionButton)
                                        .tone
                                ? colorScheme.outlineVariant.withValues(
                                    alpha: 0.54,
                                  )
                                : colorScheme.outlineVariant.withValues(
                                    alpha: 0.22,
                                  ),
                          ),
                        ),
                    ],
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
  }) async {
    if (selected == order.status) {
      return;
    }

    try {
      final didChange = await showServiceOrderStatusConfirmationDialog(
        context: sheetContext,
        status: selected,
        onConfirm: () => ref
            .read(serviceOrderCardActionsProvider(orderId).notifier)
            .changeStatus(selected),
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

  Future<void> _confirmOrder(BuildContext sheetContext, WidgetRef ref) async {
    try {
      await ref
          .read(serviceOrderCardActionsProvider(orderId).notifier)
          .confirmOrder();

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);

      if (!parentContext.mounted) return;
      await AppFeedback.showInfo(parentContext, 'Orden confirmada');
      onOrderUpdated();
    } catch (_) {
      if (!sheetContext.mounted) return;
      final error = ref.read(serviceOrderCardActionsProvider(orderId)).error;
      await AppFeedback.showError(
        sheetContext,
        error ?? 'No se pudo confirmar la orden',
      );
    }
  }

  Future<void> _addEvidence(
    BuildContext sheetContext,
    WidgetRef ref,
    _EvidencePickType selectedType,
  ) async {
    final isVideo = selectedType == _EvidencePickType.video;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: !isVideo,
      type: FileType.custom,
      allowedExtensions: isVideo
          ? ['mp4', 'mov', 'webm', 'mkv']
          : ['jpg', 'jpeg', 'png', 'webp'],
      withData: kIsWeb,
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
      title: 'Reporte final',
      hintText: _reportHintText(reportType),
      confirmLabel: 'Guardar reporte',
    );

    if (reportText == null || reportText.trim().isEmpty) {
      return;
    }

    try {
      await ref
          .read(serviceOrderCardActionsProvider(orderId).notifier)
          .addTechnicalReport(reportType, reportText);

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

  Future<void> _openExternalAction(
    BuildContext sheetContext,
    Uri uri, {
    required String copiedMessage,
  }) {
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

  static Future<String?> _promptMultilineInput(
    BuildContext context, {
    required String title,
    required String hintText,
    required String confirmLabel,
  }) async {
    final formKey = GlobalKey<FormState>();
    var draftValue = '';

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (modalContext) {
        final theme = Theme.of(modalContext);
        final colorScheme = theme.colorScheme;
        final screenHeight = MediaQuery.sizeOf(modalContext).height;
        final bottomInset = MediaQuery.viewInsetsOf(modalContext).bottom;

        return SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SizedBox(
              height: screenHeight * 0.9,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Form(
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
                      const SizedBox(height: 6),
                      Text(
                        'Anote requerimiento extra del cliente, solicitudes, levantamiento y cualquier observación relevante del servicio.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colorScheme.outlineVariant),
                          color: colorScheme.surfaceContainerLow,
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _InstructionBullet(
                              text: 'Detalle qué se hizo en la visita técnica.',
                            ),
                            SizedBox(height: 6),
                            _InstructionBullet(
                              text:
                                  'Anote requerimientos extra del cliente o solicitudes especiales.',
                            ),
                            SizedBox(height: 6),
                            _InstructionBullet(
                              text:
                                  'Registre levantamiento, materiales faltantes o pendientes detectados.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: TextFormField(
                          initialValue: draftValue,
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
                          onChanged: (value) => draftValue = value,
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
                              onPressed: () => Navigator.pop(modalContext),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                if (!formKey.currentState!.validate()) {
                                  return;
                                }
                                Navigator.pop(modalContext, draftValue.trim());
                              },
                              child: Text(confirmLabel),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    return result;
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isLoading,
    required this.onTap,
    this.tone = _ActionTone.neutral,
  });

  final IconData icon;
  final String label;
  final bool isLoading;
  final VoidCallback? onTap;
  final _ActionTone tone;

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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled && !isLoading ? onTap : null,
        child: Ink(
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 2.5,
                height: 26,
                decoration: BoxDecoration(
                  color: isPrimary
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
                    letterSpacing: -0.1,
                    color: enabled
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: leadingColor.withValues(alpha: enabled ? 0.72 : 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstructionBullet extends StatelessWidget {
  const _InstructionBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
