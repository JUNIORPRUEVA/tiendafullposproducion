import 'package:flutter/material.dart';

class MisAmonestacionesPendientesScreen extends StatelessWidget {
  const MisAmonestacionesPendientesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Amonestaciones del colaborador'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'El flujo de firma de amonestaciones fue desactivado.\n\n'
            'Si necesitas revisar una amonestacion, solicita acceso al modulo de amonestaciones a un usuario autorizado.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
