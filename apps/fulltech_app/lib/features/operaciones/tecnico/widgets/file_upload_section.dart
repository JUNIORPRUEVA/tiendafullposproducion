import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'service_order_detail_components.dart';
import '../technical_evidence_upload.dart';

class FileUploadSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String emptyTitle;
  final String emptyMessage;
  final List<String> items;
  final List<PendingEvidenceUpload> pendingUploads;
  final bool isVideo;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickGallery;
  final ValueChanged<int>? onRemove;
  final bool enabled;

  const FileUploadSection({
    super.key,
    required this.title,
    required this.icon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.items,
    required this.pendingUploads,
    required this.isVideo,
    required this.onPickCamera,
    required this.onPickGallery,
    required this.onRemove,
    this.enabled = true,
  });

  List<PendingEvidenceUpload> get _filteredPending => pendingUploads
      .where((item) => isVideo ? item.isVideo : item.isImage)
      .toList(growable: false);

  Future<void> _openExternal(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: isVideo ? 'Capturar' : 'Tomar foto',
              onPressed: enabled ? onPickCamera : null,
              icon: Icon(
                isVideo ? Icons.videocam_outlined : Icons.photo_camera_outlined,
              ),
            ),
            IconButton(
              tooltip: isVideo ? 'Subir video' : 'Elegir archivo',
              onPressed: enabled ? onPickGallery : null,
              icon: Icon(
                isVideo
                    ? Icons.video_library_outlined
                    : Icons.photo_library_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          isVideo
              ? 'Adjunta evidencia audiovisual del servicio.'
              : 'Toma o selecciona imágenes de apoyo para documentar el trabajo.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF607287),
          ),
        ),
        if (_filteredPending.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final upload in _filteredPending) ...[
            Text(
              upload.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: upload.status == PendingEvidenceStatus.failed
                    ? 1
                    : upload.progress,
                minHeight: 8,
                backgroundColor: const Color(0xFFE2E8F0),
                color: upload.status == PendingEvidenceStatus.failed
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF0B6BDE),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
        const SizedBox(height: 12),
        if (items.isEmpty)
          EmptyStateWidget(icon: icon, title: emptyTitle, message: emptyMessage)
        else if (!isVideo)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < items.length; index++)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      Image.network(
                        items[index],
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 110,
                          height: 110,
                          color: const Color(0xFFF1F5F9),
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: enabled ? () => onRemove?.call(index) : null,
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          )
        else
          Column(
            children: [
              for (var index = 0; index < items.length; index++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F3FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.play_circle_outline,
                      color: Color(0xFF0B6BDE),
                    ),
                  ),
                  title: Text(
                    'Video ${index + 1}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    items[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _openExternal(items[index]),
                  trailing: IconButton(
                    tooltip: 'Eliminar',
                    onPressed: enabled ? () => onRemove?.call(index) : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
