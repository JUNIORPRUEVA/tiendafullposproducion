import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_feedback.dart';
import '../service_order_models.dart';
import '../application/service_order_card_actions_controller.dart';

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

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Acciones rápidas',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Gestiona el estado, evidencia y reportes de esta orden',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (state.error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  state.error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _ActionButton(
              icon: Icons.sync_alt_rounded,
              label: 'Cambiar estado',
              subtitle: 'Actualiza el estado operativo de la orden',
              isLoading: state.loading,
              onTap: state.loading
                  ? null
                  : () => _changeStatus(context, ref),
            ),
            const SizedBox(height: 12),
            _ActionButton(
              icon: Icons.image_outlined,
              label: 'Agregar evidencia',
              subtitle: 'Sube imagen o video del trabajo',
              isLoading: state.loading,
              onTap: state.loading
                  ? null
                  : () => _addEvidence(context, ref),
            ),
            const SizedBox(height: 12),
            _ActionButton(
              icon: Icons.description_outlined,
              label: 'Reporte técnico',
              subtitle: 'Agrega un reporte de la ejecución',
              isLoading: state.loading,
              onTap: state.loading
                  ? null
                  : () => _addReport(context, ref),
            ),
            const SizedBox(height: 8),
          ],
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

    final selected = await showDialog<ServiceOrderStatus>(
      context: sheetContext,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cambiar estado'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: statuses.map((status) {
                final isSelected = status == order.status;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(status.label),
                  trailing: isSelected ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(dialogContext, status),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
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
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'webm', 'mkv'],
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

    final isVideo = (file.extension ?? '').toLowerCase().contains(
      RegExp(r'mp4|mov|webm|mkv'),
    );

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
        isVideo
            ? 'Video agregado. Subiendo en segundo plano...'
            : 'Imagen agregada. Subiendo en segundo plano...',
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
    final reportText = await _promptMultilineInput(
      sheetContext,
      title: 'Reporte técnico',
      hintText: 'Resume el trabajo realizado, materiales usados y resultado final',
      confirmLabel: 'Guardar reporte',
    );

    if (reportText == null || reportText.trim().isEmpty) {
      return;
    }

    try {
      await ref
          .read(serviceOrderCardActionsProvider(orderId).notifier)
          .addTechnicalReport(reportText);

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);

      if (!parentContext.mounted) return;
      await AppFeedback.showInfo(parentContext, 'Reporte added');
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

  static Future<String?> _promptMultilineInput(
    BuildContext context, {
    required String title,
    required String hintText,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              minLines: 4,
              maxLines: 7,
              autofocus: true,
              decoration: InputDecoration(
                hintText: hintText,
                border: const OutlineInputBorder(),
              ),
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) {
                  return;
                }
                Navigator.pop(dialogContext, controller.text.trim());
              },
              child: Text(confirmLabel),
            ),
          ],
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
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled && !isLoading ? onTap : null,
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: isLoading
                      ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(
                            theme.colorScheme.primary,
                          ),
                        ),
                      )
                      : Icon(
                        icon,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
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
              if (enabled)
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
