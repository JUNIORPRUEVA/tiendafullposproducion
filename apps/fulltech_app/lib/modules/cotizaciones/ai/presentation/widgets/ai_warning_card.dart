import 'package:flutter/material.dart';

import '../../domain/models/ai_warning.dart';

class AiWarningCard extends StatelessWidget {
  const AiWarningCard({
    super.key,
    required this.warning,
    required this.onOpenRule,
    required this.onAskAi,
  });

  final AiWarning warning;
  final VoidCallback? onOpenRule;
  final ValueChanged<AiWarning>? onAskAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = switch (warning.type) {
      AiWarningType.warning => theme.colorScheme.error,
      AiWarningType.success => theme.colorScheme.primary,
      AiWarningType.info => theme.colorScheme.secondary,
    };
    final icon = switch (warning.type) {
      AiWarningType.warning => Icons.warning_amber_rounded,
      AiWarningType.success => Icons.verified_rounded,
      AiWarningType.info => Icons.info_outline_rounded,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: tone, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        warning.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        warning.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if ((warning.suggestedAction ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                warning.suggestedAction!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onOpenRule != null)
                  OutlinedButton.icon(
                    onPressed: onOpenRule,
                    icon: const Icon(Icons.rule_folder_outlined),
                    label: const Text('Ver regla'),
                  ),
                if (onAskAi != null)
                  FilledButton.tonalIcon(
                    onPressed: () => onAskAi?.call(warning),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Preguntar a IA'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
