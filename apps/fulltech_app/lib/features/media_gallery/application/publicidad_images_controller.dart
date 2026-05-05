import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/publicidad_image_model.dart';
import 'publicidad_images_repository.dart';

// Provider for the repository
final publicidadImagesRepositoryProvider =
    Provider<PublicidadImagesRepository>((ref) {
  throw UnimplementedError(
    'publicidadImagesRepositoryProvider must be overridden',
  );
});

// StateNotifier for managing publicidad images
class PublicidadImagesController
    extends StateNotifier<AsyncValue<List<PublicidadImage>>> {
  final PublicidadImagesRepository _repository;

  PublicidadImagesController(this._repository)
      : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.getAll());
  }

  Future<void> create({
    required String url,
    String? caption,
  }) async {
    final currentState = state;
    if (!currentState.hasValue) return;

    final image = await _repository.create(url: url, caption: caption);
    final items = [...currentState.value!, image];
    state = AsyncValue.data(items);
  }

  Future<void> delete(String id) async {
    final currentState = state;
    if (!currentState.hasValue) return;

    await _repository.delete(id);
    final items = currentState.value!.where((e) => e.id != id).toList();
    state = AsyncValue.data(items);
  }

  Future<void> update(String id, {String? caption}) async {
    final currentState = state;
    if (!currentState.hasValue) return;

    final updatedImage = await _repository.update(id, caption: caption);
    final items = currentState.value!.map((e) => e.id == id ? updatedImage : e).toList();
    state = AsyncValue.data(items);
  }

  Future<UploadUrlResponse> generateUploadUrl(String filename) async {
    return _repository.generateUploadUrl(filename);
  }

  Future<void> uploadFileAndSave({
    required String filePath,
    required String contentType,
    required String filename,
    String? caption,
  }) async {
    // Get presigned URL
    final uploadUrl = await generateUploadUrl(filename);

    // Upload file to S3/R2
    await _repository.uploadFile(
      uploadUrl.uploadUrl,
      filePath,
      contentType,
    );

    // Create record in database with public URL
    await create(
      url: uploadUrl.publicUrl,
      caption: caption,
    );
  }
}

// Provider for the controller
final publicidadImagesControllerProvider = StateNotifierProvider<
    PublicidadImagesController,
    AsyncValue<List<PublicidadImage>>>((ref) {
  final repository = ref.watch(publicidadImagesRepositoryProvider);
  final controller = PublicidadImagesController(repository);
  controller.load();
  return controller;
});
