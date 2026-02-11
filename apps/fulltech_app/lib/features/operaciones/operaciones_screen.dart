import 'package:flutter/material.dart';

class OperacionesScreen extends StatelessWidget {
  const OperacionesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modules = ['Servicios', 'Instalaciones', 'Garantías', 'Mantenimientos'];
    final tasks = List.generate(5, (i) => 'Tarea reciente #$i');
    return Scaffold(
      appBar: AppBar(title: const Text('Operaciones')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: modules
                  .map((m) => SizedBox(
                        width: 150,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m, style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 8),
                                const Text('Placeholder de módulo'),
                              ],
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Text('Tareas recientes', style: Theme.of(context).textTheme.titleLarge),
            Expanded(
              child: ListView.builder(
                itemCount: tasks.length,
                itemBuilder: (context, i) => ListTile(title: Text(tasks[i]), subtitle: const Text('Pendiente')), 
              ),
            ),
          ],
        ),
      ),
    );
  }
}
