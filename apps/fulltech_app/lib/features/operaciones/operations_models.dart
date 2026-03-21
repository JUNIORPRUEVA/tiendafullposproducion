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

String normalizeOperationsKey(String raw) {
  var value = raw.trim().toLowerCase();
  if (value.isEmpty) return '';

  value = value
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n');

  return value.replaceAll(' ', '_').replaceAll('-', '_');
}

String _canonicalPhaseKey(String raw) {
  final value = normalizeOperationsKey(raw);
  if (value.isEmpty) return '';
  if (value.contains('levantamiento') || value.contains('survey')) {
    return 'levantamiento';
  }
  if (value.contains('garantia') || value.contains('warranty')) {
    return 'garantia';
  }
  if (value.contains('instalacion') || value.contains('installation')) {
    return 'instalacion';
  }
  if (value.contains('mantenimiento') || value.contains('maintenance')) {
    return 'mantenimiento';
  }
  if (value.contains('reserva') || value.contains('reserved')) {
    return 'reserva';
  }
  return value;
}

String _canonicalStatusKey(String raw) {
  final value = normalizeOperationsKey(raw);
  if (value.isEmpty) return '';

  switch (value) {
    case 'pending':
    case 'pendiente':
    case 'reserved':
    case 'reserva':
    case 'scheduled':
    case 'confirmed':
    case 'confirmada':
    case 'confirmado':
    case 'assigned':
    case 'asignada':
    case 'asignado':
    case 'rescheduled':
    case 'reagendada':
    case 'reagendado':
    case 'survey':
    case 'levantamiento':
      return 'pendiente';
    case 'en_camino':
      return 'en_camino';
    case 'in_progress':
    case 'en_proceso':
    case 'enproceso':
      return 'en_proceso';
    case 'completed':
    case 'completado':
    case 'finalized':
    case 'finalizado':
    case 'finalizada':
      return 'finalizada';
    case 'closed':
    case 'cerrado':
    case 'cerrada':
      return 'cerrada';
    case 'cancelled':
    case 'canceled':
    case 'cancelado':
    case 'cancelada':
      return 'cancelada';
    default:
      return value;
  }
}

String canonicalServicePhaseFromJson(Map<String, dynamic> json) {
  final candidates = <String>[
    (json['phase'] ?? '').toString(),
    (json['currentPhase'] ?? '').toString(),
    (json['orderType'] ?? '').toString(),
    (json['serviceType'] ?? '').toString(),
  ];

  for (final candidate in candidates) {
    final key = _canonicalPhaseKey(candidate);
    if (key == 'reserva' ||
        key == 'instalacion' ||
        key == 'mantenimiento' ||
        key == 'levantamiento' ||
        key == 'garantia') {
      return key;
    }
  }

  return 'reserva';
}

String canonicalServiceStatusFromJson(Map<String, dynamic> json) {
  final candidates = <String>[
    (json['adminStatus'] ?? '').toString(),
    (json['orderState'] ?? '').toString(),
    (json['status'] ?? '').toString(),
  ];

  for (final candidate in candidates) {
    final key = _canonicalStatusKey(candidate);
    if (key.isNotEmpty) return key;
  }

  return 'pendiente';
}

String effectiveServicePhaseKey(ServiceModel service) {
  final candidates = <String>[
    service.phase,
    service.currentPhase,
    service.orderType,
    service.serviceType,
  ];

  for (final candidate in candidates) {
    final key = _canonicalPhaseKey(candidate);
    if (key == 'reserva' ||
        key == 'instalacion' ||
        key == 'mantenimiento' ||
        key == 'levantamiento' ||
        key == 'garantia') {
      return key;
    }
  }

  return _canonicalPhaseKey(service.currentPhase);
}

String effectiveServicePhaseLabel(ServiceModel service) {
  return switch (effectiveServicePhaseKey(service)) {
    'reserva' => 'Reserva',
    'instalacion' => 'Instalación',
    'mantenimiento' => 'Mantenimiento',
    'levantamiento' => 'Levantamiento',
    'garantia' => 'Garantía',
    _ => phaseLabel(service.currentPhase),
  };
}

String effectiveServiceStatusKey(ServiceModel service) {
  final candidates = <String>[
    service.adminStatus ?? '',
    service.orderState,
    service.status,
  ];

  for (final candidate in candidates) {
    final value = _canonicalStatusKey(candidate);
    if (value.isNotEmpty) return value;
  }

  return 'pendiente';
}

String effectiveServiceStatusLabel(ServiceModel service) {
  return switch (effectiveServiceStatusKey(service)) {
    'pendiente' => 'Pendiente',
    'en_camino' => 'En camino',
    'en_proceso' => 'En proceso',
    'finalizada' => 'Finalizada',
    'cerrada' => 'Cerrada',
    'cancelada' => 'Cancelada',
    _ =>
      (service.adminStatus ?? '').trim().isNotEmpty
          ? service.adminStatus!.trim()
          : service.orderState.trim().isNotEmpty
          ? service.orderState.trim()
          : service.status.trim(),
  };
}

String effectiveServiceCategoryCode(ServiceModel service) {
  return normalizeOperationsKey(service.category);
}

String effectiveServiceCategoryLabel(ServiceModel service) {
  return localizedServiceCategoryFromParts(
    categoryName: service.categoryName,
    categoryCode: service.category,
    fallbackCategory: service.category,
  );
}

bool serviceCanonicalFieldsDiffer(ServiceModel left, ServiceModel right) {
  if (left.id.trim() != right.id.trim()) return true;
  return effectiveServicePhaseKey(left) != effectiveServicePhaseKey(right) ||
      effectiveServiceStatusKey(left) != effectiveServiceStatusKey(right) ||
      effectiveServiceCategoryCode(left) != effectiveServiceCategoryCode(right);
}

void debugAssertServiceSync({
  required String source,
  required ServiceModel expected,
  required ServiceModel actual,
}) {
  assert(() {
    if (serviceCanonicalFieldsDiffer(expected, actual)) {
      throw StateError(
        'State desync detected [$source] '
        'expected phase=${effectiveServicePhaseKey(expected)} '
        'status=${effectiveServiceStatusKey(expected)} '
        'category=${effectiveServiceCategoryCode(expected)} '
        'actual phase=${effectiveServicePhaseKey(actual)} '
        'status=${effectiveServiceStatusKey(actual)} '
        'category=${effectiveServiceCategoryCode(actual)}',
      );
    }
    return true;
  }());
}

String phaseLabel(dynamic raw) {
  if (raw == null) return '—';
  var value = raw.toString().trim();
  if (value.isEmpty) return '—';

  value = value.toLowerCase();
  value = value.replaceAll(' ', '_').replaceAll('-', '_');

  switch (value) {
    case 'reserved':
    case 'reserva':
      return 'Reserva';
    case 'survey':
    case 'levantamiento':
      return 'Levantamiento';
    case 'installation':
    case 'instalacion':
      return 'Instalación';
    case 'maintenance':
    case 'mantenimiento':
      return 'Mantenimiento';
    case 'warranty':
    case 'garantia':
      return 'Garantía';
    case 'completed':
    case 'finalizado':
    case 'finalizada':
      return 'Finalizado';
    case 'cancelled':
    case 'canceled':
    case 'cancelado':
    case 'cancelada':
      return 'Cancelado';
    default:
      return value;
  }
}

String localizedServiceCategoryLabel(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'General';

  var value = trimmed.toLowerCase();
  value = value
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n');
  value = value.replaceAll(' ', '_').replaceAll('-', '_');

  switch (value) {
    case 'cameras':
      return 'Cámaras';
    case 'gate_motor':
      return 'Motores de portón';
    case 'alarm':
      return 'Alarma';
    case 'electric_fence':
      return 'Cerco eléctrico';
    case 'intercom':
      return 'Intercom';
    case 'pos':
    case 'point_of_sale':
    case 'punto_de_ventas':
      return 'Punto de ventas';
    case 'general':
      return 'General';
    default:
      return trimmed;
  }
}

String localizedServiceCategoryFromParts({
  String? categoryName,
  String? categoryCode,
  String? fallbackCategory,
}) {
  final candidates = [categoryName, categoryCode, fallbackCategory];
  for (final candidate in candidates) {
    final text = (candidate ?? '').trim();
    if (text.isEmpty) continue;
    final translated = localizedServiceCategoryLabel(text);
    if (translated.isNotEmpty) return translated;
  }
  return 'General';
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
  final String? categoryId;
  final String? categoryName;
  final String phase;
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
  final String? surveyResult;
  final String? materialsUsed;
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
  final List<ServiceFileModel> evidences;
  final List<ServiceUpdateModel> updates;
  final ServiceClosingSummaryModel? closing;

  ServiceModel({
    required this.id,
    this.orderNumber = '',
    required this.title,
    required this.description,
    required this.serviceType,
    required this.category,
    this.categoryId,
    this.categoryName,
    required this.phase,
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
    required this.evidences,
    required this.updates,
    this.closing,
    this.technicianId,
    this.quotedAmount,
    this.depositAmount,
    this.finalCost,
    this.surveyResult,
    this.materialsUsed,
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

  String get categoryLabel {
    return localizedServiceCategoryFromParts(
      categoryName: categoryName,
      categoryCode: category,
      fallbackCategory: category,
    );
  }

  ServiceModel copyWith({
    String? orderNumber,
    String? title,
    String? description,
    String? serviceType,
    String? category,
    String? categoryId,
    String? categoryName,
    String? phase,
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
    String? surveyResult,
    String? materialsUsed,
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
    List<ServiceFileModel>? evidences,
    List<ServiceUpdateModel>? updates,
    ServiceClosingSummaryModel? closing,
  }) {
    final nextPhase = phase ?? currentPhase ?? this.phase;
    final nextCurrentPhase = currentPhase ?? phase ?? this.currentPhase;
    final nextStatus = status ?? this.status;
    final nextAdminStatus = adminStatus ?? this.adminStatus;
    final nextOrderType = orderType ?? this.orderType;
    final nextOrderState = orderState ?? this.orderState;

    return ServiceModel(
      id: id,
      orderNumber: orderNumber ?? this.orderNumber,
      title: title ?? this.title,
      description: description ?? this.description,
      serviceType: serviceType ?? this.serviceType,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      phase: nextPhase,
      status: nextStatus,
      currentPhase: nextCurrentPhase,
      orderType: nextOrderType,
      orderState: nextOrderState,
      adminPhase: adminPhase ?? this.adminPhase,
      adminStatus: nextAdminStatus,
      technicianId: technicianId ?? this.technicianId,
      priority: priority ?? this.priority,
      quotedAmount: quotedAmount ?? this.quotedAmount,
      depositAmount: depositAmount ?? this.depositAmount,
      finalCost: finalCost ?? this.finalCost,
      surveyResult: surveyResult ?? this.surveyResult,
      materialsUsed: materialsUsed ?? this.materialsUsed,
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
      evidences: evidences ?? this.evidences,
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

    String? parseOrderExtraString(dynamic raw, String key) {
      if (raw is! Map) return null;
      final value = raw[key];
      final text = (value ?? '').toString().trim();
      return text.isEmpty ? null : text;
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
    final parsedFiles = parseList(json['files'], ServiceFileModel.fromJson);
    final parsedEvidences = parseList(
      json['evidences'],
      ServiceFileModel.fromJson,
    );
    final phase = canonicalServicePhaseFromJson(json);
    final currentPhase = (json['currentPhase'] ?? '').toString().trim();
    final rawOrderType = (json['orderType'] ?? '').toString().trim();
    final status = canonicalServiceStatusFromJson(json);
    final rawAdminStatus = (json['adminStatus'] ?? '').toString().trim();
    final rawOrderState = (json['orderState'] ?? '').toString().trim();

    return ServiceModel(
      id: (json['id'] ?? '').toString(),
      orderNumber: (json['orderNumber'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      serviceType: (json['serviceType'] ?? 'other').toString(),
      category: (json['category'] ?? '').toString(),
      categoryId: json['categoryId']?.toString(),
      categoryName: json['categoryName']?.toString(),
      phase: phase,
      status: status,
      currentPhase: currentPhase.isEmpty ? phase : currentPhase,
      orderType: rawOrderType.isEmpty ? phase : rawOrderType,
      orderState: rawOrderState.isEmpty ? status : rawOrderState,
      adminPhase: json['adminPhase'] == null
          ? null
          : (json['adminPhase'] ?? '').toString(),
      adminStatus: rawAdminStatus.isEmpty ? status : rawAdminStatus,
      technicianId: json['technicianId'] == null
          ? null
          : (json['technicianId'] ?? '').toString(),
      priority: (json['priority'] is int)
          ? json['priority'] as int
          : int.tryParse('${json['priority']}') ?? 2,
      quotedAmount: parseMoney(json['quotedAmount']),
      depositAmount: parseMoney(json['depositAmount']),
      finalCost: parseFinalCost(json['orderExtras']),
      surveyResult: parseOrderExtraString(json['orderExtras'], 'surveyResult'),
      materialsUsed: parseOrderExtraString(
        json['orderExtras'],
        'materialsUsed',
      ),
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
      files: parsedFiles,
      evidences: parsedEvidences.isNotEmpty
          ? parsedEvidences
          : parsedFiles
                .where((file) {
                  final type = file.fileType.trim().toLowerCase();
                  final mime = (file.mimeType ?? '').trim().toLowerCase();
                  return type == 'evidence_final' ||
                      type == 'video_evidence' ||
                      mime.startsWith('image/') ||
                      mime.startsWith('video/');
                })
                .toList(growable: false),
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

  String get displayName {
    return localizedServiceCategoryFromParts(
      categoryName: name,
      categoryCode: code,
      fallbackCategory: id,
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

enum WarrantyDurationUnitModel { days, months, years }

WarrantyDurationUnitModel warrantyDurationUnitFromRaw(dynamic raw) {
  switch ((raw ?? '').toString().trim().toUpperCase()) {
    case 'DAYS':
      return WarrantyDurationUnitModel.days;
    case 'YEARS':
      return WarrantyDurationUnitModel.years;
    case 'MONTHS':
    default:
      return WarrantyDurationUnitModel.months;
  }
}

String warrantyDurationUnitCode(WarrantyDurationUnitModel unit) {
  switch (unit) {
    case WarrantyDurationUnitModel.days:
      return 'DAYS';
    case WarrantyDurationUnitModel.months:
      return 'MONTHS';
    case WarrantyDurationUnitModel.years:
      return 'YEARS';
  }
}

String warrantyDurationUnitLabel(WarrantyDurationUnitModel unit) {
  switch (unit) {
    case WarrantyDurationUnitModel.days:
      return 'Días';
    case WarrantyDurationUnitModel.months:
      return 'Meses';
    case WarrantyDurationUnitModel.years:
      return 'Años';
  }
}

class WarrantyProductConfigModel {
  final String id;
  final String? categoryId;
  final String? categoryCode;
  final String? categoryName;
  final String? productName;
  final bool hasWarranty;
  final int? durationValue;
  final WarrantyDurationUnitModel? durationUnit;
  final String? warrantySummary;
  final String? coverageSummary;
  final String? exclusionsSummary;
  final String? notes;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String scopeLabel;

  const WarrantyProductConfigModel({
    required this.id,
    required this.hasWarranty,
    required this.isActive,
    required this.scopeLabel,
    this.categoryId,
    this.categoryCode,
    this.categoryName,
    this.productName,
    this.durationValue,
    this.durationUnit,
    this.warrantySummary,
    this.coverageSummary,
    this.exclusionsSummary,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory WarrantyProductConfigModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    String? parseText(dynamic raw) {
      final value = (raw ?? '').toString().trim();
      return value.isEmpty ? null : value;
    }

    return WarrantyProductConfigModel(
      id: (json['id'] ?? '').toString(),
      categoryId: parseText(json['categoryId']),
      categoryCode: parseText(json['categoryCode']),
      categoryName: parseText(json['categoryName']),
      productName: parseText(json['productName']),
      hasWarranty: json['hasWarranty'] != false,
      durationValue: (json['durationValue'] as num?)?.toInt(),
      durationUnit: json['durationUnit'] == null
          ? null
          : warrantyDurationUnitFromRaw(json['durationUnit']),
      warrantySummary: parseText(json['warrantySummary']),
      coverageSummary: parseText(json['coverageSummary']),
      exclusionsSummary: parseText(json['exclusionsSummary']),
      notes: parseText(json['notes']),
      isActive: json['isActive'] != false,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      scopeLabel:
          parseText(json['scopeLabel']) ??
          parseText(json['productName']) ??
          'Garantía general',
    );
  }

  String get durationLabel {
    if (!hasWarranty) return 'Sin garantía comercial adicional';
    if (durationValue == null || durationUnit == null || durationValue! <= 0) {
      return 'Garantía según configuración';
    }
    return '$durationValue ${warrantyDurationUnitLabel(durationUnit!)}';
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

enum ServiceChecklistSectionType { herramientas, productos, instalacion }

ServiceChecklistSectionType serviceChecklistSectionTypeFromRaw(dynamic raw) {
  final value = (raw ?? '').toString().trim().toLowerCase();
  switch (value) {
    case 'herramientas':
      return ServiceChecklistSectionType.herramientas;
    case 'productos':
      return ServiceChecklistSectionType.productos;
    case 'instalacion':
    default:
      return ServiceChecklistSectionType.instalacion;
  }
}

String serviceChecklistSectionTypeCode(ServiceChecklistSectionType type) {
  switch (type) {
    case ServiceChecklistSectionType.herramientas:
      return 'herramientas';
    case ServiceChecklistSectionType.productos:
      return 'productos';
    case ServiceChecklistSectionType.instalacion:
      return 'instalacion';
  }
}

String serviceChecklistSectionTypeLabel(ServiceChecklistSectionType type) {
  switch (type) {
    case ServiceChecklistSectionType.herramientas:
      return 'Herramientas';
    case ServiceChecklistSectionType.productos:
      return 'Productos';
    case ServiceChecklistSectionType.instalacion:
      return 'Instalación';
  }
}

class ServiceChecklistTemplateModel {
  final String id;
  final String templateId;
  final ServiceChecklistSectionType type;
  final String title;
  final ServiceChecklistCategoryModel category;
  final ServiceChecklistPhaseModel phase;
  final List<ServiceChecklistItemModel> items;

  const ServiceChecklistTemplateModel({
    required this.id,
    required this.templateId,
    required this.type,
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
      type: serviceChecklistSectionTypeFromRaw(json['type']),
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
      type: type,
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
    List<ServiceChecklistTemplateModel> parseTemplates(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map(
            (item) => ServiceChecklistTemplateModel.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(growable: false);
    }

    final templates = parseTemplates(rawTemplates);
    return ServiceChecklistBundleModel(
      serviceId: (json['serviceId'] ?? '').toString(),
      currentPhase: (json['currentPhase'] ?? '').toString(),
      orderState: (json['orderState'] ?? '').toString(),
      categoryCode: (category['code'] ?? '').toString(),
      categoryLabel: (category['label'] ?? '').toString(),
      templates: templates,
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
