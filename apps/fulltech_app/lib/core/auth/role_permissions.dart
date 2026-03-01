String normalizeRole(String? role) {
  return (role ?? '').trim().toUpperCase();
}

bool canAccessContabilidadByRole(String? role) {
  final normalized = normalizeRole(role);
  return normalized == 'ADMIN' || normalized == 'ASISTENTE';
}

bool canSendLocationByRole(String? role) {
  final normalized = normalizeRole(role);
  return normalized == 'TECNICO';
}
