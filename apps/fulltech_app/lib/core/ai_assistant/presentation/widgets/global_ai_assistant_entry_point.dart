import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/auth_provider.dart';
import '../../domain/models/ai_chat_context.dart';
import '../../application/ai_assistant_controller.dart';
import 'ai_assistant_sheet.dart';

class GlobalAiAssistantEntryPoint extends ConsumerWidget {
  const GlobalAiAssistantEntryPoint({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    if (!auth.isAuthenticated) return child;

    return Stack(
      children: [
        child,
        Positioned(
          right: 18,
          bottom: 18,
          child: Builder(
            builder: (innerContext) {
              final location = _safeLocation(innerContext);
              final module = _moduleFromLocation(location);

              return FloatingActionButton(
                onPressed: () =>
                    _openAssistant(innerContext, ref, module, location),
                tooltip: 'Asistente IA',
                child: const Icon(Icons.auto_awesome_rounded),
              );
            },
          ),
        ),
      ],
    );
  }

  String _safeLocation(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.toString();
    } catch (_) {
      return '';
    }
  }

  String _moduleFromLocation(String location) {
    final path = location.trim().toLowerCase();
    if (path.startsWith('/clientes')) return 'clientes';
    if (path.startsWith('/catalogo')) return 'catalogo';
    if (path.startsWith('/ventas')) return 'ventas';
    if (path.startsWith('/operaciones')) return 'operaciones';
    if (path.startsWith('/contabilidad')) return 'contabilidad';
    if (path.startsWith('/nomina') || path.startsWith('/mis-pagos')) {
      return 'nomina';
    }
    if (path.startsWith('/manual-interno')) return 'manual-interno';
    if (path.startsWith('/configuracion')) return 'configuracion';
    if (path.startsWith('/administracion')) return 'administracion';
    if (path.startsWith('/cotizaciones')) return 'cotizaciones';
    return 'general';
  }

  void _openAssistant(
    BuildContext context,
    WidgetRef ref,
    String module,
    String route,
  ) {
    final controller = ref.read(aiAssistantControllerProvider.notifier);
    controller.setContext(
      AiChatContext(
        module: module,
        route: route,
        screenName: null,
        entityType: null,
        entityId: null,
      ),
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GlobalAiChatSheet(),
    );
  }
}
