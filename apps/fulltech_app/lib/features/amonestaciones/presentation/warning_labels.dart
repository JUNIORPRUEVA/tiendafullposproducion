import 'package:flutter/material.dart';

abstract class WarningLabels {
  static const Map<String, String> status = {
    'DRAFT': 'Borrador',
    'PENDING_SIGNATURE': 'Pendiente firma',
    'SIGNED': 'Firmada',
    'REFUSED_TO_SIGN': 'Negativa',
    'ANNULLED': 'Anulada',
    'ARCHIVED': 'Archivada',
  };

  static const Map<String, String> severity = {
    'LOW': 'Leve',
    'MEDIUM': 'Moderada',
    'HIGH': 'Grave',
    'CRITICAL': 'Muy Grave',
  };

  static const Map<String, String> category = {
    'TARDINESS': 'Tardanza',
    'ABSENCE': 'Ausencia',
    'MISCONDUCT': 'Conducta inapropiada',
    'NEGLIGENCE': 'Negligencia',
    'POLICY_VIOLATION': 'Violación de política',
    'INSUBORDINATION': 'Insubordinación',
    'OTHER': 'Otro',
  };

  static Color statusColor(String s) {
    switch (s) {
      case 'SIGNED':
        return const Color(0xFF2ecc71);
      case 'PENDING_SIGNATURE':
        return const Color(0xFFf39c12);
      case 'REFUSED_TO_SIGN':
        return const Color(0xFFe74c3c);
      case 'ANNULLED':
        return const Color(0xFF95a5a6);
      case 'ARCHIVED':
        return const Color(0xFF7f8c8d);
      case 'DRAFT':
      default:
        return const Color(0xFF3498db);
    }
  }

  static Color severityColor(String s) {
    switch (s) {
      case 'LOW':
        return const Color(0xFF2ecc71);
      case 'MEDIUM':
        return const Color(0xFFf39c12);
      case 'HIGH':
        return const Color(0xFFe67e22);
      case 'CRITICAL':
        return const Color(0xFFe74c3c);
      default:
        return const Color(0xFF95a5a6);
    }
  }

  static String fmt(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }
}
