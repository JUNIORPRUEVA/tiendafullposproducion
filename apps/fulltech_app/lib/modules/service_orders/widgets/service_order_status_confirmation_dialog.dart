import 'package:flutter/material.dart';

import '../service_order_models.dart';

Future<bool> showServiceOrderStatusConfirmationDialog({
  required BuildContext context,
  required ServiceOrderStatus status,
  required Future<void> Function() onConfirm,
}) async {
  if (!status.requiresUpdateConfirmation) {
    await onConfirm();
    return true;
  }

  Object? actionError;
  StackTrace? actionStackTrace;
  var confirmed = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var isSubmitting = false;

      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> handleConfirm() async {
            if (isSubmitting) {
              return;
            }

            setState(() {
              isSubmitting = true;
            });

            try {
              await onConfirm();
              confirmed = true;
            } catch (error, stackTrace) {
              actionError = error;
              actionStackTrace = stackTrace;
            } finally {
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            }
          }

          return PopScope(
            canPop: !isSubmitting,
            child: AlertDialog(
              title: const Text('Confirmar acción'),
              content: Text(
                '¿Estás seguro de que deseas marcar esta orden como ${status.confirmationLabel}?',
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
            ),
          );
        },
      );
    },
  );

  if (actionError != null && actionStackTrace != null) {
    Error.throwWithStackTrace(actionError!, actionStackTrace!);
  }

  return confirmed;
}
