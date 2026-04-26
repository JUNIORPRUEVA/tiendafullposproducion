import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/whatsapp_controller.dart';

/// Panel de gestión completa de la instancia WhatsApp del usuario en sesión.
/// Se puede embeber en cualquier pantalla (Configuración, WhatsApp, etc.).
class WhatsappPanel extends ConsumerStatefulWidget {
  const WhatsappPanel({super.key});

  @override
  ConsumerState<WhatsappPanel> createState() => _WhatsappPanelState();
}

class _WhatsappPanelState extends ConsumerState<WhatsappPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(whatsappControllerProvider.notifier).loadInstance();
    });
  }

  Future<void> _openConnectSheet() async {
    final controller = ref.read(whatsappControllerProvider.notifier);
    final s = ref.read(whatsappControllerProvider);

    // Si no hay instancia, crear primero
    if (s.instance == null || !s.instance!.exists) {
      await controller.createInstance();
      if (!mounted) return;
    }

    final newState = ref.read(whatsappControllerProvider);
    if (newState.error != null && newState.instance == null) return;

    if (!mounted) return;
    // ignore: use_build_context_synchronously
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const WhatsappQrSheet(),
    );

    if (mounted) {
      await controller.loadInstance();
    }
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar WhatsApp'),
        content: const Text(
          '¿Deseas eliminar la instancia de WhatsApp? Deberás reconectar escaneando el QR nuevamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(whatsappControllerProvider.notifier).deleteInstance();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whatsappControllerProvider);

    if (state.isLoading) {
      return const _WaLoadingCard();
    }

    if (state.error != null && state.instance == null) {
      return _WaErrorCard(
        message: state.error!,
        onRetry: () =>
            ref.read(whatsappControllerProvider.notifier).loadInstance(),
      );
    }

    return _WaStatusCard(
      state: state,
      onConnect: _openConnectSheet,
      onDisconnect: _confirmDisconnect,
    );
  }
}

// ─── Status card ─────────────────────────────────────────────────────────────

class _WaStatusCard extends StatelessWidget {
  const _WaStatusCard({
    required this.state,
    required this.onConnect,
    required this.onDisconnect,
  });

  final WhatsappState state;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final instance = state.instance;
    final isConnected = instance?.isConnected ?? false;
    final exists = instance?.exists ?? false;

    final statusColor = isConnected
        ? const Color(0xFF16A34A)
        : exists
            ? const Color(0xFFF59E0B)
            : scheme.onSurfaceVariant;

    final statusLabel = isConnected
        ? 'Conectado'
        : exists
            ? 'Pendiente (escanear QR)'
            : 'Sin instancia';

    final statusIcon = isConnected
        ? Icons.check_circle_rounded
        : exists
            ? Icons.qr_code_scanner_rounded
            : Icons.link_off_rounded;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConnected
            ? const Color(0xFF16A34A).withValues(alpha: 0.06)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF16A34A).withValues(alpha: 0.30)
              : scheme.outlineVariant.withValues(alpha: 0.60),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(statusIcon, color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WhatsApp',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isConnected && (instance?.phoneNumber ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.phone_outlined,
              label: 'Número',
              value: instance!.phoneNumber!,
            ),
          ],
          if (exists && (instance?.instanceName ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            _InfoRow(
              icon: Icons.memory_rounded,
              label: 'Instancia',
              value: instance!.instanceName!,
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isConnected)
                FilledButton.icon(
                  onPressed: state.isCreating ? null : onConnect,
                  icon: state.isCreating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.qr_code_rounded),
                  label: Text(exists ? 'Escanear QR' : 'Conectar WhatsApp'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: onConnect,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Ver QR'),
                ),
              if (exists)
                OutlinedButton.icon(
                  onPressed: onDisconnect,
                  icon: Icon(Icons.link_off_rounded, color: scheme.error),
                  label: Text('Desconectar',
                      style: TextStyle(color: scheme.error)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: scheme.error.withValues(alpha: 0.4)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Loading card ─────────────────────────────────────────────────────────────

class _WaLoadingCard extends StatelessWidget {
  const _WaLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

// ─── Error card ───────────────────────────────────────────────────────────────

class _WaErrorCard extends StatelessWidget {
  const _WaErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

// ─── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text('$label: ',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ─── QR Bottom Sheet ─────────────────────────────────────────────────────────

/// Sheet modal para escanear el QR.
/// Puede abrirse desde cualquier lugar usando showModalBottomSheet.
class WhatsappQrSheet extends ConsumerStatefulWidget {
  const WhatsappQrSheet({super.key});

  @override
  ConsumerState<WhatsappQrSheet> createState() => _WhatsappQrSheetState();
}

class _WhatsappQrSheetState extends ConsumerState<WhatsappQrSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(whatsappControllerProvider.notifier);
      controller.refreshQr();
      controller.startPolling();
    });
  }

  @override
  void dispose() {
    ref.read(whatsappControllerProvider.notifier).stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whatsappControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isConnected = state.instance?.isConnected ?? false;
    final qr = state.qr;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isConnected ? '¡WhatsApp conectado!' : 'Conectar WhatsApp',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            isConnected
                ? 'Tu WhatsApp fue conectado exitosamente.'
                : 'Escanea el QR con WhatsApp en tu teléfono.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          if (isConnected)
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF25D366), size: 46),
            )
          else if (state.qrError != null)
            _QrErrorView(
              error: state.qrError!,
              onRetry: () =>
                  ref.read(whatsappControllerProvider.notifier).refreshQr(),
            )
          else if (qr != null && qr.qrBase64.isNotEmpty)
            _QrImageView(base64: qr.qrBase64)
          else
            const _QrLoadingView(),
          const SizedBox(height: 20),
          if (!isConnected)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ref
                        .read(whatsappControllerProvider.notifier)
                        .refreshQr(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Actualizar QR'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366)),
                child: const Text('Continuar'),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── QR Image ────────────────────────────────────────────────────────────────

class _QrImageView extends StatelessWidget {
  const _QrImageView({required this.base64});

  final String base64;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    try {
      final bytes = base64Decode(
          base64.contains(',') ? base64.split(',').last : base64);
      return Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Image.memory(bytes, fit: BoxFit.contain),
      );
    } catch (_) {
      return const _QrLoadingView();
    }
  }
}

class _QrLoadingView extends StatelessWidget {
  const _QrLoadingView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text('Cargando QR...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _QrErrorView extends StatelessWidget {
  const _QrErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded,
              color: theme.colorScheme.onErrorContainer, size: 32),
          const SizedBox(height: 8),
          Text(
            error,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
