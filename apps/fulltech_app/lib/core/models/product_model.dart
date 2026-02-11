class ProductModel {
  final String id;
  final String nombre;
  final double precio;
  final double costo;
  final String? fotoUrl;
  final DateTime? createdAt;
  final String? categoria;

  ProductModel({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.costo,
    this.categoria,
    this.fotoUrl,
    this.createdAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] ?? '',
      nombre: json['nombre'] ?? '',
      precio: (json['precio'] is num) ? (json['precio'] as num).toDouble() : double.tryParse(json['precio']?.toString() ?? '') ?? 0,
      costo: (json['costo'] is num) ? (json['costo'] as num).toDouble() : double.tryParse(json['costo']?.toString() ?? '') ?? 0,
      categoria: json['categoria'] as String? ?? json['categoriaNombre'] as String?,
      fotoUrl: json['fotoUrl'] as String?,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
    );
  }

  String get categoriaLabel => (categoria == null || categoria!.isEmpty) ? 'Sin categoría' : categoria!;
}
