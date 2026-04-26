import 'package:flutter/material.dart';

import '../../modules/whatsapp/whatsapp_instance_model.dart';

class ConfiguracionUsuarioDetalleScreen extends StatelessWidget {
  const ConfiguracionUsuarioDetalleScreen({super.key, required this.user});

  final WhatsappAdminUserEntry user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wa = user.whatsapp;
    final isConnected = wa?.isConnected ?? false;
    final hasInstance = wa != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          user.nombreCompleto,
          style: const TextStyle(fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // User info card
            _UserHeaderCard(user: user, theme: theme, scheme: scheme),
            const SizedBox(height: 24),
            // WhatsApp section label
            _SectionLabel(label: 'WhatsApp', theme: theme, scheme: scheme),
            const SizedBox(height: 10),
            _WhatsappStatusCard(
              wa: wa,
              isConnected: isConnected,
              hasInstance: hasInstance,
              theme: theme,
              scheme: scheme,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── USER HEADER ─────────────────────────────────────────────────────────────

class _UserHeaderCard extends StatelessWidget {
  const _UserHeaderCard({
    required this.user,
    required this.theme,
    required this.scheme,
  });

  final WhatsappAdminUserEntry user;
  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              user.nombreCompleto.isNotEmpty
                  ? user.nombreCompleto[0].toUpperCase()
                  : '?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.nombreCompleto,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              _friendlyRole(user.role),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _friendlyRole(String raw) {
    switch (raw.toUpperCase()) {
      case 'ADMIN':
        return 'Admin';
      case 'TECNICO':
        return 'Técnico';
      case 'ASISTENTE':
        return 'Asistente';
      case 'VENDEDOR':
        return 'Vendedor';
      case 'MARKETING':
        return 'Marketing';
      default:
        return raw;
    }
  }
}

// ─── SECTION LABEL ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.theme,
    required this.scheme,
  });

  final String label;
  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    );
  }
}

// ─── WHATSAPP STATUS CARD ─────────────────────────────────────────────────────

class _WhatsappStatusCard extends StatelessWidget {
  const _WhatsappStatusCard({
    required this.wa,
    required this.isConnected,
    required this.hasInstance,
    required this.theme,
    required this.scheme,
  });

  final WhatsappInstanceStatusResponse? wa;
  final bool isConnected;
  final bool hasInstance;
  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final statusColor = isConnected
        ? const Color(0xFF16A34A)
        : hasInstance
        ? const Color(0xFFF59E0B)
        : scheme.onSurfaceVariant.withValues(alpha: 0.6);

    final statusLabel = isConnected
        ? 'Conectado'
        : hasInstance
        ? 'Pendiente — esperando escaneo de QR'
        : 'Sin instancia configurada';

    final statusIcon = isConnected
        ? Icons.check_circle_rounded
        : hasInstance
        ? Icons.schedule_rounded
        : Icons.link_off_rounded;

    final bgColor = isConnected
        ? const Color(0xFF16A34A).withValues(alpha: 0.06)
        : !hasInstance
        ? scheme.surfaceContainerLow
        : scheme.surface;

    final borderColor = isConnected
        ? const Color(0xFF16A34A).withValues(alpha: 0.25)
        : scheme.outlineVariant.withValues(alpha: 0.45);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(statusIcon, color: statusColor, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                statusLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (hasInstance) ...[
            const SizedBox(height: 14),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 14),
            _InfoLine(
              label: 'Instancia',
              value: wa?.instanceName ?? '—',
              theme: theme,
              scheme: scheme,
            ),
            if ((wa?.phoneNumber ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              _InfoLine(
                label: 'Número',
                value: wa!.phoneNumber!,
                theme: theme,
                scheme: scheme,
              ),
            ],
            if (wa?.createdAt != null) ...[
              const SizedBox(height: 8),
              _InfoLine(
                label: 'Creado',
                value: _formatDate(wa!.createdAt!),
                theme: theme,
                scheme: scheme,
              ),
            ],
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'Este usuario aún no ha configurado su WhatsApp.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
    required this.theme,
    required this.scheme,
  });

  final String label;
  final String value;
  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
