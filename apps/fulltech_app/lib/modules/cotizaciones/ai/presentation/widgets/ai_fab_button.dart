import 'package:flutter/material.dart';

class AiFabButton extends StatelessWidget {
  const AiFabButton({
    super.key,
    required this.onPressed,
    required this.isDesktop,
  });

  final VoidCallback onPressed;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: onPressed,
        elevation: 0,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        icon: const Icon(Icons.auto_awesome_rounded),
        label: Text(isDesktop ? 'Asistente FULLTECH' : 'IA'),
      ),
    );
  }
}
