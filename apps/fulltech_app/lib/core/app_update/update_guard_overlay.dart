import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/safe_url_launcher.dart';
import 'app_update_controller.dart';
import 'app_update_models.dart';

class UpdateGuardOverlay extends ConsumerWidget {
  const UpdateGuardOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateProvider);
    if (!state.blocksUsage) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final installed = state.installedRelease;
    final updateInfo = state.updateInfo;
    final downloadUrl = updateInfo?.downloadUrl;
    final canOpenDownload =
        downloadUrl != null && downloadUrl.trim().isNotEmpty;
    final platformName = installed?.platform.displayName ?? 'esta plataforma';
    final installedLabel = installed == null
        ? null
        : '${installed.currentVersion}+${installed.currentBuild}';
    final latestLabel = updateInfo == null
        ? null
        : '${updateInfo.latestVersion ?? 'Nueva versión'}${updateInfo.latestBuild == null ? '' : '+${updateInfo.latestBuild}'}';

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.62),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                color: scheme.surface,
                elevation: 18,
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              Icons.system_update_alt_rounded,
                              color: scheme.onErrorContainer,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Actualización obligatoria',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Debes actualizar FullTech en $platformName para continuar usando la app.',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _InfoRow(
                        label: 'Versión instalada',
                        value: installedLabel ?? 'Desconocida',
                      ),
                      _InfoRow(
                        label: 'Versión requerida',
                        value: latestLabel ?? 'Disponible',
                      ),
                      if ((updateInfo?.releaseNotes ?? '')
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Notas de la versión',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.65,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            updateInfo!.releaseNotes!,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        canOpenDownload
                            ? 'Cuando termine la instalación, vuelve a abrir FullTech y la app validará la nueva versión automáticamente.'
                            : 'No se recibió un enlace de descarga válido. Reintenta la validación o corrige el release en el panel admin.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ref
                                    .read(appUpdateProvider.notifier)
                                    .checkNow(force: true);
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Reintentar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: canOpenDownload
                                  ? () {
                                      safeOpenUrl(
                                        context,
                                        Uri.parse(downloadUrl),
                                        copiedMessage:
                                            'Enlace de actualización copiado',
                                      );
                                    }
                                  : null,
                              icon: const Icon(Icons.download_rounded),
                              label: Text(
                                installed?.platform == ReleasePlatform.android
                                    ? 'Descargar APK'
                                    : 'Descargar instalador',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
