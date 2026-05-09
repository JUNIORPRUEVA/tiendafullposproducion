class CrmComercialUserRef {
  const CrmComercialUserRef({
    required this.id,
    required this.nombreCompleto,
    this.role,
  });

  final String id;
  final String nombreCompleto;
  final String? role;

  factory CrmComercialUserRef.fromJson(Map<String, dynamic> json) {
    return CrmComercialUserRef(
      id: (json['id'] ?? '').toString(),
      nombreCompleto: (json['nombreCompleto'] ?? 'Sin nombre').toString(),
      role: json['role']?.toString(),
    );
  }
}

class CrmComercialStatusEntry {
  const CrmComercialStatusEntry({
    required this.id,
    required this.estadoNuevo,
    this.estadoAnterior,
    this.nota,
    this.createdAt,
    this.changedBy,
  });

  final String id;
  final String estadoNuevo;
  final String? estadoAnterior;
  final String? nota;
  final DateTime? createdAt;
  final CrmComercialUserRef? changedBy;

  factory CrmComercialStatusEntry.fromJson(Map<String, dynamic> json) {
    return CrmComercialStatusEntry(
      id: (json['id'] ?? '').toString(),
      estadoNuevo: (json['estadoNuevo'] ?? '').toString(),
      estadoAnterior: json['estadoAnterior']?.toString(),
      nota: json['nota']?.toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      changedBy: (json['changedByUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['changedByUser'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class CrmComercialNote {
  const CrmComercialNote({
    required this.id,
    required this.note,
    this.createdAt,
    this.author,
  });

  final String id;
  final String note;
  final DateTime? createdAt;
  final CrmComercialUserRef? author;

  factory CrmComercialNote.fromJson(Map<String, dynamic> json) {
    return CrmComercialNote(
      id: (json['id'] ?? '').toString(),
      note: (json['note'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      author: (json['authorUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['authorUser'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class CrmComercialActivity {
  const CrmComercialActivity({
    required this.id,
    required this.activityType,
    required this.description,
    this.dueAt,
    this.completedAt,
    this.createdAt,
    this.assignedTo,
    this.createdBy,
  });

  final String id;
  final String activityType;
  final String description;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final CrmComercialUserRef? assignedTo;
  final CrmComercialUserRef? createdBy;

  factory CrmComercialActivity.fromJson(Map<String, dynamic> json) {
    return CrmComercialActivity(
      id: (json['id'] ?? '').toString(),
      activityType: (json['activityType'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      dueAt: DateTime.tryParse((json['dueAt'] ?? '').toString()),
      completedAt: DateTime.tryParse((json['completedAt'] ?? '').toString()),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      assignedTo: (json['assignedToUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['assignedToUser'] as Map<String, dynamic>,
            )
          : null,
      createdBy: (json['createdByUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['createdByUser'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class CrmComercialCustomer {
  const CrmComercialCustomer({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.estadoActual,
    this.direccion,
    this.ciudad,
    this.etiqueta,
    this.nextAction,
    this.nextActionAt,
    this.updatedAt,
    this.responsable,
    this.statusHistory = const [],
    this.notes = const [],
    this.activities = const [],
  });

  final String id;
  final String nombre;
  final String telefono;
  final String estadoActual;
  final String? direccion;
  final String? ciudad;
  final String? etiqueta;
  final String? nextAction;
  final DateTime? nextActionAt;
  final DateTime? updatedAt;
  final CrmComercialUserRef? responsable;
  final List<CrmComercialStatusEntry> statusHistory;
  final List<CrmComercialNote> notes;
  final List<CrmComercialActivity> activities;

  factory CrmComercialCustomer.fromJson(Map<String, dynamic> json) {
    return CrmComercialCustomer(
      id: (json['id'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      telefono: (json['telefono'] ?? '').toString(),
      estadoActual: (json['estadoActual'] ?? '').toString(),
      direccion: json['direccion']?.toString(),
      ciudad: json['ciudad']?.toString(),
      etiqueta: json['etiqueta']?.toString(),
      nextAction: json['nextAction']?.toString(),
      nextActionAt: DateTime.tryParse((json['nextActionAt'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
      responsable: (json['responsableUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['responsableUser'] as Map<String, dynamic>,
            )
          : null,
      statusHistory: ((json['statusHistory'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialStatusEntry.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      notes: ((json['notes'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialNote.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      activities: ((json['activities'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialActivity.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class CrmComercialCustomerListResponse {
  const CrmComercialCustomerListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<CrmComercialCustomer> items;
  final int total;
  final int page;
  final int pageSize;

  factory CrmComercialCustomerListResponse.fromJson(Map<String, dynamic> json) {
    return CrmComercialCustomerListResponse(
      items: ((json['items'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialCustomer.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? 20,
    );
  }
}

  class CrmComercialFollowupTask {
    const CrmComercialFollowupTask({
      required this.id,
      required this.customerId,
      required this.title,
      required this.status,
      required this.effectiveStatus,
      required this.priority,
      this.description,
      this.dueDate,
      this.completedAt,
      this.createdAt,
      this.assignedTo,
      this.createdBy,
      this.completedBy,
    });

    final String id;
    final String customerId;
    final String title;
    final String status;
    final String effectiveStatus;
    final String priority;
    final String? description;
    final DateTime? dueDate;
    final DateTime? completedAt;
    final DateTime? createdAt;
    final CrmComercialUserRef? assignedTo;
    final CrmComercialUserRef? createdBy;
    final CrmComercialUserRef? completedBy;

    bool get isPending => effectiveStatus == 'PENDIENTE';
    bool get isOverdue => effectiveStatus == 'VENCIDA';
    bool get isCompleted => status == 'COMPLETADA';
    bool get isCancelled => status == 'CANCELADA';
    bool get isActive => status == 'PENDIENTE';

    factory CrmComercialFollowupTask.fromJson(Map<String, dynamic> json) {
      return CrmComercialFollowupTask(
        id: (json['id'] ?? '').toString(),
        customerId: (json['customerId'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        status: (json['status'] ?? 'PENDIENTE').toString(),
        effectiveStatus:
            (json['effectiveStatus'] ?? json['status'] ?? 'PENDIENTE').toString(),
        priority: (json['priority'] ?? 'NORMAL').toString(),
        description: json['description']?.toString(),
        dueDate: DateTime.tryParse((json['dueDate'] ?? '').toString()),
        completedAt: DateTime.tryParse((json['completedAt'] ?? '').toString()),
        createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
        assignedTo: (json['assignedUser'] is Map<String, dynamic>)
            ? CrmComercialUserRef.fromJson(
                json['assignedUser'] as Map<String, dynamic>)
            : null,
        createdBy: (json['createdByUser'] is Map<String, dynamic>)
            ? CrmComercialUserRef.fromJson(
                json['createdByUser'] as Map<String, dynamic>)
            : null,
        completedBy: (json['completedByUser'] is Map<String, dynamic>)
            ? CrmComercialUserRef.fromJson(
                json['completedByUser'] as Map<String, dynamic>)
            : null,
      );
    }
  }
