import 'package:flutter/material.dart';

class QuickAiActions extends StatelessWidget {
  const QuickAiActions({super.key, required this.onAction});

  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    const actions = <String>[
      'Revisar cotización',
      'Ver precio mínimo',
      'Ver garantía',
      'Ver reglas del DVR',
      'Ver instalación',
      'Explicar advertencias',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final action in actions)
          ActionChip(
            label: Text(action),
            avatar: const Icon(Icons.bolt_rounded, size: 16),
            onPressed: () => onAction(action),
          ),
      ],
    );
  }
}
