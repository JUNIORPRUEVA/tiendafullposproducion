import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../clientes/cliente_model.dart';

enum ServiceOrderCategory {
  camara,
  motorPorton,
  alarma,
  cercoElectrico,
  intercom,
  puntoVenta,
}

enum ServiceOrderType { instalacion, mantenimiento, levantamiento, garantia }

enum ServiceOrderStatus { pendiente, enProceso, finalizado, cancelado }

enum ServiceEvidenceType {
  referenciaTexto,
  referenciaImagen,
  referenciaVideo,
  evidenciaTexto,
  evidenciaImagen,
  evidenciaVideo,
}

enum ServiceReportType {
  requerimientoCliente,
  servicioFinalizado,
  otros,
}

ServiceOrderCategory serviceOrderCategoryFromApi(String value) {
  switch (value.trim()) {
    case 'camara':
      return ServiceOrderCategory.camara;
    case 'motor_porton':
      return ServiceOrderCategory.motorPorton;
    case 'alarma':
      return ServiceOrderCategory.alarma;
    case 'cerco_electrico':
      return ServiceOrderCategory.cercoElectrico;
    case 'intercom':
      return ServiceOrderCategory.intercom;
    case 'punto_venta':
      return ServiceOrderCategory.puntoVenta;
    default:
      return ServiceOrderCategory.camara;
  }
}

ServiceOrderType serviceOrderTypeFromApi(String value) {
  switch (value.trim()) {
    case 'instalacion':
      return ServiceOrderType.instalacion;
    case 'mantenimiento':
      return ServiceOrderType.mantenimiento;
    case 'levantamiento':
      return ServiceOrderType.levantamiento;
    case 'garantia':
      return ServiceOrderType.garantia;
    default:
      return ServiceOrderType.instalacion;
  }
}

ServiceOrderStatus serviceOrderStatusFromApi(String value) {
  switch (value.trim()) {
    case 'pendiente':
      return ServiceOrderStatus.pendiente;
    case 'en_proceso':
      return ServiceOrderStatus.enProceso;
    case 'finalizado':
      return ServiceOrderStatus.finalizado;
    case 'cancelado':
      return ServiceOrderStatus.cancelado;
    default:
      return ServiceOrderStatus.pendiente;
  }
}

ServiceEvidenceType serviceEvidenceTypeFromApi(String value) {
  switch (value.trim()) {
    case 'referencia_texto':
      return ServiceEvidenceType.referenciaTexto;
    case 'referencia_imagen':
      return ServiceEvidenceType.referenciaImagen;
    case 'referencia_video':
      return ServiceEvidenceType.referenciaVideo;
    case 'evidencia_texto':
      return ServiceEvidenceType.evidenciaTexto;
    case 'evidencia_imagen':
      return ServiceEvidenceType.evidenciaImagen;
    case 'evidencia_video':
      return ServiceEvidenceType.evidenciaVideo;
    default:
      return ServiceEvidenceType.referenciaTexto;
  }
}

ServiceReportType serviceReportTypeFromApi(String value) {
  switch (value.trim()) {
    case 'requerimiento_cliente':
      return ServiceReportType.requerimientoCliente;
    case 'servicio_finalizado':
      return ServiceReportType.servicioFinalizado;
    case 'otros':
    default:
      return ServiceReportType.otros;
  }
}

extension ServiceOrderCategoryX on ServiceOrderCategory {
  String get apiValue {
    switch (this) {
      case ServiceOrderCategory.camara:
        return 'camara';
      case ServiceOrderCategory.motorPorton:
        return 'motor_porton';
      case ServiceOrderCategory.alarma:
        return 'alarma';
      case ServiceOrderCategory.cercoElectrico:
        return 'cerco_electrico';
      case ServiceOrderCategory.intercom:
        return 'intercom';
      case ServiceOrderCategory.puntoVenta:
        return 'punto_venta';
    }
  }

  String get label {
    switch (this) {
      case ServiceOrderCategory.camara:
        return 'Cámara';
      case ServiceOrderCategory.motorPorton:
        return 'Motor portón';
      case ServiceOrderCategory.alarma:
        return 'Alarma';
      case ServiceOrderCategory.cercoElectrico:
        return 'Cerco eléctrico';
      case ServiceOrderCategory.intercom:
        return 'Intercom';
      case ServiceOrderCategory.puntoVenta:
        return 'Punto de venta';
    }
  }
}

extension ServiceOrderTypeX on ServiceOrderType {
  String get apiValue {
    switch (this) {
      case ServiceOrderType.instalacion:
        return 'instalacion';
      case ServiceOrderType.mantenimiento:
        return 'mantenimiento';
      case ServiceOrderType.levantamiento:
        return 'levantamiento';
      case ServiceOrderType.garantia:
        return 'garantia';
    }
  }

  String get label {
    switch (this) {
      case ServiceOrderType.instalacion:
        return 'Instalación';
      case ServiceOrderType.mantenimiento:
        return 'Mantenimiento';
      case ServiceOrderType.levantamiento:
        return 'Levantamiento';
      case ServiceOrderType.garantia:
        return 'Garantía';
    }
  }
}

extension ServiceOrderStatusX on ServiceOrderStatus {
  String get apiValue {
    switch (this) {
      case ServiceOrderStatus.pendiente:
        return 'pendiente';
      case ServiceOrderStatus.enProceso:
        return 'en_proceso';
      case ServiceOrderStatus.finalizado:
        return 'finalizado';
      case ServiceOrderStatus.cancelado:
        return 'cancelado';
    }
  }

  String get label {
    switch (this) {
      case ServiceOrderStatus.pendiente:
        return 'Pendiente';
      case ServiceOrderStatus.enProceso:
        return 'En proceso';
      case ServiceOrderStatus.finalizado:
        return 'Finalizado';
      case ServiceOrderStatus.cancelado:
        return 'Cancelado';
    }
  }

  Color get color {
    switch (this) {
      case ServiceOrderStatus.pendiente:
        return const Color(0xFFD98324);
      case ServiceOrderStatus.enProceso:
        return const Color(0xFF1D5D9B);
      case ServiceOrderStatus.finalizado:
        return const Color(0xFF2E8B57);
      case ServiceOrderStatus.cancelado:
        return const Color(0xFFB3261E);
    }
  }

  List<ServiceOrderStatus> get allowedNextStatuses {
    switch (this) {
      case ServiceOrderStatus.pendiente:
        return const [
          ServiceOrderStatus.enProceso,
          ServiceOrderStatus.cancelado,
        ];
      case ServiceOrderStatus.enProceso:
        return const [
          ServiceOrderStatus.finalizado,
          ServiceOrderStatus.cancelado,
        ];
      case ServiceOrderStatus.finalizado:
      case ServiceOrderStatus.cancelado:
        return const [];
    }
  }
}

extension ServiceEvidenceTypeX on ServiceEvidenceType {
  String get apiValue {
    switch (this) {
      case ServiceEvidenceType.referenciaTexto:
        return 'referencia_texto';
      case ServiceEvidenceType.referenciaImagen:
        return 'referencia_imagen';
      case ServiceEvidenceType.referenciaVideo:
        return 'referencia_video';
      case ServiceEvidenceType.evidenciaTexto:
        return 'evidencia_texto';
      case ServiceEvidenceType.evidenciaImagen:
        return 'evidencia_imagen';
      case ServiceEvidenceType.evidenciaVideo:
        return 'evidencia_video';
    }
  }

  String get label {
    switch (this) {
      case ServiceEvidenceType.referenciaTexto:
        return 'Referencia en texto';
      case ServiceEvidenceType.referenciaImagen:
        return 'Referencia en imagen';
      case ServiceEvidenceType.referenciaVideo:
        return 'Referencia en video';
      case ServiceEvidenceType.evidenciaTexto:
        return 'Evidencia en texto';
      case ServiceEvidenceType.evidenciaImagen:
        return 'Evidencia en imagen';
      case ServiceEvidenceType.evidenciaVideo:
        return 'Evidencia en video';
    }
  }

  bool get isReference {
    return this == ServiceEvidenceType.referenciaTexto ||
        this == ServiceEvidenceType.referenciaImagen ||
        this == ServiceEvidenceType.referenciaVideo;
  }

  bool get isTechnicalEvidence => !isReference;

  bool get isText {
    return this == ServiceEvidenceType.referenciaTexto ||
        this == ServiceEvidenceType.evidenciaTexto;
  }

  bool get isImage {
    return this == ServiceEvidenceType.referenciaImagen ||
        this == ServiceEvidenceType.evidenciaImagen;
  }

  bool get isVideo {
    return this == ServiceEvidenceType.referenciaVideo ||
        this == ServiceEvidenceType.evidenciaVideo;
  }

  String get familyLabel => isReference ? 'Referencia' : 'Evidencia técnica';
}

class ServiceOrderEvidenceModel {
  final String id;
  final String serviceOrderId;
  final ServiceEvidenceType type;
  final String content;
  final String createdById;
  final DateTime createdAt;
  final String? localPath;
  final Uint8List? previewBytes;
  final String? fileName;
  final bool isPendingUpload;
  final bool hasUploadError;

  const ServiceOrderEvidenceModel({
    required this.id,
    required this.serviceOrderId,
    required this.type,
    required this.content,
    required this.createdById,
    required this.createdAt,
    this.localPath,
    this.previewBytes,
    this.fileName,
    this.isPendingUpload = false,
    this.hasUploadError = false,
  });

  factory ServiceOrderEvidenceModel.fromJson(Map<String, dynamic> json) {
    return ServiceOrderEvidenceModel(
      id: (json['id'] ?? '').toString(),
      serviceOrderId: (json['serviceOrderId'] ?? '').toString(),
      type: serviceEvidenceTypeFromApi((json['type'] ?? '').toString()),
      content: (json['content'] ?? '').toString(),
      createdById: (json['createdById'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      localPath: null,
      previewBytes: null,
      fileName: null,
      isPendingUpload: false,
      hasUploadError: false,
    );
  }

  ServiceOrderEvidenceModel copyWith({
    String? id,
    String? serviceOrderId,
    ServiceEvidenceType? type,
    String? content,
    String? createdById,
    DateTime? createdAt,
    String? localPath,
    Uint8List? previewBytes,
    String? fileName,
    bool? isPendingUpload,
    bool? hasUploadError,
    bool clearLocalPath = false,
    bool clearPreviewBytes = false,
    bool clearFileName = false,
  }) {
    return ServiceOrderEvidenceModel(
      id: id ?? this.id,
      serviceOrderId: serviceOrderId ?? this.serviceOrderId,
      type: type ?? this.type,
      content: content ?? this.content,
      createdById: createdById ?? this.createdById,
      createdAt: createdAt ?? this.createdAt,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      previewBytes: clearPreviewBytes ? null : (previewBytes ?? this.previewBytes),
      fileName: clearFileName ? null : (fileName ?? this.fileName),
      isPendingUpload: isPendingUpload ?? this.isPendingUpload,
      hasUploadError: hasUploadError ?? this.hasUploadError,
    );
  }
}

extension ServiceReportTypeX on ServiceReportType {
  String get apiValue {
    switch (this) {
      case ServiceReportType.requerimientoCliente:
        return 'requerimiento_cliente';
      case ServiceReportType.servicioFinalizado:
        return 'servicio_finalizado';
      case ServiceReportType.otros:
        return 'otros';
    }
  }

  String get label {
    switch (this) {
      case ServiceReportType.requerimientoCliente:
        return 'Requerimiento del cliente';
      case ServiceReportType.servicioFinalizado:
        return 'Reporte de servicio finalizado';
      case ServiceReportType.otros:
        return 'Otros';
    }
  }

  Color get color {
    switch (this) {
      case ServiceReportType.requerimientoCliente:
        return const Color(0xFFC2410C);
      case ServiceReportType.servicioFinalizado:
        return const Color(0xFF047857);
      case ServiceReportType.otros:
        return const Color(0xFF1D4ED8);
    }
  }
}

class ServiceOrderReportModel {
  final String id;
  final String serviceOrderId;
  final ServiceReportType type;
  final String report;
  final String createdById;
  final DateTime createdAt;

  const ServiceOrderReportModel({
    required this.id,
    required this.serviceOrderId,
    required this.type,
    required this.report,
    required this.createdById,
    required this.createdAt,
  });

  factory ServiceOrderReportModel.fromJson(Map<String, dynamic> json) {
    return ServiceOrderReportModel(
      id: (json['id'] ?? '').toString(),
      serviceOrderId: (json['serviceOrderId'] ?? '').toString(),
      type: serviceReportTypeFromApi((json['type'] ?? '').toString()),
      report: (json['report'] ?? '').toString(),
      createdById: (json['createdById'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class ServiceOrderModel {
  final String id;
  final String clientId;
  final ClienteModel? client;
  final String? quotationId;
  final ServiceOrderCategory category;
  final ServiceOrderType serviceType;
  final ServiceOrderStatus status;
  final String? technicalNote;
  final String? extraRequirements;
  final String? parentOrderId;
  final String createdById;
  final String? assignedToId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ServiceOrderEvidenceModel> evidences;
  final List<ServiceOrderReportModel> reports;

  const ServiceOrderModel({
    required this.id,
    required this.clientId,
    this.client,
    required this.quotationId,
    required this.category,
    required this.serviceType,
    required this.status,
    required this.technicalNote,
    required this.extraRequirements,
    required this.parentOrderId,
    required this.createdById,
    required this.assignedToId,
    required this.createdAt,
    required this.updatedAt,
    this.evidences = const [],
    this.reports = const [],
  });

  bool get isCloneSourceAllowed => status == ServiceOrderStatus.finalizado;
  List<ServiceOrderEvidenceModel> get referenceItems {
    return evidences.where((item) => item.type.isReference).toList(growable: false);
  }

  List<ServiceOrderEvidenceModel> get technicalEvidenceItems {
    return evidences
        .where((item) => item.type.isTechnicalEvidence)
        .toList(growable: false);
  }

  ServiceOrderModel copyWith({
    String? id,
    String? clientId,
    ClienteModel? client,
    String? quotationId,
    ServiceOrderCategory? category,
    ServiceOrderType? serviceType,
    ServiceOrderStatus? status,
    String? technicalNote,
    String? extraRequirements,
    String? parentOrderId,
    String? createdById,
    String? assignedToId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ServiceOrderEvidenceModel>? evidences,
    List<ServiceOrderReportModel>? reports,
    bool clearQuotationId = false,
    bool clearTechnicalNote = false,
    bool clearExtraRequirements = false,
    bool clearParentOrderId = false,
    bool clearAssignedToId = false,
    bool clearClient = false,
  }) {
    return ServiceOrderModel(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      client: clearClient ? null : (client ?? this.client),
      quotationId: clearQuotationId ? null : (quotationId ?? this.quotationId),
      category: category ?? this.category,
      serviceType: serviceType ?? this.serviceType,
      status: status ?? this.status,
      technicalNote: clearTechnicalNote
          ? null
          : (technicalNote ?? this.technicalNote),
      extraRequirements: clearExtraRequirements
          ? null
          : (extraRequirements ?? this.extraRequirements),
      parentOrderId: clearParentOrderId
          ? null
          : (parentOrderId ?? this.parentOrderId),
      createdById: createdById ?? this.createdById,
      assignedToId: clearAssignedToId
          ? null
          : (assignedToId ?? this.assignedToId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      evidences: evidences ?? this.evidences,
      reports: reports ?? this.reports,
    );
  }

  factory ServiceOrderModel.fromJson(Map<String, dynamic> json) {
    final rawEvidences = (json['evidences'] as List?) ?? const [];
    final rawReports = (json['reports'] as List?) ?? const [];
    return ServiceOrderModel(
      id: (json['id'] ?? '').toString(),
      clientId: (json['clientId'] ?? '').toString(),
      client: json['client'] is Map
          ? ClienteModel.fromJson((json['client'] as Map).cast<String, dynamic>())
          : null,
      quotationId: json['quotationId']?.toString(),
      category: serviceOrderCategoryFromApi((json['category'] ?? '').toString()),
      serviceType: serviceOrderTypeFromApi(
        (json['serviceType'] ?? '').toString(),
      ),
      status: serviceOrderStatusFromApi((json['status'] ?? '').toString()),
      technicalNote: json['technicalNote']?.toString(),
      extraRequirements: json['extraRequirements']?.toString(),
      parentOrderId: json['parentOrderId']?.toString(),
      createdById: (json['createdById'] ?? '').toString(),
      assignedToId: json['assignedToId']?.toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
          DateTime.now(),
      evidences: rawEvidences
          .whereType<Map>()
          .map(
            (row) =>
                ServiceOrderEvidenceModel.fromJson(row.cast<String, dynamic>()),
          )
          .toList(growable: false),
      reports: rawReports
          .whereType<Map>()
          .map(
            (row) =>
                ServiceOrderReportModel.fromJson(row.cast<String, dynamic>()),
          )
          .toList(growable: false),
    );
  }
}

class CreateServiceOrderRequest {
  final String clientId;
  final String quotationId;
  final ServiceOrderCategory category;
  final ServiceOrderType serviceType;
  final String? technicalNote;
  final String? extraRequirements;
  final String? assignedToId;

  const CreateServiceOrderRequest({
    required this.clientId,
    required this.quotationId,
    required this.category,
    required this.serviceType,
    this.technicalNote,
    this.extraRequirements,
    this.assignedToId,
  });

  Map<String, dynamic> toJson() {
    return {
      'clientId': clientId,
      'quotationId': quotationId,
      'category': category.apiValue,
      'serviceType': serviceType.apiValue,
      if ((technicalNote ?? '').trim().isNotEmpty)
        'technicalNote': technicalNote!.trim(),
      if ((extraRequirements ?? '').trim().isNotEmpty)
        'extraRequirements': extraRequirements!.trim(),
      if ((assignedToId ?? '').trim().isNotEmpty) 'assignedToId': assignedToId,
    };
  }
}

class UpdateServiceOrderRequest {
  final String clientId;
  final String quotationId;
  final ServiceOrderCategory category;
  final ServiceOrderType serviceType;
  final String? technicalNote;
  final String? extraRequirements;
  final String? assignedToId;

  const UpdateServiceOrderRequest({
    required this.clientId,
    required this.quotationId,
    required this.category,
    required this.serviceType,
    this.technicalNote,
    this.extraRequirements,
    this.assignedToId,
  });

  Map<String, dynamic> toJson() {
    return {
      'clientId': clientId,
      'quotationId': quotationId,
      'category': category.apiValue,
      'serviceType': serviceType.apiValue,
      'technicalNote': technicalNote?.trim().isEmpty == true
          ? null
          : technicalNote?.trim(),
      'extraRequirements': extraRequirements?.trim().isEmpty == true
          ? null
          : extraRequirements?.trim(),
      'assignedToId': assignedToId?.trim().isEmpty == true
          ? null
          : assignedToId?.trim(),
    };
  }
}

class CloneServiceOrderRequest {
  final ServiceOrderType serviceType;
  final String? technicalNote;
  final String? extraRequirements;
  final String? assignedToId;

  const CloneServiceOrderRequest({
    required this.serviceType,
    this.technicalNote,
    this.extraRequirements,
    this.assignedToId,
  });

  Map<String, dynamic> toJson() {
    return {
      'serviceType': serviceType.apiValue,
      if ((technicalNote ?? '').trim().isNotEmpty)
        'technicalNote': technicalNote!.trim(),
      if ((extraRequirements ?? '').trim().isNotEmpty)
        'extraRequirements': extraRequirements!.trim(),
      if ((assignedToId ?? '').trim().isNotEmpty) 'assignedToId': assignedToId,
    };
  }
}

class CreateServiceOrderEvidenceRequest {
  final ServiceEvidenceType type;
  final String content;

  const CreateServiceOrderEvidenceRequest({
    required this.type,
    required this.content,
  });

  Map<String, dynamic> toJson() {
    return {'type': type.apiValue, 'content': content.trim()};
  }
}

class ServiceOrderDraftReference {
  final String id;
  final ServiceEvidenceType type;
  final String content;
  final String? uploadedUrl;
  final Uint8List? previewBytes;
  final String? localPath;
  final String? fileName;
  final int? sizeBytes;
  final DateTime createdAt;

  const ServiceOrderDraftReference({
    required this.id,
    required this.type,
    required this.content,
    required this.createdAt,
    this.uploadedUrl,
    this.previewBytes,
    this.localPath,
    this.fileName,
    this.sizeBytes,
  });

  factory ServiceOrderDraftReference.text({
    required String id,
    required String content,
  }) {
    return ServiceOrderDraftReference(
      id: id,
      type: ServiceEvidenceType.referenciaTexto,
      content: content,
      createdAt: DateTime.now(),
    );
  }

  factory ServiceOrderDraftReference.video({
    required String id,
    required String uploadedUrl,
    String? localPath,
    String? fileName,
    int? sizeBytes,
  }) {
    return ServiceOrderDraftReference(
      id: id,
      type: ServiceEvidenceType.referenciaVideo,
      content: uploadedUrl,
      uploadedUrl: uploadedUrl,
      localPath: localPath,
      fileName: fileName,
      sizeBytes: sizeBytes,
      createdAt: DateTime.now(),
    );
  }

  factory ServiceOrderDraftReference.image({
    required String id,
    required String uploadedUrl,
    required String fileName,
    Uint8List? previewBytes,
    String? localPath,
    int? sizeBytes,
  }) {
    return ServiceOrderDraftReference(
      id: id,
      type: ServiceEvidenceType.referenciaImagen,
      content: uploadedUrl,
      uploadedUrl: uploadedUrl,
      previewBytes: previewBytes,
      localPath: localPath,
      fileName: fileName,
      sizeBytes: sizeBytes,
      createdAt: DateTime.now(),
    );
  }

  bool get isImage => type.isImage;
  bool get isVideo => type.isVideo;
  bool get isText => type.isText;
  bool get hasRemoteContent => (uploadedUrl ?? '').trim().isNotEmpty;
  String get referenceContent => isText ? content : ((uploadedUrl ?? content).trim());
  String get previewSource {
    final path = (localPath ?? '').trim();
    if (path.isNotEmpty) return path;
    return (uploadedUrl ?? content).trim();
  }
}

class ServiceOrderCreateArgs {
  final ServiceOrderModel? cloneSource;
  final ServiceOrderModel? editSource;

  const ServiceOrderCreateArgs({this.cloneSource, this.editSource});

  bool get isCloneMode => cloneSource != null;
  bool get isEditMode => editSource != null;
}