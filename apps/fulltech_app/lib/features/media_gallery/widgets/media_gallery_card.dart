import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../../core/cache/fulltech_cache_manager.dart';
import '../../../core/utils/video_preview_controller.dart';
import '../media_gallery_models.dart';

Future<void> showMediaGalleryViewer(
  BuildContext context,
  MediaGalleryItem item,
  Future<void> Function()? onDownload,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog.fullscreen(
        backgroundColor: const Color(0xFF020617),
        child: Stack(
          children: [
            Positioned.fill(
              child: item.isImage
                  ? _FullScreenImageViewer(item: item)
                  : _FullScreenVideoViewer(item: item),
            ),
            Positioned(
              top: 18,
              right: 18,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onDownload != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: IconButton.filled(
                        tooltip: 'Descargar',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.55),
                        ),
                        onPressed: onDownload,
                        icon: const Icon(Icons.download_outlined),
                      ),
                    ),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.55),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class MediaGalleryCard extends StatelessWidget {
  const MediaGalleryCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onDownload,
  });

  final MediaGalleryItem item;
  final VoidCallback onTap;
  final Future<void> Function()? onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = item.isInstallationCompleted
        ? const Color(0xFF0F766E)
        : const Color(0xFFB45309);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: theme.colorScheme.surface,
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      item.isImage
                          ? _ImageThumbnail(url: item.url)
                          : _VideoThumbnail(url: item.url),
                      Positioned(
                        left: 14,
                        top: 14,
                        child: _Pill(
                          label: item.isVideo ? 'Video' : 'Imagen',
                          backgroundColor: Colors.black.withValues(alpha: 0.58),
                          foregroundColor: Colors.white,
                          icon: item.isVideo
                              ? Icons.play_circle_outline
                              : Icons.image_outlined,
                        ),
                      ),
                      if (onDownload != null)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: IconButton.filledTonal(
                            tooltip: 'Descargar archivo',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(alpha: 0.38),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: onDownload,
                            icon: const Icon(Icons.download_outlined, size: 18),
                          ),
                        ),
                      if (item.isVideo)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.48),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    size: 34,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayComment,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Pill(
                          label: item.installationLabel,
                          backgroundColor: statusColor.withValues(alpha: 0.12),
                          foregroundColor: statusColor,
                          icon: item.isInstallationCompleted
                              ? Icons.verified_outlined
                              : Icons.schedule_outlined,
                        ),
                        _Pill(
                          label: item.uploadedByLabel,
                          backgroundColor:
                              theme.colorScheme.primaryContainer.withValues(
                                alpha: 0.48,
                              ),
                          foregroundColor: theme.colorScheme.onPrimaryContainer,
                          icon: item.uploadedByRole ==
                                  MediaGalleryUploadedByRole.creator
                              ? Icons.person_outline
                              : Icons.build_circle_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${item.orderStatusLabel} · ${DateFormat('dd MMM yyyy, h:mm a', 'es_DO').format(item.createdAt.toLocal())}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: FulltechImageCacheManager.instance,
      fit: BoxFit.cover,
      placeholder: (context, _) => const _ThumbnailPlaceholder(
        icon: Icons.image_outlined,
      ),
      errorWidget: (context, _, __) => const _ThumbnailPlaceholder(
        icon: Icons.broken_image_outlined,
      ),
    );
  }
}

class _VideoThumbnail extends StatefulWidget {
  const _VideoThumbnail({required this.url});

  final String url;

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _failed = false;

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
    final controller = createVideoPreviewController(path: widget.url);
    if (controller == null) {
      if (mounted) {
        setState(() => _failed = true);
      }
      return;
    }

    try {
      await controller.initialize();
      await controller.pause();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return _failed
          ? const _ThumbnailPlaceholder(icon: Icons.videocam_off_outlined)
          : const _ThumbnailPlaceholder(icon: Icons.videocam_outlined);
    }

    final aspectRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;

    return ColoredBox(
      color: const Color(0xFF020617),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 220 * aspectRatio,
          height: 220,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
      ),
      child: Center(
        child: Icon(icon, size: 34, color: Colors.white70),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foregroundColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  const _FullScreenImageViewer({required this.item});

  final MediaGalleryItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: item.url,
                cacheManager: FulltechImageCacheManager.instance,
                fit: BoxFit.contain,
                placeholder: (context, _) => const CircularProgressIndicator(),
                errorWidget: (context, _, __) => const _ViewerErrorState(),
              ),
            ),
          ),
        ),
        _ViewerFooter(item: item),
      ],
    );
  }
}

class _FullScreenVideoViewer extends StatefulWidget {
  const _FullScreenVideoViewer({required this.item});

  final MediaGalleryItem item;

  @override
  State<_FullScreenVideoViewer> createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<_FullScreenVideoViewer> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;

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
    final controller = createVideoPreviewController(path: widget.item.url);
    if (controller == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed || _controller == null) {
      return const _ViewerErrorState();
    }

    final controller = _controller!;
    final aspectRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;

    return Column(
      children: [
        Expanded(
          child: Center(
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
                            Colors.black.withValues(alpha: 0.28),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: IconButton.filledTonal(
                      onPressed: _togglePlay,
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _ViewerFooter(item: widget.item),
      ],
    );
  }
}

class _ViewerFooter extends StatelessWidget {
  const _ViewerFooter({required this.item});

  final MediaGalleryItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.displayComment,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ViewerMeta(label: item.installationLabel),
              _ViewerMeta(label: item.uploadedByLabel),
              _ViewerMeta(label: item.orderStatusLabel),
              _ViewerMeta(
                label: DateFormat(
                  'dd MMM yyyy, h:mm a',
                  'es_DO',
                ).format(item.createdAt.toLocal()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewerMeta extends StatelessWidget {
  const _ViewerMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ViewerErrorState extends StatelessWidget {
  const _ViewerErrorState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.white70, size: 36),
          SizedBox(height: 12),
          Text(
            'No se pudo abrir este archivo',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}