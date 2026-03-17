import 'package:flutter/material.dart';

import '../../../../core/widgets/local_file_image.dart';

class ServiceClosureCard extends StatelessWidget {
  final bool clientApproved;
  final ValueChanged<bool>? onClientApprovedChanged;
  final bool invoicePaid;
  final ValueChanged<bool>? onInvoicePaidChanged;
  final VoidCallback onInvoicePressed;
  final VoidCallback? onInvoiceEdit;
  final VoidCallback onWarrantyPressed;
  final VoidCallback? onWarrantyEdit;
  final VoidCallback? onSignPressed;
  final String? signatureUrl;
  final DateTime? signatureSignedAt;
  final bool busy;

  const ServiceClosureCard({
    super.key,
    required this.clientApproved,
    required this.onClientApprovedChanged,
    required this.invoicePaid,
    required this.onInvoicePaidChanged,
    required this.onInvoicePressed,
    required this.onInvoiceEdit,
    required this.onWarrantyPressed,
    required this.onWarrantyEdit,
    required this.onSignPressed,
    this.signatureUrl,
    this.signatureSignedAt,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.10),
            cs.surface,
            cs.primaryContainer.withValues(alpha: 0.18),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
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
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.task_alt_rounded,
                    color: cs.onPrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CIERRE DEL SERVICIO',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Confirma satisfacción, pago, documentos y firma final del cliente.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Guardando',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SatisfactionToggle(
              value: clientApproved,
              onChanged: onClientApprovedChanged,
            ),
            const SizedBox(height: 12),
            PaymentStatusToggle(
              value: invoicePaid,
              onChanged: onInvoicePaidChanged,
            ),
            const SizedBox(height: 12),
            DocumentsSection(
              onInvoicePressed: onInvoicePressed,
              onInvoiceEdit: onInvoiceEdit,
              onWarrantyPressed: onWarrantyPressed,
              onWarrantyEdit: onWarrantyEdit,
            ),
            const SizedBox(height: 12),
            SignatureButton(
              onPressed: onSignPressed,
              signatureUrl: signatureUrl,
              signedAt: signatureSignedAt,
            ),
          ],
        ),
      ),
    );
  }
}

class SatisfactionToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SatisfactionToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _ClosureSectionShell(
      icon: Icons.sentiment_satisfied_alt_outlined,
      title: 'Cliente satisfecho',
      subtitle: 'Registra la confirmación final del cliente.',
      child: _SegmentedToggle(value: value, onChanged: onChanged),
    );
  }
}

class PaymentStatusToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const PaymentStatusToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return _ClosureSectionShell(
      icon: Icons.payments_outlined,
      title: 'Estado de pago',
      subtitle: 'Marca si la factura ya fue pagada por el cliente.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value
              ? cs.primaryContainer.withValues(alpha: 0.70)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: value
                ? cs.primary.withValues(alpha: 0.30)
                : cs.outlineVariant.withValues(alpha: 0.50),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: value ? cs.primary : cs.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                value ? Icons.paid_outlined : Icons.receipt_long_outlined,
                color: value ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value ? 'Factura pagada' : 'Pago pendiente',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value
                        ? 'El cierre queda marcado con pago confirmado.'
                        : 'Aún no se ha confirmado el pago de la factura.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class DocumentsSection extends StatelessWidget {
  final VoidCallback onInvoicePressed;
  final VoidCallback? onInvoiceEdit;
  final VoidCallback onWarrantyPressed;
  final VoidCallback? onWarrantyEdit;

  const DocumentsSection({
    super.key,
    required this.onInvoicePressed,
    required this.onInvoiceEdit,
    required this.onWarrantyPressed,
    required this.onWarrantyEdit,
  });

  @override
  Widget build(BuildContext context) {
    return _ClosureSectionShell(
      icon: Icons.folder_copy_outlined,
      title: 'Documentos',
      subtitle: 'Consulta y ajusta los documentos de cierre del servicio.',
      child: GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: 168,
        ),
        children: [
          _DocumentActionCard(
            label: 'Factura',
            icon: Icons.receipt_long_outlined,
            onPressed: onInvoicePressed,
            onEdit: onInvoiceEdit,
          ),
          _DocumentActionCard(
            label: 'Garantía',
            icon: Icons.verified_outlined,
            onPressed: onWarrantyPressed,
            onEdit: onWarrantyEdit,
          ),
        ],
      ),
    );
  }
}

class SignatureButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? signatureUrl;
  final DateTime? signedAt;

  const SignatureButton({
    super.key,
    required this.onPressed,
    this.signatureUrl,
    this.signedAt,
  });

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return 'Firma guardada';
    final v = dt.toLocal();
    final d = v.day.toString().padLeft(2, '0');
    final m = v.month.toString().padLeft(2, '0');
    final y = v.year.toString();
    final hh = v.hour.toString().padLeft(2, '0');
    final mm = v.minute.toString().padLeft(2, '0');
    return 'Firmada el $d/$m/$y a las $hh:$mm';
  }

  bool _isLocalPath(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return false;
    if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(raw)) return true;
    if (raw.startsWith('file:///') || raw.startsWith('file://')) return true;
    final uri = Uri.tryParse(raw);
    return (uri?.scheme ?? '').toLowerCase() == 'file';
  }

  String _normalizeLocalPath(String value) {
    final raw = value.trim();
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      return uri.toFilePath();
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final signature = (signatureUrl ?? '').trim();
    final hasPreview = signature.isNotEmpty;

    return _ClosureSectionShell(
      icon: Icons.draw_outlined,
      title: 'Firma del cliente',
      subtitle: 'Captura la firma en pantalla completa para un cierre limpio.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.border_color_rounded),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              label: Text(hasPreview ? 'Actualizar firma' : 'Firmar Cliente'),
            ),
          ),
          if (hasPreview) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.50),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 96,
                    height: 56,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.60),
                      ),
                    ),
                    child: _isLocalPath(signature)
                        ? localFileImage(
                            path: _normalizeLocalPath(signature),
                            fit: BoxFit.contain,
                          )
                        : Image.network(
                            signature,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.draw_outlined,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Firma registrada',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fmtDateTime(signedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClosureSectionShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _ClosureSectionShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
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
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SegmentedToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SegmentedToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentOption(
              label: 'SI',
              icon: Icons.thumb_up_alt_outlined,
              selected: value,
              onTap: onChanged == null ? null : () => onChanged!(true),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _SegmentOption(
              label: 'NO',
              icon: Icons.thumb_down_alt_outlined,
              selected: !value,
              onTap: onChanged == null ? null : () => onChanged!(false),
              selectedColor: cs.errorContainer,
              selectedForegroundColor: cs.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  final Color? selectedColor;
  final Color? selectedForegroundColor;

  const _SegmentOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.selectedColor,
    this.selectedForegroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final background = selected
        ? (selectedColor ?? cs.primary)
        : Colors.transparent;
    final foreground = selected
        ? (selectedForegroundColor ?? cs.onPrimary)
        : cs.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback? onEdit;

  const _DocumentActionCard({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: const Icon(Icons.visibility_outlined),
            label: Text(label),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar'),
          ),
        ],
      ),
    );
  }
}
