import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../../core/api/env.dart';
import '../../../core/utils/video_preview_controller.dart';
import '../service_order_models.dart';

class EvidenceItemWidget extends StatelessWidget {
  const EvidenceItemWidget({
    super.key,
    required this.type,
    this.url,
    this.text,
    this.createdAt,
    this.previewBytes,
    this.localPath,
    this.fileName,
    this.onRemove,
    this.compact = false,
  });

  final ServiceEvidenceType type;
  final String? url;
  final String? text;
  final DateTime? createdAt;
  final Uint8List? previewBytes;
  final String? localPath;
  final String? fileName;
  final VoidCallback? onRemove;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = _resolveMediaUrl(url ?? text ?? '');
    final effectiveVideoSource = (localPath ?? '').trim().isNotEmpty
        ? localPath!.trim()
        : resolvedUrl;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                type.isText
                    ? Icons.notes_outlined
                    : type.isImage
                        ? Icons.image_outlined
                        : Icons.videocam_outlined,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(type.label)),
              if (createdAt != null)
                Text(
                  DateFormat('dd/MM h:mm a', 'es_DO').format(createdAt!.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (type.isText)
            Text((text ?? '').trim().isEmpty ? 'Sin contenido' : text!.trim())
          else if (type.isImage)
            _EvidenceImage(
              url: resolvedUrl,
              previewBytes: previewBytes,
              compact: compact,
            )
          else
            _EvidenceVideo(
              source: effectiveVideoSource,
              previewBytes: previewBytes,
              fileName: fileName,
              compact: compact,
            ),
        ],
      ),
    );
  }
}

class _EvidenceImage extends StatelessWidget {
  const _EvidenceImage({
    required this.url,
    this.previewBytes,
    required this.compact,
  });

  final String url;
  final Uint8List? previewBytes;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (previewBytes == null && url.isEmpty) {
      return const _MediaErrorBox(message: 'No hay imagen disponible');
    }

    final height = compact ? 160.0 : 220.0;

    return GestureDetector(
      onTap: () => _showImageFullscreen(context, url, previewBytes),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: previewBytes != null
            ? Image.memory(
                previewBytes!,
                height: height,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            : Image.network(
                url,
                height: height,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  final total = loadingProgress.expectedTotalBytes;
                  final value = total == null
                      ? null
                      : loadingProgress.cumulativeBytesLoaded / total;
                  return SizedBox(
                    height: height,
                    child: Center(
                      child: CircularProgressIndicator(value: value),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return SizedBox(
                    height: compact ? 140 : 180,
                    child: const _MediaErrorBox(message: 'No se pudo cargar la imagen'),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _showImageFullscreen(
    BuildContext context,
    String imageUrl,
    Uint8List? bytes,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: bytes != null
                      ? Image.memory(bytes, fit: BoxFit.contain)
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(child: CircularProgressIndicator());
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const _MediaErrorBox(
                              message: 'No se pudo abrir la imagen',
                              dark: true,
                            );
                          },
                        ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton.filled(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EvidenceVideo extends StatefulWidget {
  const _EvidenceVideo({
    required this.source,
    this.previewBytes,
    this.fileName,
    this.expanded = false,
    this.compact = false,
  });

  final String source;
  final Uint8List? previewBytes;
  final String? fileName;
  final bool expanded;
  final bool compact;

  @override
  State<_EvidenceVideo> createState() => _EvidenceVideoState();
}

class _EvidenceVideoState extends State<_EvidenceVideo> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;
  String? _durationLabel;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final rawSource = widget.source.trim();
    if (rawSource.isEmpty) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }

    final controller = createVideoPreviewController(
      path: rawSource,
      bytes: widget.previewBytes,
      fileName: widget.fileName,
    );
    if (controller == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    try {
      await controller.initialize();
      controller.setLooping(false);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _durationLabel = _formatDuration(controller.value.duration);
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _openExpanded(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _EvidenceVideo(
                    source: widget.source,
                    previewBytes: widget.previewBytes,
                    fileName: widget.fileName,
                    expanded: true,
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton.filled(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _VideoSurface(
        expanded: widget.expanded,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_failed || _controller == null) {
      return _VideoSurface(
        expanded: widget.expanded,
        child: const _MediaErrorBox(message: 'No se pudo cargar el video'),
      );
    }

    final controller = _controller!;
    final aspectRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;

    return GestureDetector(
      onTap: _togglePlayback,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(controller),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.14),
                        Colors.black.withValues(alpha: 0.34),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: IconButton.filledTonal(
                  onPressed: _togglePlayback,
                  icon: Icon(
                    controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 32,
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: IconButton.filledTonal(
                  onPressed: () => _openExpanded(context),
                  icon: const Icon(Icons.open_in_full),
                ),
              ),
              if ((_durationLabel ?? '').isNotEmpty)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Text(
                        _durationLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({required this.child, required this.expanded});

  final Widget child;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: expanded ? null : (compact ? 160 : 220),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF101828),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _MediaErrorBox extends StatelessWidget {
  const _MediaErrorBox({required this.message, this.dark = false});

  final String message;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: color),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

String _resolveMediaUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';

  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) {
    return uri.toString();
  }

  final normalized = value.replaceAll('\\', '/');
  final baseUrl = Env.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  if (normalized.startsWith('/uploads/')) {
    return '$baseUrl$normalized';
  }
  if (normalized.startsWith('uploads/')) {
    return '$baseUrl/$normalized';
  }
  if (normalized.startsWith('./uploads/')) {
    return '$baseUrl/${normalized.substring(2)}';
  }

  return normalized.startsWith('/') ? '$baseUrl$normalized' : '$baseUrl/$normalized';
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  if (totalSeconds <= 0) return '';
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}