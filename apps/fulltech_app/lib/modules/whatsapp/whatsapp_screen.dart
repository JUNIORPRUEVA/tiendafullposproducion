import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'application/whatsapp_controller.dart';
import 'whatsapp_instance_model.dart';

class WhatsappScreen extends ConsumerStatefulWidget {
  const WhatsappScreen({super.key});

  @override
  ConsumerState<WhatsappScreen> createState() => _WhatsappScreenState();
}

class _WhatsappScreenState extends ConsumerState<WhatsappScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(whatsappControllerProvider.notifier).loadInstance();
      final user = ref.read(authStateProvider).user;
      if (user?.appRole == AppRole.admin) {
        ref.read(whatsappControllerProvider.notifier).loadAdminUsers();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final state = ref.watch(whatsappControllerProvider);
    final isAdmin = user?.appRole == AppRole.admin;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'WhatsApp',
        showLogo: false,
        showDepartmentLabel: false,
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(whatsappControllerProvider.notifier).loadInstance();
            if (isAdmin) {
              await ref
                  .read(whatsappControllerProvider.notifier)
                  .loadAdminUsers();
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // My WhatsApp section
              _MySectionHeader(theme: theme),
              const SizedBox(height: 12),
              if (state.isLoading)
                const _LoadingCard()
              else if (state.error != null && state.instance == null)
                _ErrorCard(
                  message: state.error!,
                  onRetry: () => ref
                      .read(whatsappControllerProvider.notifier)
                      .loadInstance(),
                )
              else
                _MyWhatsappCard(
                  state: state,
                  onConnect: () => _openConnectSheet(context),
                  onDisconnect: () => _confirmDisconnect(context),
                ),

              // Admin users section
              if (isAdmin) ...[
                const SizedBox(height: 28),
                _AdminSectionHeader(theme: theme, count: state.adminUsers.length),
                const SizedBox(height: 12),
                if (state.adminUsersLoading)
                  const _LoadingCard()
                else if (state.adminUsers.isEmpty)
                  _EmptyAdminCard(theme: theme)
                else
                  _AdminUsersCard(users: state.adminUsers),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openConnectSheet(BuildContext context) async {
    final controller = ref.read(whatsappControllerProvider.notifier);
    final state = ref.read(whatsappControllerProvider);

    // If no instance exists, create one first
    if (state.instance == null || !state.instance!.exists) {
      await controller.createInstance();
      if (!mounted) return;
    }

    if (!mounted) return;
    final newState = ref.read(whatsappControllerProvider);
    if (newState.error != null && newState.instance == null) return;

    // ignore: use_build_context_synchronously
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _WhatsappConnectSheet(),
    );

    // After modal closes, reload status
    if (mounted) {
      await controller.loadInstance();
    }
  }

  Future<void> _confirmDisconnect(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar WhatsApp'),
        content:
            const Text('¿Deseas eliminar la instancia de WhatsApp? Deberás reconectar escaneando el QR nuevamente.'),
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
}

// ─── WIDGETS ────────────────────────────────────────────────────────────────

class _MySectionHeader extends StatelessWidget {
  const _MySectionHeader({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF25D366).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.chat_rounded,
            color: Color(0xFF25D366),
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Mi conexión WhatsApp',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _AdminSectionHeader extends StatelessWidget {
  const _AdminSectionHeader({required this.theme, required this.count});

  final ThemeData theme;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.60),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.groups_outlined,
            color: theme.colorScheme.primary,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Estado WhatsApp del equipo',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: theme.colorScheme.onErrorContainer,
          ),
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

class _MyWhatsappCard extends StatelessWidget {
  const _MyWhatsappCard({
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
            : scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF16A34A).withValues(alpha: 0.30)
              : scheme.outlineVariant.withValues(alpha: 0.60),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
                  borderRadius: BorderRadius.circular(14),
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
          Row(
            children: [
              if (!isConnected)
                Expanded(
                  child: FilledButton.icon(
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
                  ),
                )
              else
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onConnect,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Ver QR'),
                  ),
                ),
              if (exists) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onDisconnect,
                  icon: Icon(
                    Icons.link_off_rounded,
                    color: scheme.error,
                  ),
                  label: Text(
                    'Desconectar',
                    style: TextStyle(color: scheme.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

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
        Text(
          '$label: ',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyAdminCard extends StatelessWidget {
  const _EmptyAdminCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.40),
        ),
      ),
      child: Center(
        child: Text(
          'No hay usuarios para mostrar.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _AdminUsersCard extends StatelessWidget {
  const _AdminUsersCard({required this.users});

  final List<WhatsappAdminUserEntry> users;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: users.asMap().entries.map((entry) {
          final i = entry.key;
          final user = entry.value;
          final isLast = i == users.length - 1;
          return _AdminUserRow(user: user, isLast: isLast);
        }).toList(growable: false),
      ),
    );
  }
}

class _AdminUserRow extends StatelessWidget {
  const _AdminUserRow({required this.user, required this.isLast});

  final WhatsappAdminUserEntry user;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wa = user.whatsapp;
    final isConnected = wa?.isConnected ?? false;
    final hasInstance = wa != null;

    final statusColor = isConnected
        ? const Color(0xFF16A34A)
        : hasInstance
            ? const Color(0xFFF59E0B)
            : scheme.onSurfaceVariant.withValues(alpha: 0.5);

    final statusIcon = isConnected
        ? Icons.check_circle_rounded
        : hasInstance
            ? Icons.schedule_rounded
            : Icons.radio_button_unchecked_rounded;

    final statusLabel = isConnected
        ? 'Conectado'
        : hasInstance
            ? 'Pendiente'
            : 'Sin instancia';

    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.30),
                ),
              ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.50),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              user.nombreCompleto.isNotEmpty
                  ? user.nombreCompleto[0].toUpperCase()
                  : '?',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.nombreCompleto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, color: statusColor, size: 14),
              const SizedBox(width: 4),
              Text(
                statusLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── QR CONNECT SHEET ───────────────────────────────────────────────────────

class _WhatsappConnectSheet extends ConsumerStatefulWidget {
  const _WhatsappConnectSheet();

  @override
  ConsumerState<_WhatsappConnectSheet> createState() =>
      _WhatsappConnectSheetState();
}

class _WhatsappConnectSheetState extends ConsumerState<_WhatsappConnectSheet> {
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
    // Stop polling when sheet is closed
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
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.80,
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isConnected ? '¡WhatsApp conectado!' : 'Conectar WhatsApp',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isConnected
                ? 'Tu WhatsApp fue conectado exitosamente.'
                : 'Escanea el QR con WhatsApp en tu teléfono.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
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
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF25D366),
                size: 46,
              ),
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
          if (!isConnected) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(whatsappControllerProvider.notifier).refreshQr(),
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
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                ),
                child: const Text('Continuar'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QrImageView extends StatelessWidget {
  const _QrImageView({required this.base64});

  final String base64;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    try {
      final bytes = base64Decode(
        base64.contains(',') ? base64.split(',').last : base64,
      );
      return Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
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
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            'Cargando QR...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
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
          Icon(
            Icons.error_outline_rounded,
            color: theme.colorScheme.onErrorContainer,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            error,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onRetry,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
