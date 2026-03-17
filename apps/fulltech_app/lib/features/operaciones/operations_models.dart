class ServiceAssignmentModel {
  final String id;
  final String userId;
  final String role;
  final String userName;

  ServiceAssignmentModel({
    required this.id,
    required this.userId,
    required this.role,
    required this.userName,
  });

  factory ServiceAssignmentModel.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ServiceAssignmentModel(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      role: (json['role'] ?? 'assistant').toString(),
      userName: (user['nombreCompleto'] ?? user['email'] ?? 'Técnico')
          .toString(),
    );
  }
}

enum ServiceStatus {
  reserved,
  survey,
  scheduled,
  inProgress,
  completed,
  warranty,
  closed,
  cancelled,
  unknown,
}

ServiceStatus parseStatus(dynamic raw) {
  if (raw == null) return ServiceStatus.unknown;
  var value = raw.toString().trim();
  if (value.isEmpty) return ServiceStatus.unknown;

  value = value.toLowerCase();
  value = value.replaceAll(' ', '_').replaceAll('-', '_');

  switch (value) {
    case 'reserved':
    case 'reserva':
    case 'pending':
    case 'pendiente':
    case 'confirmed':
    case 'confirmado':
    case 'assigned':
    case 'asignado':
    case 'rescheduled':
    case 'reagendado':
      return ServiceStatus.reserved;
    case 'survey':
    case 'levantamiento':
      return ServiceStatus.survey;
    case 'scheduled':
    case 'agendado':
      return ServiceStatus.scheduled;
    case 'in_progress':
    case 'en_proceso':
    case 'enproceso':
      return ServiceStatus.inProgress;
    case 'completed':
    case 'completado':
    case 'finalizado':
    case 'finalized':
    case 'finalizada':
      return ServiceStatus.completed;
    case 'warranty':
    case 'garantia':
      return ServiceStatus.warranty;
    case 'closed':
    case 'cerrado':
      return ServiceStatus.closed;
    case 'cancelled':
    case 'canceled':
    case 'cancelado':
      return ServiceStatus.cancelled;
    default:
      return ServiceStatus.unknown;
  }
}

String phaseLabel(dynamic raw) {
  if (raw == null) return '—';
  var value = raw.toString().trim();
  if (value.isEmpty) return '—';

  value = value.toLowerCase();
  value = value.replaceAll(' ', '_').replaceAll('-', '_');

  switch (value) {
    case 'reserva':
      return 'Reserva';
    case 'levantamiento':
      return 'Levantamiento';
    case 'instalacion':
      return 'Instalación';
    case 'mantenimiento':
      return 'Mantenimiento';
    case 'garantia':
      return 'Garantía';
    case 'finalizado':
    case 'finalizada':
      return 'Finalizado';
    case 'cancelado':
    case 'cancelada':
      return 'Cancelado';
    default:
      return value;
  }
}

String adminPhaseLabel(dynamic raw) {
  if (raw == null) return '—';
  var value = raw.toString().trim();
  if (value.isEmpty) return '—';

  value = value.toLowerCase();
  value = value.replaceAll(' ', '_').replaceAll('-', '_');

  switch (value) {
    case 'reserva':
      return 'Reserva';
    case 'confirmacion':
      return 'Confirmación';
    case 'programacion':
      return 'Programación';
    case 'ejecucion':
      return 'Ejecución';
    case 'revision':
      return 'Revisión';
    case 'facturacion':
      return 'Facturación';
    case 'cierre':
      return 'Cierre';
    case 'cancelada':
      return 'Cancelada';
    default:
      return value;
  }
}

class ServiceStepModel {
  final String id;
  final String stepKey;
  final String stepLabel;
  final bool isDone;
  final DateTime? doneAt;

  ServiceStepModel({
    required this.id,
    required this.stepKey,
    required this.stepLabel,
    required this.isDone,
    this.doneAt,
  });

  factory ServiceStepModel.fromJson(Map<String, dynamic> json) {
    return ServiceStepModel(
      id: (json['id'] ?? '').toString(),
      stepKey: (json['stepKey'] ?? '').toString(),
      stepLabel: (json['stepLabel'] ?? '').toString(),
      isDone: json['isDone'] == true,
      doneAt: json['doneAt'] == null
          ? null
          : DateTime.tryParse(json['doneAt'].toString()),
    );
  }
}

class ServiceFileModel {
  final String id;
  final String fileUrl;
  final String fileType;
  final String? mimeType;
  final String? caption;
  final DateTime? createdAt;

  ServiceFileModel({
    required this.id,
    required this.fileUrl,
    required this.fileType,
    this.mimeType,
    this.caption,
    this.createdAt,
  });

  factory ServiceFileModel.fromJson(Map<String, dynamic> json) {
    return ServiceFileModel(
      id: (json['id'] ?? '').toString(),
      fileUrl: (json['fileUrl'] ?? '').toString(),
      fileType: (json['fileType'] ?? '').toString(),
      mimeType: json['mimeType']?.toString(),
      caption: json['caption']?.toString(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
    );
  }
}

class ServiceUpdateModel {
  final String id;
  final String type;
  final String message;
  final String changedBy;
  final DateTime? createdAt;

  ServiceUpdateModel({
    required this.id,
    required this.type,
    required this.message,
    required this.changedBy,
    this.createdAt,
  });

  factory ServiceUpdateModel.fromJson(Map<String, dynamic> json) {
    final changedBy =
        (json['changedBy'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ServiceUpdateModel(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      changedBy: (changedBy['nombreCompleto'] ?? 'Sistema').toString(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
    );
  }
}

class ServicePhaseHistoryModel {
  final String id;
  final String phase;
  final String? note;
  final String changedBy;
  final DateTime? changedAt;
  final String? fromPhase;
  final String? toPhase;

  ServicePhaseHistoryModel({
    required this.id,
    required this.phase,
    required this.changedBy,
    this.note,
    this.changedAt,
    this.fromPhase,
    this.toPhase,
  });

  factory ServicePhaseHistoryModel.fromJson(Map<String, dynamic> json) {
    final changedBy =
        (json['changedBy'] as Map?)?.cast<String, dynamic>() ?? const {};

    String? parseNullableString(dynamic raw) {
      if (raw == null) return null;
      final text = raw.toString();
      return text.trim().isEmpty ? null : text;
    }

    return ServicePhaseHistoryModel(
      id: (json['id'] ?? '').toString(),
      phase: (json['phase'] ?? 'reserva').toString(),
      note: parseNullableString(json['note']),
      changedBy: (changedBy['nombreCompleto'] ?? 'Sistema').toString(),
      changedAt: json['changedAt'] == null
          ? null
          : DateTime.tryParse(json['changedAt'].toString()),
      fromPhase: parseNullableString(json['fromPhase']),
      toPhase: parseNullableString(json['toPhase']),
    );
  }
}

class TechnicianModel {
  final String id;
  final String name;

  TechnicianModel({required this.id, required this.name});

  factory TechnicianModel.fromJson(Map<String, dynamic> json) {
    return TechnicianModel(
      id: (json['id'] ?? '').toString(),
      name: (json['nombreCompleto'] ?? json['name'] ?? 'Técnico').toString(),
    );
  }
}

class ServiceClosingSummaryModel {
  final String approvalStatus;
  final String signatureStatus;
  final String? invoiceDraftFileId;
  final String? warrantyDraftFileId;
  final String? invoiceApprovedFileId;
  final String? warrantyApprovedFileId;
  final String? invoiceFinalFileId;
  final String? warrantyFinalFileId;
  final DateTime? approvedAt;
  final DateTime? signedAt;
  final DateTime? sentToClientAt;

  const ServiceClosingSummaryModel({
    required this.approvalStatus,
    required this.signatureStatus,
    this.invoiceDraftFileId,
    this.warrantyDraftFileId,
    this.invoiceApprovedFileId,
    this.warrantyApprovedFileId,
    this.invoiceFinalFileId,
    this.warrantyFinalFileId,
    this.approvedAt,
    this.signedAt,
    this.sentToClientAt,
  });

  static String _s(dynamic v) => (v ?? '').toString();
  static String? _sn(dynamic v) {
    final s = _s(v).trim();
    return s.isEmpty ? null : s;
  }

  factory ServiceClosingSummaryModel.fromJson(Map<String, dynamic> json) {
    DateTime? asDate(dynamic raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    return ServiceClosingSummaryModel(
      approvalStatus: _s(json['approvalStatus']).trim().isEmpty
          ? 'PENDING'
          : _s(json['approvalStatus']).trim(),
      signatureStatus: _s(json['signatureStatus']).trim().isEmpty
          ? 'PENDING'
          : _s(json['signatureStatus']).trim(),
      invoiceDraftFileId: _sn(json['invoiceDraftFileId']),
      warrantyDraftFileId: _sn(json['warrantyDraftFileId']),
      invoiceApprovedFileId: _sn(json['invoiceApprovedFileId']),
      warrantyApprovedFileId: _sn(json['warrantyApprovedFileId']),
      invoiceFinalFileId: _sn(json['invoiceFinalFileId']),
      warrantyFinalFileId: _sn(json['warrantyFinalFileId']),
      approvedAt: asDate(json['approvedAt']),
      signedAt: asDate(json['signedAt']),
      sentToClientAt: asDate(json['sentToClientAt']),
    );
  }
}

class ServiceModel {
  final String id;
  final String orderNumber;
  final String title;
  final String description;
  final String serviceType;
  final String category;
  final String status;
  final String currentPhase;
  final String orderType;
  final String orderState;
  final String? adminPhase;
  final String? adminStatus;
  final String? technicianId;
  final int priority;
  final double? quotedAmount;
  final double? depositAmount;
  final double? finalCost;
  final List<String> tags;
  final DateTime? createdAt;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? completedAt;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String createdByUserId;
  final String createdByName;
  final List<ServiceAssignmentModel> assignments;
  final List<ServiceStepModel> steps;
  final List<ServiceFileModel> files;
  final List<ServiceUpdateModel> updates;
  final ServiceClosingSummaryModel? closing;

  ServiceModel({
    required this.id,
    this.orderNumber = '',
    required this.title,
    required this.description,
    required this.serviceType,
    required this.category,
    required this.status,
    required this.currentPhase,
    required this.orderType,
    required this.orderState,
    this.adminPhase,
    this.adminStatus,
    required this.priority,
    required this.tags,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.createdByUserId,
    required this.createdByName,
    required this.assignments,
    required this.steps,
    required this.files,
    required this.updates,
    this.closing,
    this.technicianId,
    this.quotedAmount,
    this.depositAmount,
    this.finalCost,
    this.createdAt,
    this.scheduledStart,
    this.scheduledEnd,
    this.completedAt,
  });

  String get orderLabel {
    final v = orderNumber.trim();
    if (v.isNotEmpty) return v;
    final idTrim = id.trim();
    if (idTrim.length >= 8) return idTrim.substring(0, 8);
    return idTrim;
  }

  ServiceModel copyWith({
    String? orderNumber,
    String? title,
    String? description,
    String? serviceType,
    String? category,
    String? status,
    String? currentPhase,
    String? orderType,
    String? orderState,
    String? adminPhase,
    String? adminStatus,
    String? technicianId,
    int? priority,
    double? quotedAmount,
    double? depositAmount,
    double? finalCost,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    DateTime? completedAt,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? createdByUserId,
    String? createdByName,
    List<ServiceAssignmentModel>? assignments,
    List<ServiceStepModel>? steps,
    List<ServiceFileModel>? files,
    List<ServiceUpdateModel>? updates,
    ServiceClosingSummaryModel? closing,
  }) {
    return ServiceModel(
      id: id,
      orderNumber: orderNumber ?? this.orderNumber,
      title: title ?? this.title,
      description: description ?? this.description,
      serviceType: serviceType ?? this.serviceType,
      category: category ?? this.category,
      status: status ?? this.status,
      currentPhase: currentPhase ?? this.currentPhase,
      orderType: orderType ?? this.orderType,
      orderState: orderState ?? this.orderState,
      adminPhase: adminPhase ?? this.adminPhase,
      adminStatus: adminStatus ?? this.adminStatus,
      technicianId: technicianId ?? this.technicianId,
      priority: priority ?? this.priority,
      quotedAmount: quotedAmount ?? this.quotedAmount,
      depositAmount: depositAmount ?? this.depositAmount,
      finalCost: finalCost ?? this.finalCost,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      scheduledStart: scheduledStart ?? this.scheduledStart,
      scheduledEnd: scheduledEnd ?? this.scheduledEnd,
      completedAt: completedAt ?? this.completedAt,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdByName: createdByName ?? this.createdByName,
      assignments: assignments ?? this.assignments,
      steps: steps ?? this.steps,
      files: files ?? this.files,
      updates: updates ?? this.updates,
      closing: closing ?? this.closing,
    );
  }

  bool get isSeguro {
    final deposit = depositAmount ?? 0;
    if (deposit > 0) return true;
    return tags.any((t) => t.trim().toLowerCase() == 'seguro');
  }

  factory ServiceModel.fromJson(Map<String, dynamic> json) {
    final customer =
        (json['customer'] as Map?)?.cast<String, dynamic>() ?? const {};
    final createdBy =
        (json['createdBy'] as Map?)?.cast<String, dynamic>() ?? const {};

    double? parseMoney(dynamic raw) {
      if (raw == null) return null;
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw);
      return double.tryParse(raw.toString());
    }

    double? parseFinalCost(dynamic raw) {
      if (raw == null) return null;
      if (raw is Map) {
        return parseMoney(raw['finalCost']);
      }
      return null;
    }

    List<String> parseStringList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .map((e) => (e ?? '').toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }

    List<T> parseList<T>(dynamic raw, T Function(Map<String, dynamic>) parser) {
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((item) => parser(item.cast<String, dynamic>()))
          .toList();
    }

    final closingRaw = (json['closing'] as Map?)?.cast<String, dynamic>();

    return ServiceModel(
      id: (json['id'] ?? '').toString(),
      orderNumber: (json['orderNumber'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      serviceType: (json['serviceType'] ?? 'other').toString(),
      category: (json['category'] ?? '').toString(),
      status: (json['status'] ?? 'reserved').toString(),
      currentPhase: (json['currentPhase'] ?? json['phase'] ?? 'reserva')
          .toString(),
      orderType: (json['orderType'] ?? 'reserva').toString(),
      orderState: (json['orderState'] ?? 'pending').toString(),
      adminPhase: json['adminPhase'] == null
          ? null
          : (json['adminPhase'] ?? '').toString(),
      adminStatus: json['adminStatus'] == null
          ? null
          : (json['adminStatus'] ?? '').toString(),
      technicianId: json['technicianId'] == null
          ? null
          : (json['technicianId'] ?? '').toString(),
      priority: (json['priority'] is int)
          ? json['priority'] as int
          : int.tryParse('${json['priority']}') ?? 2,
      quotedAmount: parseMoney(json['quotedAmount']),
      depositAmount: parseMoney(json['depositAmount']),
      finalCost: parseFinalCost(json['orderExtras']),
      tags: parseStringList(json['tags']),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
      scheduledStart: json['scheduledStart'] == null
          ? null
          : DateTime.tryParse(json['scheduledStart'].toString()),
      scheduledEnd: json['scheduledEnd'] == null
          ? null
          : DateTime.tryParse(json['scheduledEnd'].toString()),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.tryParse(json['completedAt'].toString()),
      customerId: (customer['id'] ?? '').toString(),
      customerName: (customer['nombre'] ?? '').toString(),
      customerPhone: (customer['telefono'] ?? '').toString(),
      customerAddress: (json['addressSnapshot'] ?? customer['direccion'] ?? '')
          .toString(),
      createdByUserId: (json['createdByUserId'] ?? '').toString(),
      createdByName: (createdBy['nombreCompleto'] ?? '').toString(),
      assignments: parseList(
        json['assignments'],
        ServiceAssignmentModel.fromJson,
      ),
      steps: parseList(json['steps'], ServiceStepModel.fromJson),
      files: parseList(json['files'], ServiceFileModel.fromJson),
      updates: parseList(json['updates'], ServiceUpdateModel.fromJson),
      closing: closingRaw == null
          ? null
          : ServiceClosingSummaryModel.fromJson(closingRaw),
    );
  }
}

class ServiceExecutionReportModel {
  final String id;
  final String serviceId;
  final String technicianId;
  final String phase;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? notes;
  final Map<String, dynamic>? checklistData;
  final Map<String, dynamic>? phaseSpecificData;
  final bool clientApproved;
  final DateTime? updatedAt;

  const ServiceExecutionReportModel({
    required this.id,
    required this.serviceId,
    required this.technicianId,
    required this.phase,
    required this.clientApproved,
    this.arrivedAt,
    this.startedAt,
    this.finishedAt,
    this.notes,
    this.checklistData,
    this.phaseSpecificData,
    this.updatedAt,
  });

  factory ServiceExecutionReportModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? asMap(dynamic raw) {
      if (raw is Map) return raw.cast<String, dynamic>();
      return null;
    }

    DateTime? asDate(dynamic raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    return ServiceExecutionReportModel(
      id: (json['id'] ?? '').toString(),
      serviceId: (json['serviceId'] ?? '').toString(),
      technicianId: (json['technicianId'] ?? '').toString(),
      phase: (json['phase'] ?? '').toString(),
      arrivedAt: asDate(json['arrivedAt']),
      startedAt: asDate(json['startedAt']),
      finishedAt: asDate(json['finishedAt']),
      notes: json['notes']?.toString(),
      checklistData: asMap(json['checklistData']),
      phaseSpecificData: asMap(json['phaseSpecificData']),
      clientApproved: json['clientApproved'] == true,
      updatedAt: asDate(json['updatedAt']),
    );
  }
}

class ServiceExecutionChangeModel {
  final String id;
  final String serviceId;
  final String executionReportId;
  final String createdByUserId;
  final String type;
  final String description;
  final double? quantity;
  final double? extraCost;
  final bool? clientApproved;
  final String? note;
  final DateTime? createdAt;

  const ServiceExecutionChangeModel({
    required this.id,
    required this.serviceId,
    required this.executionReportId,
    required this.createdByUserId,
    required this.type,
    required this.description,
    this.quantity,
    this.extraCost,
    this.clientApproved,
    this.note,
    this.createdAt,
  });

  factory ServiceExecutionChangeModel.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic raw) {
      if (raw == null) return null;
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw.toString());
    }

    DateTime? asDate(dynamic raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    return ServiceExecutionChangeModel(
      id: (json['id'] ?? '').toString(),
      serviceId: (json['serviceId'] ?? '').toString(),
      executionReportId: (json['executionReportId'] ?? '').toString(),
      createdByUserId: (json['createdByUserId'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      quantity: asDouble(json['quantity']),
      extraCost: asDouble(json['extraCost']),
      clientApproved: json['clientApproved'] == null
          ? null
          : json['clientApproved'] == true,
      note: json['note']?.toString(),
      createdAt: asDate(json['createdAt']),
    );
  }
}

class ServiceExecutionBundleModel {
  final ServiceExecutionReportModel? report;
  final List<ServiceExecutionChangeModel> changes;

  const ServiceExecutionBundleModel({
    required this.report,
    required this.changes,
  });

  factory ServiceExecutionBundleModel.fromJson(Map<String, dynamic> json) {
    final reportRaw = json['report'];
    final report = reportRaw is Map
        ? ServiceExecutionReportModel.fromJson(
            reportRaw.cast<String, dynamic>(),
          )
        : null;

    final changesRaw = json['changes'];
    final changes = changesRaw is List
        ? changesRaw
              .whereType<Map>()
              .map(
                (e) => ServiceExecutionChangeModel.fromJson(
                  e.cast<String, dynamic>(),
                ),
              )
              .toList(growable: false)
        : const <ServiceExecutionChangeModel>[];

    return ServiceExecutionBundleModel(report: report, changes: changes);
  }
}

class ServiceChecklistCategoryModel {
  final String id;
  final String name;
  final String code;

  const ServiceChecklistCategoryModel({
    required this.id,
    required this.name,
    required this.code,
  });

  factory ServiceChecklistCategoryModel.fromJson(Map<String, dynamic> json) {
    return ServiceChecklistCategoryModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
    );
  }
}

class ServiceChecklistPhaseModel {
  final String id;
  final String name;
  final String code;
  final int orderIndex;

  const ServiceChecklistPhaseModel({
    required this.id,
    required this.name,
    required this.code,
    required this.orderIndex,
  });

  factory ServiceChecklistPhaseModel.fromJson(Map<String, dynamic> json) {
    return ServiceChecklistPhaseModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
    );
  }
}

class ServiceChecklistItemModel {
  final String id;
  final String checklistItemId;
  final String label;
  final bool isRequired;
  final int orderIndex;
  final bool isChecked;
  final DateTime? checkedAt;
  final String? checkedByUserId;
  final String? checkedByName;

  const ServiceChecklistItemModel({
    required this.id,
    required this.checklistItemId,
    required this.label,
    required this.isRequired,
    required this.orderIndex,
    required this.isChecked,
    this.checkedAt,
    this.checkedByUserId,
    this.checkedByName,
  });

  factory ServiceChecklistItemModel.fromJson(Map<String, dynamic> json) {
    return ServiceChecklistItemModel(
      id: (json['id'] ?? '').toString(),
      checklistItemId: (json['checklistItemId'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      isRequired: json['isRequired'] != false,
      orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
      isChecked: json['isChecked'] == true,
      checkedAt: json['checkedAt'] == null
          ? null
          : DateTime.tryParse(json['checkedAt'].toString()),
      checkedByUserId: json['checkedByUserId']?.toString(),
      checkedByName: json['checkedByName']?.toString(),
    );
  }

  ServiceChecklistItemModel copyWith({bool? isChecked, DateTime? checkedAt}) {
    return ServiceChecklistItemModel(
      id: id,
      checklistItemId: checklistItemId,
      label: label,
      isRequired: isRequired,
      orderIndex: orderIndex,
      isChecked: isChecked ?? this.isChecked,
      checkedAt: checkedAt ?? this.checkedAt,
      checkedByUserId: checkedByUserId,
      checkedByName: checkedByName,
    );
  }
}

class ServiceChecklistTemplateModel {
  final String id;
  final String templateId;
  final String title;
  final ServiceChecklistCategoryModel category;
  final ServiceChecklistPhaseModel phase;
  final List<ServiceChecklistItemModel> items;

  const ServiceChecklistTemplateModel({
    required this.id,
    required this.templateId,
    required this.title,
    required this.category,
    required this.phase,
    required this.items,
  });

  factory ServiceChecklistTemplateModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ServiceChecklistTemplateModel(
      id: (json['id'] ?? '').toString(),
      templateId: (json['templateId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      category: ServiceChecklistCategoryModel.fromJson(
        (json['category'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      phase: ServiceChecklistPhaseModel.fromJson(
        (json['phase'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => ServiceChecklistItemModel.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }

  ServiceChecklistTemplateModel copyWith({
    List<ServiceChecklistItemModel>? items,
  }) {
    return ServiceChecklistTemplateModel(
      id: id,
      templateId: templateId,
      title: title,
      category: category,
      phase: phase,
      items: items ?? this.items,
    );
  }
}

class ServiceChecklistBundleModel {
  final String serviceId;
  final String currentPhase;
  final String orderState;
  final String categoryCode;
  final String categoryLabel;
  final List<ServiceChecklistTemplateModel> templates;

  const ServiceChecklistBundleModel({
    required this.serviceId,
    required this.currentPhase,
    required this.orderState,
    required this.categoryCode,
    required this.categoryLabel,
    required this.templates,
  });

  factory ServiceChecklistBundleModel.fromJson(Map<String, dynamic> json) {
    final category =
        (json['category'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawTemplates = json['templates'];
    return ServiceChecklistBundleModel(
      serviceId: (json['serviceId'] ?? '').toString(),
      currentPhase: (json['currentPhase'] ?? '').toString(),
      orderState: (json['orderState'] ?? '').toString(),
      categoryCode: (category['code'] ?? '').toString(),
      categoryLabel: (category['label'] ?? '').toString(),
      templates: rawTemplates is List
          ? rawTemplates
                .whereType<Map>()
                .map(
                  (item) => ServiceChecklistTemplateModel.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class OperationsDashboardModel {
  final int installationsPendingToday;
  final int warrantiesOpen;
  final double averageHoursByLifecycle;
  final Map<String, int> activeByStatus;
  final List<Map<String, dynamic>> technicianPerformance;

  OperationsDashboardModel({
    required this.installationsPendingToday,
    required this.warrantiesOpen,
    required this.averageHoursByLifecycle,
    required this.activeByStatus,
    required this.technicianPerformance,
  });

  factory OperationsDashboardModel.empty() => OperationsDashboardModel(
    installationsPendingToday: 0,
    warrantiesOpen: 0,
    averageHoursByLifecycle: 0,
    activeByStatus: const {},
    technicianPerformance: const [],
  );

  factory OperationsDashboardModel.fromJson(Map<String, dynamic> json) {
    final byStatusRaw = json['activeByStatus'];
    final byStatus = <String, int>{};
    if (byStatusRaw is List) {
      for (final row in byStatusRaw.whereType<Map>()) {
        final item = row.cast<String, dynamic>();
        byStatus[(item['status'] ?? '').toString()] =
            int.tryParse('${item['count']}') ?? 0;
      }
    }

    final perfRaw = json['technicianPerformance'];
    final perf = perfRaw is List
        ? perfRaw
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList()
        : <Map<String, dynamic>>[];

    return OperationsDashboardModel(
      installationsPendingToday:
          int.tryParse('${json['installationsPendingToday']}') ?? 0,
      warrantiesOpen: int.tryParse('${json['warrantiesOpen']}') ?? 0,
      averageHoursByLifecycle:
          double.tryParse('${json['averageHoursByLifecycle']}') ?? 0,
      activeByStatus: byStatus,
      technicianPerformance: perf,
    );
  }
}

class ServicesPageModel {
  final List<ServiceModel> items;
  final int total;
  final int page;
  final int pageSize;

  ServicesPageModel({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory ServicesPageModel.fromJson(Map<String, dynamic> json) {
    final listRaw = json['items'];
    final items = listRaw is List
        ? listRaw
              .whereType<Map>()
              .map((row) => ServiceModel.fromJson(row.cast<String, dynamic>()))
              .toList()
        : <ServiceModel>[];

    return ServicesPageModel(
      items: items,
      total: int.tryParse('${json['total']}') ?? items.length,
      page: int.tryParse('${json['page']}') ?? 1,
      pageSize: int.tryParse('${json['pageSize']}') ?? 30,
    );
  }
}
