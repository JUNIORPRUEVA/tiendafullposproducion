import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/routes.dart';
import '../operations_models.dart';
import '../presentation/operations_permissions.dart';
import 'technical_service_execution_controller.dart';
import 'widgets/technical_execution_cards.dart';
import 'widgets/service_execution_form.dart';

class TechnicalServiceExecutionScreen extends ConsumerStatefulWidget {
  final String serviceId;

  const TechnicalServiceExecutionScreen({super.key, required this.serviceId});

  @override
  ConsumerState<TechnicalServiceExecutionScreen> createState() =>
      _TechnicalServiceExecutionScreenState();
}

class _TechnicalServiceExecutionScreenState
    extends ConsumerState<TechnicalServiceExecutionScreen> {
  late final TextEditingController _notesCtrl;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  bool _isReadOnly({required ServiceModel service, required dynamic user}) {
    final perms = OperationsPermissions(user: user, service: service);
    if (!perms.canOperate) return true;
    if (perms.isAdminLike) return false;

    final status = parseStatus(service.status);
    return status == ServiceStatus.closed ||
        status == ServiceStatus.cancelled ||
        status == ServiceStatus.completed;
  }

  bool _isLikelyVideo(ServiceFileModel file) {
    final ft = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final url = file.fileUrl.trim().toLowerCase();
    if (ft.contains('video')) return true;
    return url.endsWith('.mp4');
  }

  bool _isLikelyImage(ServiceFileModel file) {
    final ft = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final url = file.fileUrl.trim().toLowerCase();
    if (ft.contains('image')) return true;
    return url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.webp');
  }

  Future<String?> _askEvidenceNote(
    BuildContext context, {
    required String title,
    required String hintText,
    required bool required,
  }) async {
    final theme = Theme.of(context);
    final ctrl = TextEditingController();
    String? error;

    final res = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    required ? 'Nota (requerida)' : 'Nota (opcional)',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLength: 140,
                    decoration: InputDecoration(
                      hintText: hintText,
                      errorText: error,
                    ),
                    onChanged: (_) {
                      if (error != null) {
                        setState(() => error = null);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final v = ctrl.text.trim();
                    if (required && v.isEmpty) {
                      setState(() => error = 'Requerido');
                      return;
                    }
                    Navigator.pop(dialogContext, v);
                  },
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        );
      },
    );

    ctrl.dispose();
    if (res == null) return null;
    final trimmed = res.trim();
    if (required) {
      return trimmed.isEmpty ? null : trimmed;
    }
    return trimmed.isEmpty ? '' : trimmed;
  }

  Future<void> _pickAndUploadImageEvidence(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    Future<void> uploadXFile(XFile xFile) async {
      if (!context.mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!context.mounted) return;

      final caption = await _askEvidenceNote(
        context,
        title: 'Agregar nota',
        hintText: 'Ej: Evidencia después de instalación',
        required: true,
      );
      if (caption == null || caption.trim().isEmpty) return;
      if (!context.mounted) return;
      await ctrl.uploadEvidenceXFile(file: xFile, caption: caption);
    }

    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (xFile != null) {
        await uploadXFile(xFile);
        return;
      }
    } catch (_) {
      // fallback below
    }

    // Fallback (desktop/web): file picker
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withReadStream: !kIsWeb,
      withData: kIsWeb,
      dialogTitle: 'Selecciona una imagen',
    );

    final file = result?.files.isNotEmpty == true ? result!.files.first : null;
    if (file == null) return;

    if (!context.mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;

    final caption = await _askEvidenceNote(
      context,
      title: 'Agregar nota',
      hintText: 'Ej: Evidencia después de instalación',
      required: true,
    );
    if (caption == null || caption.trim().isEmpty) return;
    if (!context.mounted) return;
    await ctrl.uploadEvidence(file: file, caption: caption);
  }

  Future<void> _captureAndUploadImageEvidence(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (xFile == null) return;
      if (!context.mounted) return;

      await Future<void>.delayed(Duration.zero);
      if (!context.mounted) return;

      final caption = await _askEvidenceNote(
        context,
        title: 'Agregar nota',
        hintText: 'Ej: Evidencia después de instalación',
        required: true,
      );
      if (caption == null || caption.trim().isEmpty) return;
      if (!context.mounted) return;

      await ctrl.uploadEvidenceXFile(file: xFile, caption: caption);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cámara no disponible: $e')));
    }
  }

  Future<void> _pickAndUploadVideoEvidence(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    Future<void> uploadXFile(XFile xFile) async {
      if (!context.mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!context.mounted) return;

      final note = await _askEvidenceNote(
        context,
        title: 'Agregar nota al video',
        hintText: 'Ej: Video de prueba (opcional)',
        required: false,
      );
      if (note == null) return;
      if (!context.mounted) return;

      await ctrl.uploadEvidenceXFile(
        file: xFile,
        caption: note.trim().isEmpty ? null : note,
      );
    }

    try {
      final xFile = await _picker.pickVideo(source: ImageSource.gallery);
      if (xFile != null) {
        await uploadXFile(xFile);
        return;
      }
    } catch (_) {
      // fallback below
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['mp4'],
      withReadStream: !kIsWeb,
      withData: kIsWeb,
      dialogTitle: 'Selecciona un video',
    );

    final file = result?.files.isNotEmpty == true ? result!.files.first : null;
    if (file == null) return;

    if (!context.mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;

    final note = await _askEvidenceNote(
      context,
      title: 'Agregar nota al video',
      hintText: 'Ej: Video de prueba (opcional)',
      required: false,
    );
    if (note == null) return;
    if (!context.mounted) return;

    await ctrl.uploadEvidence(
      file: file,
      caption: note.trim().isEmpty ? null : note,
    );
  }

  Future<void> _captureAndUploadVideoEvidence(
    BuildContext context,
    TechnicalExecutionController ctrl,
  ) async {
    try {
      final xFile = await _picker.pickVideo(source: ImageSource.camera);
      if (xFile == null) return;

      if (!context.mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!context.mounted) return;

      final note = await _askEvidenceNote(
        context,
        title: 'Agregar nota al video',
        hintText: 'Ej: Video de prueba (opcional)',
        required: false,
      );
      if (note == null) return;
      if (!context.mounted) return;

      await ctrl.uploadEvidenceXFile(
        file: xFile,
        caption: note.trim().isEmpty ? null : note,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cámara no disponible: $e')));
    }
  }

  Future<void> _previewEvidence(
    BuildContext context,
    ServiceFileModel file,
  ) async {
    final url = file.fileUrl.trim();
    if (url.isEmpty) return Future.value();

    final ft = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final isVideo = ft.contains('video') || url.toLowerCase().endsWith('.mp4');
    if (isVideo) {
      return showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return _VideoPreviewDialog(url: url);
        },
      );
    }

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                url,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(
      technicalExecutionControllerProvider(widget.serviceId),
    );
    final ctrl = ref.read(
      technicalExecutionControllerProvider(widget.serviceId).notifier,
    );

    final auth = ref.watch(authStateProvider);

    final service = st.service;
    if (_notesCtrl.text != st.notes) {
      _notesCtrl.text = st.notes;
      _notesCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _notesCtrl.text.length),
      );
    }

    final title = service == null
        ? 'Servicio'
        : (service.customerName.trim().isEmpty
              ? 'Servicio'
              : service.customerName.trim());

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(Routes.operacionesTecnico);
          },
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (st.saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
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
              onPressed: () => ctrl.saveNow(),
              icon: const Icon(Icons.save_outlined),
            ),
        ],
      ),
      body: st.loading
          ? const Center(child: CircularProgressIndicator())
          : service == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(st.error ?? 'No se pudo cargar el servicio'),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ctrl.load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                children: [
                  if (st.error != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(st.error!),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ExecutionTimelineCard(
                    arrivedAt: st.arrivedAt,
                    startedAt: st.startedAt,
                    finishedAt: st.finishedAt,
                    onArrived: () => ctrl.markArrivedNow(),
                    onStarted: () => ctrl.markStartedNow(),
                    onFinished: () => ctrl.markFinishedNow(),
                  ),
                  const SizedBox(height: 12),
                  ClientApprovalCard(
                    value: st.clientApproved,
                    onChanged: (v) => ctrl.toggleClientApproved(v),
                  ),
                  const SizedBox(height: 12),
                  TechnicalNotesCard(
                    controller: _notesCtrl,
                    onChanged: ctrl.updateNotes,
                    readOnly: _isReadOnly(service: service, user: auth.user),
                  ),
                  const SizedBox(height: 12),
                  TechnicalSectionCard(
                    icon: Icons.tune_outlined,
                    title: 'Detalles por tipo de servicio',
                    child: ServiceExecutionForm(
                      service: service,
                      phaseSpecificData: st.phaseSpecificData,
                      readOnly: _isReadOnly(service: service, user: auth.user),
                      onChanged: (k, v) => ctrl.updatePhaseSpecificField(k, v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ServiceChecklistCard(
                    steps: service.steps,
                    onToggle: ctrl.toggleStep,
                  ),
                  const SizedBox(height: 12),
                  EvidenceGalleryCard(
                    title: 'Fotos del servicio',
                    emptyLabel: 'Sin evidencias aún',
                    icon: Icons.photo_camera_outlined,
                    files: service.files.where(_isLikelyImage).toList(),
                    pending: st.pendingEvidence
                        .where((p) => p.isImage)
                        .toList(),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Cámara',
                          onPressed: () =>
                              _captureAndUploadImageEvidence(context, ctrl),
                          icon: const Icon(Icons.photo_camera_outlined),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: 'Galería',
                          onPressed: () =>
                              _pickAndUploadImageEvidence(context, ctrl),
                          icon: const Icon(Icons.photo_library_outlined),
                        ),
                      ],
                    ),
                    onPreview: (f) => _previewEvidence(context, f),
                  ),
                  const SizedBox(height: 12),
                  EvidenceGalleryCard(
                    title: 'Videos del servicio',
                    emptyLabel: 'Sin videos aún',
                    icon: Icons.videocam_outlined,
                    files: service.files.where(_isLikelyVideo).toList(),
                    pending: st.pendingEvidence
                        .where((p) => p.isVideo)
                        .toList(),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Cámara',
                          onPressed: () =>
                              _captureAndUploadVideoEvidence(context, ctrl),
                          icon: const Icon(Icons.videocam_outlined),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: 'Galería',
                          onPressed: () =>
                              _pickAndUploadVideoEvidence(context, ctrl),
                          icon: const Icon(Icons.video_library_outlined),
                        ),
                      ],
                    ),
                    onPreview: (f) => _previewEvidence(context, f),
                  ),
                ],
              ),
            ),
    );
  }
}

class _VideoPreviewDialog extends StatefulWidget {
  final String url;

  const _VideoPreviewDialog({required this.url});

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  late final VideoPlayerController _controller;
  ChewieController? _chewie;
  late final Future<void> _init;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _init = _controller.initialize().then((_) {
      if (!mounted) return;

      final cs = Theme.of(context).colorScheme;
      _chewie = ChewieController(
        videoPlayerController: _controller,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: cs.primary,
          handleColor: cs.primary,
          bufferedColor: cs.primary.withValues(alpha: 0.25),
          backgroundColor: cs.onSurface.withValues(alpha: 0.20),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No se pudo reproducir el video\n$errorMessage',
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );
    });
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: cs.surface,
                child: FutureBuilder<void>(
                  future: _init,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snap.hasError ||
                        !_controller.value.isInitialized ||
                        _chewie == null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No se pudo reproducir el video',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      );
                    }

                    final aspect = _controller.value.aspectRatio;
                    return Center(
                      child: AspectRatio(
                        aspectRatio: aspect > 0 ? aspect : 16 / 9,
                        child: Chewie(controller: _chewie!),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
