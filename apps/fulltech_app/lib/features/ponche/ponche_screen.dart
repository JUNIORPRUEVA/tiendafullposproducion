import 'package:flutter/material.dart';
import '../../core/models/punch_model.dart';

class PoncheScreen extends StatelessWidget {
  const PoncheScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mockHistory = List.generate(
      5,
      (i) => PunchModel(id: '$i', type: i % 2 == 0 ? 'in' : 'out', timestamp: DateTime.now().subtract(Duration(hours: i * 2))),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Ponche')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.login), label: const Text('Entrada')),
                ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.logout), label: const Text('Salida')),
                ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.fastfood), label: const Text('Inicio Almuerzo')),
                ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.restaurant), label: const Text('Fin Almuerzo')),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: mockHistory.length,
                itemBuilder: (context, i) {
                  final p = mockHistory[i];
                  return ListTile(
                    leading: Icon(p.type == 'in' ? Icons.login : Icons.logout),
                    title: Text(p.type),
                    subtitle: Text(p.timestamp.toIso8601String()),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}
