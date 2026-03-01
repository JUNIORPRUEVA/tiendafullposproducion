import 'package:flutter/material.dart';

class OperacionesReglasScreen extends StatelessWidget {
  const OperacionesReglasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Reglas',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.rule_folder_outlined, size: 42, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              const Text(
                'Pantalla de reglas',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Aquí se mostrarán y configurarán las reglas del Centro de Operaciones.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
