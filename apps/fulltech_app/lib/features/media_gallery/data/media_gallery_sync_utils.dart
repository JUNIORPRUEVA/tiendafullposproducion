import '../media_gallery_models.dart';

List<MediaGalleryItem> mergeMediaGalleryItems({
  required List<MediaGalleryItem> previousItems,
  required List<MediaGalleryItem> freshItems,
}) {
  final itemsById = <String, MediaGalleryItem>{
    for (final item in previousItems) item.id: item,
  };
  for (final item in freshItems) {
    itemsById[item.id] = item;
  }

  final merged = itemsById.values.toList(growable: false)
    ..sort((a, b) {
      final createdAtCompare = b.createdAt.compareTo(a.createdAt);
      if (createdAtCompare != 0) return createdAtCompare;
      return b.id.compareTo(a.id);
    });
  return merged;
}