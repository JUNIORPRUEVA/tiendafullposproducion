import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum CloseStatus { draft, pending, closed, diff, depositRequired }

class StatusBadge extends StatelessWidget {
  final CloseStatus status;
  final String? label;

  const StatusBadge({super.key, required this.status, this.label});

  Color _color(ColorScheme scheme) {
    switch (status) {
      case CloseStatus.closed:
        return AppTheme.successColor;
      case CloseStatus.pending:
      case CloseStatus.draft:
        return AppTheme.warningColor;
      case CloseStatus.diff:
      case CloseStatus.depositRequired:
        return AppTheme.errorColor;
    }
  }

  String _text() {
    if (label != null && label!.isNotEmpty) return label!;
    switch (status) {
      case CloseStatus.closed:
        return 'Cerrado';
      case CloseStatus.pending:
        return 'Pendiente';
      case CloseStatus.draft:
        return 'Borrador';
      case CloseStatus.diff:
        return 'Diferencia';
      case CloseStatus.depositRequired:
        return 'Depósito requerido';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color(scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        _text(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
