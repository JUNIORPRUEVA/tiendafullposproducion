import 'dart:typed_data';

import 'package:flutter/material.dart';

class SignaturePadWidget extends StatelessWidget {
  final Uint8List? signaturePreviewBytes;
  final String? signatureUrl;
  final DateTime? signedAt;
  final String? syncStatus;
  final String? syncError;
  final VoidCallback? onCapture;
  final VoidCallback? onClear;
  final bool required;
  final bool enabled;

  const SignaturePadWidget({
    super.key,
    this.signaturePreviewBytes,
    this.signatureUrl,
    this.signedAt,
    this.syncStatus,
    this.syncError,
    required this.onCapture,
    required this.onClear,
    this.required = false,
    this.enabled = true,
  });

  String _formatSignedAt(DateTime? value) {
    if (value == null) return 'Firma pendiente';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return 'Firmada el $day/$month/$year a las $hh:$mm';
  }

  String _syncLabel(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'uploading':
        return 'Subiendo firma';
      case 'pending_upload':
        return 'Pendiente de sincronización';
      case 'completed':
        return 'Firma sincronizada';
      case 'local_saved':
        return 'Firma guardada localmente';
      default:
        return 'Firma pendiente';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPreview =
        signaturePreviewBytes != null || (signatureUrl ?? '').trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Firma del cliente',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            if (required) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE8E8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Obligatoria',
                  style: TextStyle(
                    color: Color(0xFFB42318),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Captura la firma para dejar evidencia del servicio realizado.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF607287),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDCE6F2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 180,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(
                    color: Colors.white,
                    child: hasPreview
                        ? signaturePreviewBytes != null
                              ? Image.memory(
                                  signaturePreviewBytes!,
                                  fit: BoxFit.contain,
                                )
                              : Image.network(
                                  signatureUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(
                                      Icons.draw_outlined,
                                      size: 36,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                )
                        : const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.draw_outlined,
                                  size: 36,
                                  color: Color(0xFF94A3B8),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Sin firma capturada',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _formatSignedAt(signedAt),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _syncLabel(syncStatus),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if ((syncError ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  syncError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFB42318),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: enabled ? onCapture : null,
                      icon: const Icon(Icons.gesture_outlined),
                      label: Text(
                        hasPreview ? 'Actualizar firma' : 'Capturar firma',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: enabled && hasPreview ? onClear : null,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Limpiar firma'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
