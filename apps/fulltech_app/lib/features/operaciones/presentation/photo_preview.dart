import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/local_file_image.dart';
import 'full_screen_image_viewer.dart';

class PhotoPreview extends StatelessWidget {
  final String source;
  final double height;

  const PhotoPreview({super.key, required this.source, this.height = 120});

  bool get _isRemote {
    final s = source.trim().toLowerCase();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final borderRadius = BorderRadius.circular(14);

    Widget fallback() {
      return Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_outlined,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
              const SizedBox(height: 6),
              Text(
                'Ver foto',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isRemote) {
      final url = source.trim();
      return ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              FullScreenImageViewer.show(
                context,
                image: CachedNetworkImageProvider(url),
                title: 'Foto',
              );
            },
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 120),
                placeholder: (context, _) => Container(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, _, __) => fallback(),
              ),
            ),
          ),
        ),
      );
    }

    if (kIsWeb) {
      return SizedBox(height: height, child: fallback());
    }

    final provider = localFileImageProvider(source);
    if (provider == null) {
      return SizedBox(height: height, child: fallback());
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            FullScreenImageViewer.show(context, image: provider, title: 'Foto');
          },
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Image(
              image: provider,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => fallback(),
            ),
          ),
        ),
      ),
    );
  }
}
