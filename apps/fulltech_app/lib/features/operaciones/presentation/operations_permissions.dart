import '../../../core/models/user_model.dart';
import '../operations_models.dart';

class OperationsPermissions {
  final UserModel? user;
  final ServiceModel service;

  const OperationsPermissions({required this.user, required this.service});

  String get _userId => (user?.id ?? '').trim();
  String get _role => (user?.role ?? '').trim().toLowerCase();

  bool get isAdminLike => _role == 'admin' || _role == 'asistente';
  bool get isTechnician => _role == 'tecnico';
  bool get isOwner => _userId.isNotEmpty && _userId == service.createdByUserId;

  bool get canChangePhase => isAdminLike || isOwner;

  String? get changePhaseDeniedReason {
    if (canChangePhase) return null;
    return 'Solo creador o admin';
  }

  bool get canChangeAdminPhase => canOperate;

  String? get changeAdminPhaseDeniedReason =>
      canChangeAdminPhase ? null : operateDeniedReason;

  bool get isAssignedTechnician {
    if (!isTechnician) return false;
    if (_userId.isEmpty) return false;
    if ((service.technicianId ?? '').trim() == _userId) return true;
    return service.assignments.any((a) => a.userId == _userId);
  }

  bool get canCritical => isAdminLike || isOwner;

  bool get canOperate {
    // Operativas: admin, técnico asignado, (opcional) owner.
    return isAdminLike || isAssignedTechnician || isOwner;
  }

  bool get canDelete => canCritical;

  bool get canCancel => canCritical;

  String? get operateDeniedReason {
    if (canOperate) return null;
    if (isTechnician) return 'Solo técnicos asignados';
    return 'No autorizado';
  }

  String? get criticalDeniedReason =>
      canCritical ? null : 'Solo creador o admin';

  static const _flow = <String, List<String>>{
    'reserved': ['survey', 'cancelled'],
    'survey': ['scheduled', 'cancelled'],
    'scheduled': ['in_progress', 'cancelled'],
    'in_progress': ['completed', 'warranty', 'cancelled'],
    'completed': ['warranty', 'closed'],
    'warranty': ['in_progress', 'closed'],
    'closed': [],
    'cancelled': [],
  };

  bool canTransition(String from, String to) {
    final cur = from.trim().toLowerCase();
    final next = to.trim().toLowerCase();
    if (cur == next) return true;

    final allowed = _flow[cur];
    if (allowed == null) return false;
    if (!allowed.contains(next)) return false;

    // Regla extra: cancelar solo crítico.
    if (next == 'cancelled') return canCancel;

    return canOperate;
  }

  List<String> allowedNextStatuses() {
    final cur = service.status.trim().toLowerCase();
    final allowed = _flow[cur] ?? const <String>[];
    return allowed.where((next) => canTransition(cur, next)).toList();
  }
}
