import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/loading/app_loading_screen.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);

    return AppLoadingScreen(
      title: auth.restoringSession
          ? 'Restaurando sesión…'
          : 'Abriendo tu espacio de trabajo…',
      subtitle: auth.restoringSession
          ? 'Usando la sesión guardada primero y verificando el backend en segundo plano.'
          : 'Preparando la navegación inicial de forma segura.',
      statusLabel: auth.user == null ? 'Acceso rápido' : 'Sesión local lista',
    );
  }
}
