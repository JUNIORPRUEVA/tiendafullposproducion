import 'dart:convert';
import 'dart:typed_data';

class EstimatedProductItemModel {
  final String name;
  final int quantity;

  const EstimatedProductItemModel({required this.name, required this.quantity});

  factory EstimatedProductItemModel.fromJson(Map<String, dynamic> json) {
    final rawQty = json['quantity'];
    final qty = rawQty is num
        ? rawQty.toInt()
        : int.tryParse((rawQty ?? '').toString()) ?? 0;

    return EstimatedProductItemModel(
      name: (json['name'] ?? '').toString(),
      quantity: qty,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'quantity': quantity};
}

class ReplacementItemModel {
  final String description;

  const ReplacementItemModel({required this.description});

  factory ReplacementItemModel.fromJson(Map<String, dynamic> json) {
    return ReplacementItemModel(
      description: (json['description'] ?? json['name'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {'description': description};
}

class VisitClientSignatureModel {
  final String? fileId;
  final String? fileUrl;
  final DateTime? signedAt;
  final String? syncStatus;
  final String? syncError;
  final String? localPreviewBase64;

  const VisitClientSignatureModel({
    this.fileId,
    this.fileUrl,
    this.signedAt,
    this.syncStatus,
    this.syncError,
    this.localPreviewBase64,
  });

  bool get hasAnyValue {
    return (fileId ?? '').trim().isNotEmpty ||
        (fileUrl ?? '').trim().isNotEmpty ||
        (localPreviewBase64 ?? '').trim().isNotEmpty;
  }

  Uint8List? get previewBytes {
    final raw = (localPreviewBase64 ?? '').trim();
    if (raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  VisitClientSignatureModel copyWith({
    String? fileId,
    String? fileUrl,
    DateTime? signedAt,
    String? syncStatus,
    String? syncError,
    String? localPreviewBase64,
    bool clearSyncError = false,
  }) {
    return VisitClientSignatureModel(
      fileId: fileId ?? this.fileId,
      fileUrl: fileUrl ?? this.fileUrl,
      signedAt: signedAt ?? this.signedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      syncError: clearSyncError ? null : (syncError ?? this.syncError),
      localPreviewBase64: localPreviewBase64 ?? this.localPreviewBase64,
    );
  }

  Map<String, dynamic> toJson({bool includeLocalPreview = false}) {
    return {
      if ((fileId ?? '').trim().isNotEmpty) 'fileId': fileId!.trim(),
      if ((fileUrl ?? '').trim().isNotEmpty) 'fileUrl': fileUrl!.trim(),
      if (signedAt != null) 'signedAt': signedAt!.toIso8601String(),
      if ((syncStatus ?? '').trim().isNotEmpty)
        'syncStatus': syncStatus!.trim(),
      if ((syncError ?? '').trim().isNotEmpty) 'syncError': syncError!.trim(),
      if (includeLocalPreview && (localPreviewBase64 ?? '').trim().isNotEmpty)
        'localPreviewBase64': localPreviewBase64!.trim(),
    };
  }

  factory VisitClientSignatureModel.fromJson(Map<String, dynamic> json) {
    final signedAtRaw = json['signedAt'] ?? json['signed_at'];
    return VisitClientSignatureModel(
      fileId: json['fileId']?.toString() ?? json['file_id']?.toString(),
      fileUrl: json['fileUrl']?.toString() ?? json['file_url']?.toString(),
      signedAt: signedAtRaw == null
          ? null
          : DateTime.tryParse(signedAtRaw.toString()),
      syncStatus:
          json['syncStatus']?.toString() ?? json['sync_status']?.toString(),
      syncError:
          json['syncError']?.toString() ?? json['sync_error']?.toString(),
      localPreviewBase64:
          json['localPreviewBase64']?.toString() ??
          json['local_preview_base64']?.toString(),
    );
  }
}

class TechnicalVisitModel {
  final String id;
  final String orderId;
  final String technicianId;
  final String reportDescription;
  final String installationNotes;
  final List<EstimatedProductItemModel> estimatedProducts;
  final List<ReplacementItemModel> replacements;
  final List<String> photos;
  final List<String> videos;
  final VisitClientSignatureModel? clientSignature;
  final DateTime? visitDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TechnicalVisitModel({
    required this.id,
    required this.orderId,
    required this.technicianId,
    this.reportDescription = '',
    this.installationNotes = '',
    this.estimatedProducts = const [],
    this.replacements = const [],
    this.photos = const [],
    this.videos = const [],
    this.clientSignature,
    this.visitDate,
    this.createdAt,
    this.updatedAt,
  });

  static String _s(Map<String, dynamic> json, String key, {String? alt}) {
    final v = json[key] ?? (alt == null ? null : json[alt]);
    return (v ?? '').toString();
  }

  static DateTime? _dt(Map<String, dynamic> json, String key, {String? alt}) {
    final v = json[key] ?? (alt == null ? null : json[alt]);
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => (e ?? '').toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  static List<EstimatedProductItemModel> _products(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (m) => EstimatedProductItemModel.fromJson(m.cast<String, dynamic>()),
        )
        .where((p) => p.name.trim().isNotEmpty)
        .toList(growable: false);
  }

  static List<ReplacementItemModel> _replacements(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => ReplacementItemModel.fromJson(m.cast<String, dynamic>()))
        .where((item) => item.description.trim().isNotEmpty)
        .toList(growable: false);
  }

  factory TechnicalVisitModel.fromJson(Map<String, dynamic> json) {
    return TechnicalVisitModel(
      id: _s(json, 'id'),
      orderId: _s(
        json,
        'orderId',
        alt: json.containsKey('order_id') ? 'order_id' : 'service_id',
      ),
      technicianId: _s(json, 'technicianId', alt: 'technician_id'),
      reportDescription: _s(
        json,
        'reportDescription',
        alt: 'report_description',
      ),
      installationNotes: _s(
        json,
        'installationNotes',
        alt: 'installation_notes',
      ),
      estimatedProducts: _products(
        json['estimatedProducts'] ?? json['estimated_products'],
      ),
      replacements: _replacements(
        json['replacements'] ?? json['replacement_items'],
      ),
      photos: _stringList(json['photos']),
      videos: _stringList(json['videos']),
      clientSignature:
          (json['clientSignature'] ?? json['client_signature']) is Map
          ? VisitClientSignatureModel.fromJson(
              ((json['clientSignature'] ?? json['client_signature']) as Map)
                  .cast<String, dynamic>(),
            )
          : null,
      visitDate: _dt(json, 'visitDate', alt: 'visit_date'),
      createdAt: _dt(json, 'createdAt', alt: 'created_at'),
      updatedAt: _dt(json, 'updatedAt', alt: 'updated_at'),
    );
  }
}
