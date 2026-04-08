import '../../modules/service_orders/service_order_models.dart';

enum MediaGalleryAssetType { image, video }

enum MediaGalleryUploadedByRole { creator, technician }

enum MediaGalleryTypeFilter { all, image, video }

enum MediaGalleryInstallationFilter { all, completed, pending }

class MediaGalleryItem {
  const MediaGalleryItem({
    required this.id,
    required this.url,
    required this.type,
    required this.comment,
    required this.orderId,
    required this.createdAt,
    required this.uploadedByRole,
    required this.orderStatus,
    required this.isInstallationCompleted,
  });

  final String id;
  final String url;
  final MediaGalleryAssetType type;
  final String comment;
  final String orderId;
  final DateTime createdAt;
  final MediaGalleryUploadedByRole uploadedByRole;
  final ServiceOrderStatus orderStatus;
  final bool isInstallationCompleted;

  bool get isImage => type == MediaGalleryAssetType.image;
  bool get isVideo => type == MediaGalleryAssetType.video;

  String get displayComment {
    final value = comment.trim();
    if (value.isNotEmpty) return value;
    return uploadedByRole == MediaGalleryUploadedByRole.creator
        ? 'Referencia del cliente'
        : 'Evidencia técnica';
  }

  String get installationLabel => isInstallationCompleted ? 'Instalado' : 'Pendiente';

  String get orderStatusLabel {
    switch (orderStatus) {
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

  String get uploadedByLabel =>
      uploadedByRole == MediaGalleryUploadedByRole.creator
      ? 'Creador'
      : 'Técnico';

  factory MediaGalleryItem.fromJson(Map<String, dynamic> json) {
    return MediaGalleryItem(
      id: (json['id'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      type: (json['type'] ?? '').toString().trim().toLowerCase() == 'video'
          ? MediaGalleryAssetType.video
          : MediaGalleryAssetType.image,
      comment: (json['comment'] ?? '').toString(),
      orderId: (json['orderId'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      uploadedByRole:
          (json['uploadedByRole'] ?? '').toString().trim().toLowerCase() ==
              'technician'
          ? MediaGalleryUploadedByRole.technician
          : MediaGalleryUploadedByRole.creator,
      orderStatus: serviceOrderStatusFromApi(
        (json['orderStatus'] ?? '').toString(),
      ),
      isInstallationCompleted: json['isInstallationCompleted'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'type': isVideo ? 'video' : 'image',
      'comment': comment,
      'orderId': orderId,
      'createdAt': createdAt.toIso8601String(),
      'uploadedByRole': uploadedByRole == MediaGalleryUploadedByRole.creator
          ? 'creator'
          : 'technician',
      'orderStatus': orderStatus.apiValue,
      'isInstallationCompleted': isInstallationCompleted,
    };
  }
}

class MediaGalleryPage {
  const MediaGalleryPage({
    required this.items,
    required this.nextCursor,
    required this.limit,
  });

  final List<MediaGalleryItem> items;
  final String? nextCursor;
  final int limit;

  factory MediaGalleryPage.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return MediaGalleryPage(
      items: rawItems
          .whereType<Map>()
          .map((row) => MediaGalleryItem.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false),
      nextCursor: (json['nextCursor'] ?? '').toString().trim().isEmpty
          ? null
          : (json['nextCursor'] ?? '').toString(),
      limit: (json['limit'] as num?)?.toInt() ?? 48,
    );
  }
}