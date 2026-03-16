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

class TechnicalVisitModel {
  final String id;
  final String orderId;
  final String technicianId;
  final String reportDescription;
  final String installationNotes;
  final List<EstimatedProductItemModel> estimatedProducts;
  final List<String> photos;
  final List<String> videos;
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
    this.photos = const [],
    this.videos = const [],
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

  factory TechnicalVisitModel.fromJson(Map<String, dynamic> json) {
    return TechnicalVisitModel(
      id: _s(json, 'id'),
      orderId: _s(json, 'orderId', alt: 'order_id'),
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
      photos: _stringList(json['photos']),
      videos: _stringList(json['videos']),
      visitDate: _dt(json, 'visitDate', alt: 'visit_date'),
      createdAt: _dt(json, 'createdAt', alt: 'created_at'),
      updatedAt: _dt(json, 'updatedAt', alt: 'updated_at'),
    );
  }
}
