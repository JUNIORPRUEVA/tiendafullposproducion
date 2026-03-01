import 'package:flutter/material.dart';

import 'status_chip.dart';

class ServiceHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final VoidCallback onActions;

  const ServiceHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onActions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusChip(status: status),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onActions,
              icon: const Icon(Icons.more_horiz_rounded, size: 18),
              label: const Text('Acciones'),
            ),
          ],
        ),
      ],
    );
  }
}
