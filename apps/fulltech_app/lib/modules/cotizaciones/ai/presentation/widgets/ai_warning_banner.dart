import 'package:flutter/material.dart';

import '../../domain/models/ai_warning.dart';
import 'ai_warning_card.dart';

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

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.surfaceContainerLowest,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Asistente FULLTECH',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        analyzing
                            ? 'Revisando la cotización con reglas oficiales...'
                            : 'Advertencias y confirmaciones no bloqueantes para esta cotización.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (analyzing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 14),
              Column(
                children: [
                  for (
                    var index = 0;
                    index < warnings.length && index < 3;
                    index++
                  ) ...[
                    AiWarningCard(
                      warning: warnings[index],
                      onOpenRule: () => onOpenRule(warnings[index]),
                      onAskAi: onAskAi,
                    ),
                    if (index < warnings.length - 1 && index < 2)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
