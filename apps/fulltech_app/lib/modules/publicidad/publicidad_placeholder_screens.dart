import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';

class PublicidadCampanasScreen extends ConsumerWidget {
  const PublicidadCampanasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _PublicidadComingSoonScreen(
      title: 'Campañas',
      subtitle: 'Crear contenido y anuncios para campañas pagadas.',
      description:
          'Este submódulo quedará preparado para IA y aprobación semi-automática.',
      icon: Icons.rocket_launch_rounded,
    );
  }
}

class PublicidadMarketplaceScreen extends ConsumerWidget {
  const PublicidadMarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _PublicidadComingSoonScreen(
      title: 'Marketplace',
      subtitle: 'Crear publicaciones optimizadas para Facebook Marketplace.',
      description:
          'Este submódulo quedará preparado para IA y aprobación semi-automática.',
      icon: Icons.storefront_rounded,
    );
  }
}

class _PublicidadComingSoonScreen extends ConsumerWidget {
  const _PublicidadComingSoonScreen({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    final isAdmin =
        user != null && hasPermission(user.appRole, AppPermission.viewPublicidad);
    final scheme = Theme.of(context).colorScheme;

    if (!isAdmin) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Publicidad', showLogo: false),
        body: const Center(
          child: Text('Acceso denegado. Solo ADMIN puede usar Publicidad.'),
        ),
      );
    }

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: CustomAppBar(title: 'Publicidad / $title'),
      backgroundColor: scheme.surfaceContainerLowest,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Card(
            elevation: 0,
            color: scheme.surface,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: scheme.onPrimaryContainer, size: 30),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(subtitle, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 14),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
