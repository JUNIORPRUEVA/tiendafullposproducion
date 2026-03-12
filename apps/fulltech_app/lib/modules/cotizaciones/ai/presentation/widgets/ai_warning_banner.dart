import 'package:flutter/material.dart';

import '../../domain/models/ai_warning.dart';

class AiWarningBanner extends StatelessWidget {
  const AiWarningBanner({
    super.key,
    required this.warnings,
    required this.analyzing,
    required this.onOpenRule,
    required this.onAskAi,
  });

  final List<AiWarning> warnings;
  final bool analyzing;
  final Future<void> Function(AiWarning warning) onOpenRule;
  final ValueChanged<AiWarning> onAskAi;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty && !analyzing) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final primaryWarning = warnings.isNotEmpty ? warnings.first : null;
    final warningCount = warnings
        .where((item) => item.type == AiWarningType.warning)
        .length;
    final hasActionableRule =
        (primaryWarning?.relatedRuleId ?? '').trim().isNotEmpty ||
        (primaryWarning?.relatedRuleTitle ?? '').trim().isNotEmpty;
    final tone = switch (primaryWarning?.type) {
      AiWarningType.warning => theme.colorScheme.error,
      AiWarningType.success => theme.colorScheme.primary,
      AiWarningType.info || null => theme.colorScheme.secondary,
    };
    final icon = analyzing
        ? Icons.auto_awesome_rounded
        : switch (primaryWarning?.type) {
            AiWarningType.warning => Icons.warning_amber_rounded,
            AiWarningType.success => Icons.verified_rounded,
            AiWarningType.info || null => Icons.info_outline_rounded,
          };
    final headline = analyzing
        ? 'Revisando reglas oficiales...'
        : primaryWarning?.title ?? 'Asistente FULLTECH';
    final detail = analyzing
        ? 'Analizando la cotización actual sin bloquear tu trabajo.'
        : primaryWarning?.description ??
              'Sin novedades relevantes en esta cotización.';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: analyzing
                  ? Padding(
                      padding: const EdgeInsets.all(7),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tone,
                      ),
                    )
                  : Icon(icon, color: tone, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (warningCount > 1) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$warningCount alertas',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (primaryWarning != null && hasActionableRule)
              TextButton(
                onPressed: () => onOpenRule(primaryWarning),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Regla'),
              ),
            if (primaryWarning != null)
              IconButton(
                tooltip: 'Preguntar a IA',
                visualDensity: VisualDensity.compact,
                onPressed: () => onAskAi(primaryWarning),
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}
