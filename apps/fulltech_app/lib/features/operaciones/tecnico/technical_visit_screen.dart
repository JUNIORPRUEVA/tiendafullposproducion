import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/app_drawer.dart';
import 'technical_visit_controller.dart';
import 'technical_visit_models.dart';

class TechnicalVisitScreen extends ConsumerStatefulWidget {
  final String serviceId;

  const TechnicalVisitScreen({super.key, required this.serviceId});

  @override
  ConsumerState<TechnicalVisitScreen> createState() =>
      _TechnicalVisitScreenState();
}

class _TechnicalVisitScreenState extends ConsumerState<TechnicalVisitScreen> {
  final _picker = ImagePicker();

  final _reportCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final _productNameCtrl = TextEditingController();
  final _productQtyCtrl = TextEditingController(text: '1');

  bool _syncedText = false;
  bool _syncScheduled = false;

  @override
  void dispose() {
    _reportCtrl.dispose();
    _notesCtrl.dispose();
    _productNameCtrl.dispose();
    _productQtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto({required ImageSource source}) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    await ref
        .read(technicalVisitControllerProvider(widget.serviceId).notifier)
        .uploadPhoto(file);
  }

  Future<void> _pickVideo({required ImageSource source}) async {
    final file = await _picker.pickVideo(source: source);
    if (file == null) return;
    await ref
        .read(technicalVisitControllerProvider(widget.serviceId).notifier)
        .uploadVideo(file);
  }

  Widget _sectionTitle(String title, {List<Widget> actions = const []}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        ...actions,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final user = ref.watch(authStateProvider).user;

    final state = ref.watch(technicalVisitControllerProvider(widget.serviceId));
    final ctrl = ref.read(
      technicalVisitControllerProvider(widget.serviceId).notifier,
    );

    if (!_syncedText && !state.loading && !_syncScheduled) {
      _syncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_syncedText) return;
        _reportCtrl.text = state.reportDescription;
        _notesCtrl.text = state.installationNotes;
        _syncedText = true;
        _syncScheduled = false;
      });
    }

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: AppBar(
        title: const Text('Levantamiento Técnico'),
        actions: [
          if (state.saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Guardar',
              onPressed: () => ctrl.save(),
              icon: const Icon(Icons.save_outlined),
            ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                _syncedText = false;
                await ctrl.load();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (state.error != null && state.error!.trim().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        state.error!,
                        style: TextStyle(color: cs.onErrorContainer),
                      ),
                    ),

                  if (state.pendingUploads.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('Subiendo archivos'),
                            const SizedBox(height: 8),
                            ...state.pendingUploads.map((u) {
                              final isFailed = u.status.name == 'failed';
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      u.fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: isFailed ? 1 : u.progress,
                                        minHeight: 8,
                                        backgroundColor:
                                            cs.surfaceContainerHighest,
                                        color: isFailed ? cs.error : cs.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Fotos
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(
                            'Fotos',
                            actions: [
                              IconButton(
                                tooltip: 'Tomar foto',
                                onPressed: () =>
                                    _pickPhoto(source: ImageSource.camera),
                                icon: const Icon(Icons.photo_camera_outlined),
                              ),
                              IconButton(
                                tooltip: 'Elegir de galería',
                                onPressed: () =>
                                    _pickPhoto(source: ImageSource.gallery),
                                icon: const Icon(Icons.photo_library_outlined),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (state.photos.isEmpty)
                            Text('Sin fotos', style: theme.textTheme.bodySmall)
                          else
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: List.generate(state.photos.length, (i) {
                                final url = state.photos[i];
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    children: [
                                      Image.network(
                                        url,
                                        width: 96,
                                        height: 96,
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) => Container(
                                          width: 96,
                                          height: 96,
                                          color: cs.surfaceContainerHighest,
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.broken_image_outlined,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: Material(
                                          color: cs.scrim.withValues(
                                            alpha: 0.55,
                                          ),
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: () => ctrl.removePhotoAt(i),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(
                                                Icons.close,
                                                color: cs.onSurface,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Videos
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(
                            'Videos',
                            actions: [
                              IconButton(
                                tooltip: 'Grabar video',
                                onPressed: () =>
                                    _pickVideo(source: ImageSource.camera),
                                icon: const Icon(Icons.videocam_outlined),
                              ),
                              IconButton(
                                tooltip: 'Elegir video',
                                onPressed: () =>
                                    _pickVideo(source: ImageSource.gallery),
                                icon: const Icon(Icons.video_library_outlined),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (state.videos.isEmpty)
                            Text('Sin videos', style: theme.textTheme.bodySmall)
                          else
                            ...List.generate(state.videos.length, (i) {
                              final url = state.videos[i];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.play_circle_outline),
                                title: Text('Video ${i + 1}'),
                                subtitle: Text(
                                  url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () async {
                                  final uri = Uri.tryParse(url);
                                  if (uri != null) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                                trailing: IconButton(
                                  tooltip: 'Eliminar',
                                  onPressed: () => ctrl.removeVideoAt(i),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Reporte técnico
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Reporte técnico'),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _reportCtrl,
                            minLines: 3,
                            maxLines: 8,
                            decoration: const InputDecoration(
                              hintText: 'Describe el levantamiento realizado…',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: ctrl.setReportDescription,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Observaciones
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Observaciones'),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _notesCtrl,
                            minLines: 3,
                            maxLines: 8,
                            decoration: const InputDecoration(
                              hintText: 'Notas y observaciones…',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: ctrl.setInstallationNotes,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Productos necesarios
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Productos necesarios'),
                          const SizedBox(height: 10),
                          if (state.estimatedProducts.isEmpty)
                            Text(
                              'Sin productos',
                              style: theme.textTheme.bodySmall,
                            )
                          else
                            ...List.generate(state.estimatedProducts.length, (
                              i,
                            ) {
                              final p = state.estimatedProducts[i];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(p.name),
                                subtitle: Text('Cantidad: ${p.quantity}'),
                                trailing: IconButton(
                                  tooltip: 'Eliminar',
                                  onPressed: () =>
                                      ctrl.removeEstimatedProductAt(i),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              );
                            }),
                          const Divider(height: 24),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _productNameCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Producto',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _productQtyCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Cant.',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton(
                                onPressed: () {
                                  final name = _productNameCtrl.text.trim();
                                  final qty =
                                      int.tryParse(
                                        _productQtyCtrl.text.trim(),
                                      ) ??
                                      1;
                                  if (name.isEmpty) return;
                                  ctrl.addEstimatedProduct(
                                    EstimatedProductItemModel(
                                      name: name,
                                      quantity: qty,
                                    ),
                                  );
                                  _productNameCtrl.clear();
                                  _productQtyCtrl.text = '1';
                                },
                                child: const Text('Agregar'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),
                ],
              ),
            ),
    );
  }
}
