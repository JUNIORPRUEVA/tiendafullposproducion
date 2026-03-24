import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_feedback.dart';
import '../service_order_models.dart';
import '../application/service_order_card_actions_controller.dart';

enum _EvidencePickType { image, video }

/// Modal que muestra 3 opciones de acciones rápidas para una orden.
/// 
/// 1. Cambiar estado
/// 2. Agregar evidencia (imagen/video)
/// 3. Agregar reporte técnico
Future<void> showServiceOrderQuickActionsModal({
  required BuildContext context,
  required WidgetRef ref,
  required String orderId,
  required ServiceOrderModel order,
  required VoidCallback onOrderUpdated,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return _ServiceOrderQuickActionsSheet(
        orderId: orderId,
        order: order,
        parentContext: context,
        onOrderUpdated: onOrderUpdated,
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
  });

  final String orderId;
  final ServiceOrderModel order;
  final BuildContext parentContext;
  final VoidCallback onOrderUpdated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serviceOrderCardActionsProvider(orderId));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final actionCards = <Widget>[
      _ActionButton(
        icon: Icons.sync_alt_rounded,
        label: 'Cambiar estado',
        subtitle: 'Actualiza el avance real de la orden.',
        isHighlighted: true,
        badgeText: 'Prioritario',
        isLoading: state.loading,
        onTap: state.loading ? null : () => _changeStatus(context, ref),
      ),
      _ActionButton(
        icon: Icons.upload_file_outlined,
        label: 'Subir evidencia',
        subtitle: 'Carga fotos o videos del antes y después.',
        isLoading: state.loading,
        onTap: state.loading ? null : () => _addEvidence(context, ref),
      ),
      _ActionButton(
        icon: Icons.description_outlined,
        label: 'Reporte técnico',
        subtitle: 'Anota observaciones y requerimientos del cliente.',
        isLoading: state.loading,
        onTap: state.loading ? null : () => _addReport(context, ref),
      ),
    ];

    return SafeArea(
      child: SizedBox(
        height: screenHeight * 0.9,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B1220), Color(0xFF13233A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: const Color(0xFF1F3A5F)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F0B1220),
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
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: const Color(0xFF22D3EE).withValues(alpha: 0.16),
                            border: Border.all(
                              color: const Color(0xFF22D3EE).withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Icon(
                            Icons.verified_outlined,
                            color: Color(0xFF67E8F9),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Gestión técnica',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Administra la orden, documenta la ejecución y deja constancia clara del servicio realizado.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.86),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (state.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.rule_folder_outlined,
                            color: colorScheme.primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Evidencia requerida',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Sigue estas instrucciones de forma exacta para evitar confusiones.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _InstructionBullet(text: 'Pre-instalacion: suba 1 a 2 fotos o 1 video.'),
                    const SizedBox(height: 6),
                    const _InstructionBullet(text: 'Post-instalacion: suba 1 a 2 videos y tambien 3 a 5 fotos.'),
                    const SizedBox(height: 6),
                    const _InstructionBullet(text: 'Orden obligatorio: primero pre-instalacion y luego post-instalacion.'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: actionCards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => actionCards[index],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeStatus(BuildContext sheetContext, WidgetRef ref) async {
    final statuses = [
      order.status,
      ...order.status.allowedNextStatuses,
    ].fold<List<ServiceOrderStatus>>([], (acc, item) {
      if (!acc.contains(item)) acc.add(item);
      return acc;
    });

    if (!sheetContext.mounted) return;

    final selected = await showModalBottomSheet<ServiceOrderStatus>(
      context: sheetContext,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (modalContext) {
        final theme = Theme.of(modalContext);
        final colorScheme = theme.colorScheme;
        final screenHeight = MediaQuery.sizeOf(modalContext).height;

        return SafeArea(
          child: SizedBox(
            height: screenHeight * 0.9,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cambiar estado',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Selecciona el estado que representa el avance real de esta orden.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: statuses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final status = statuses[index];
                        final isSelected = status == order.status;
                        return _StatusSelectionTile(
                          status: status,
                          isCurrent: isSelected,
                          onTap: () => Navigator.pop(modalContext, status),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected == null || selected == order.status) {
      return;
    }

    try {
      await ref
          .read(serviceOrderCardActionsProvider(orderId).notifier)
          .changeStatus(selected);

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);

      if (!parentContext.mounted) return;
      await AppFeedback.showInfo(parentContext, 'Estado actualizado');
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

  Future<void> _addEvidence(BuildContext sheetContext, WidgetRef ref) async {
    final selectedType = await _pickEvidenceType(sheetContext);
    if (selectedType == null) {
      return;
    }

    final isVideo = selectedType == _EvidencePickType.video;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: isVideo
          ? ['mp4', 'mov', 'webm', 'mkv']
          : ['jpg', 'jpeg', 'png', 'webp'],
      withData: kIsWeb,
    );

    if (result?.files.firstOrNull == null) {
      return;
    }

    final file = result!.files.first;
    final bytes = file.bytes;
    final path = kIsWeb ? null : file.path;

    if ((bytes == null || bytes.isEmpty) && (path == null || path.trim().isEmpty)) {
      if (!sheetContext.mounted) return;
      await AppFeedback.showError(
        sheetContext,
        'No se pudo leer el archivo',
      );
      return;
    }

    try {
      if (isVideo) {
        await ref
            .read(serviceOrderCardActionsProvider(orderId).notifier)
            .addVideoEvidence(
              fileName: file.name,
              bytes: bytes ?? const <int>[],
              path: path,
            );
      } else {
        await ref
            .read(serviceOrderCardActionsProvider(orderId).notifier)
            .addImageEvidence(
              fileName: file.name,
              bytes: bytes ?? const <int>[],
              path: path,
            );
      }

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);

      if (!parentContext.mounted) return;
      await AppFeedback.showInfo(
        parentContext,
        isVideo ? 'Video agregado correctamente' : 'Imagen agregada correctamente',
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

  Future<void> _addReport(BuildContext sheetContext, WidgetRef ref) async {
    final reportType = await _pickReportType(sheetContext);
    if (reportType == null) {
      return;
    }
    if (!sheetContext.mounted) return;

    final reportText = await _promptMultilineInput(
      sheetContext,
      title: reportType.label,
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
      await AppFeedback.showInfo(parentContext, 'Reporte guardado');
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

  static Future<_EvidencePickType?> _pickEvidenceType(BuildContext context) {
    return showModalBottomSheet<_EvidencePickType>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (modalContext) {
        final theme = Theme.of(modalContext);
        final colorScheme = theme.colorScheme;
        final screenHeight = MediaQuery.sizeOf(modalContext).height;

        return SafeArea(
          child: SizedBox(
            height: screenHeight * 0.9,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tipo de evidencia',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Selecciona el tipo de archivo que vas a cargar y sigue estas instrucciones simples.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InstructionBullet(text: 'Pre-instalacion: 1 a 2 fotos o 1 video.'),
                        SizedBox(height: 6),
                        _InstructionBullet(text: 'Post-instalacion: 1 a 2 videos y tambien 3 a 5 fotos.'),
                        SizedBox(height: 6),
                        _InstructionBullet(text: 'Orden obligatorio: primero pre-instalacion y luego post-instalacion.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _EvidenceTypeButton(
                    icon: Icons.image_outlined,
                    title: 'Subir imagen',
                    subtitle: 'Usa esta opción para fotos del antes, proceso y resultado final',
                    onTap: () => Navigator.pop(modalContext, _EvidencePickType.image),
                  ),
                  const SizedBox(height: 10),
                  _EvidenceTypeButton(
                    icon: Icons.videocam_outlined,
                    title: 'Subir video',
                    subtitle: 'Usa esta opción para recorridos, funcionamiento o pruebas del sistema',
                    onTap: () => Navigator.pop(modalContext, _EvidencePickType.video),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<ServiceReportType?> _pickReportType(BuildContext context) {
    return showModalBottomSheet<ServiceReportType>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (modalContext) {
        final theme = Theme.of(modalContext);
        final colorScheme = theme.colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tipo de reporte',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Selecciona el tipo de reporte que vas a registrar en la orden.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                _EvidenceTypeButton(
                  icon: Icons.assignment_ind_outlined,
                  title: ServiceReportType.requerimientoCliente.label,
                  subtitle: 'Para solicitudes o requerimientos adicionales del cliente',
                  onTap: () => Navigator.pop(
                    modalContext,
                    ServiceReportType.requerimientoCliente,
                  ),
                ),
                const SizedBox(height: 10),
                _EvidenceTypeButton(
                  icon: Icons.task_alt_outlined,
                  title: ServiceReportType.servicioFinalizado.label,
                  subtitle: 'Para documentar la ejecución final del servicio',
                  onTap: () => Navigator.pop(
                    modalContext,
                    ServiceReportType.servicioFinalizado,
                  ),
                ),
                const SizedBox(height: 10),
                _EvidenceTypeButton(
                  icon: Icons.notes_outlined,
                  title: ServiceReportType.otros.label,
                  subtitle: 'Para cualquier otra observación relevante de la orden',
                  onTap: () => Navigator.pop(
                    modalContext,
                    ServiceReportType.otros,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

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
                            _InstructionBullet(text: 'Detalle qué se hizo en la visita técnica.'),
                            SizedBox(height: 6),
                            _InstructionBullet(text: 'Anote requerimientos extra del cliente o solicitudes especiales.'),
                            SizedBox(height: 6),
                            _InstructionBullet(text: 'Registre levantamiento, materiales faltantes o pendientes detectados.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: TextFormField(
                          controller: controller,
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
                                Navigator.pop(modalContext, controller.text.trim());
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

    controller.dispose();
    return result;
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isLoading,
    required this.onTap,
    this.isHighlighted = false,
    this.badgeText,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool isLoading;
  final VoidCallback? onTap;
  final bool isHighlighted;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onTap != null;
    final cardColor = isHighlighted
        ? const Color(0xFF0EA5E9).withValues(alpha: 0.09)
        : colorScheme.primary.withValues(alpha: 0.06);
    final borderColor = isHighlighted
        ? const Color(0xFF0284C7).withValues(alpha: 0.45)
        : colorScheme.primary.withValues(alpha: 0.12);
    final iconContainerColor = isHighlighted
        ? const Color(0xFF0369A1).withValues(alpha: 0.18)
        : colorScheme.primary.withValues(alpha: 0.12);
    final iconColor = isHighlighted ? const Color(0xFF075985) : colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled && !isLoading ? onTap : null,
        child: Ink(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
            ),
            boxShadow: isHighlighted
                ? const [
                    BoxShadow(
                      color: Color(0x290EA5E9),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconContainerColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: isLoading
                      ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(
                            iconColor,
                          ),
                        ),
                      )
                      : Icon(
                        icon,
                        color: iconColor,
                        size: 20,
                      ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (badgeText != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFF0284C7).withValues(alpha: 0.32),
                              ),
                            ),
                            child: Text(
                              badgeText!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF075985),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (enabled)
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 17,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidenceTypeButton extends StatelessWidget {
  const _EvidenceTypeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
            color: colorScheme.surfaceContainerLow,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant,
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

class _StatusSelectionTile extends StatelessWidget {
  const _StatusSelectionTile({
    required this.status,
    required this.isCurrent,
    required this.onTap,
  });

  final ServiceOrderStatus status;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrent
                  ? status.color.withValues(alpha: 0.38)
                  : colorScheme.outlineVariant,
            ),
            color: isCurrent
                ? status.color.withValues(alpha: 0.10)
                : colorScheme.surfaceContainerLow,
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: status.color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _statusDescription(status),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Actual',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: status.color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _statusDescription(ServiceOrderStatus status) {
    switch (status) {
      case ServiceOrderStatus.pendiente:
        return 'La orden fue creada y todavía no se ha iniciado el trabajo.';
      case ServiceOrderStatus.enProceso:
        return 'El técnico ya inició la ejecución o está trabajando en sitio.';
      case ServiceOrderStatus.finalizado:
        return 'El trabajo quedó completado y documentado correctamente.';
      case ServiceOrderStatus.cancelado:
        return 'La orden no continuará por cancelación o cierre sin ejecución.';
    }
  }
}
