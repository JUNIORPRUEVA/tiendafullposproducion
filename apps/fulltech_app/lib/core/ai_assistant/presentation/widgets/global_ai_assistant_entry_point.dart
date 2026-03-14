import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/auth_provider.dart';
import '../../../routing/routes.dart';
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
              final assistantContext = _buildAssistantContext(innerContext);

              return FloatingActionButton(
                onPressed: () =>
                    _openAssistant(innerContext, ref, assistantContext),
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

  AiChatContext _buildAssistantContext(BuildContext context) {
    final location = _safeLocation(context);
    final uri = Uri.tryParse(location) ?? Uri(path: location);
    final path = uri.path.trim().toLowerCase();
    final segments = uri.pathSegments
        .map((segment) => segment.trim().toLowerCase())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    var module = 'general';
    var screenName = _screenNameFromPath(path);
    String? entityType;
    String? entityId;

    if (path.startsWith('/clientes')) {
      module = 'clientes';
      if (segments.length >= 2 && segments[1] != 'nuevo') {
        entityType = 'client';
        entityId = segments[1];
      }
    } else if (path.startsWith('/catalogo')) {
      module = 'catalogo';
    } else if (path.startsWith('/ventas')) {
      module = 'ventas';
    } else if (path.startsWith('/operaciones')) {
      module = 'operaciones';
      if (segments.length >= 2 &&
          segments[1] != 'agenda' &&
          segments[1] != 'mapa-clientes' &&
          segments[1] != 'reglas') {
        entityType = 'service';
        entityId = segments[1];
      }
    } else if (path.startsWith('/contabilidad')) {
      module = 'contabilidad';
    } else if (path.startsWith('/nomina') || path.startsWith('/mis-pagos')) {
      module = 'nomina';
    } else if (path.startsWith('/manual-interno')) {
      module = 'manual-interno';
    } else if (path.startsWith('/configuracion')) {
      module = 'configuracion';
    } else if (path.startsWith('/administracion')) {
      module = 'administracion';
    } else if (path.startsWith('/cotizaciones')) {
      module = 'cotizaciones';
      final quoteId = (uri.queryParameters['quoteId'] ?? '').trim();
      final customerPhone = (uri.queryParameters['customerPhone'] ?? '').trim();
      if (quoteId.isNotEmpty) {
        entityType = 'quote';
        entityId = quoteId;
      } else if (customerPhone.isNotEmpty) {
        entityType = 'client-phone';
        entityId = customerPhone;
      }
    } else if (path.startsWith('/users')) {
      module = 'administracion';
      if (segments.length >= 2) {
        entityType = 'user';
        entityId = segments[1];
      }
    }

    return AiChatContext(
      module: module,
      route: uri.toString(),
      screenName: screenName,
      entityType: entityType,
      entityId: entityId,
    );
  }

  String? _screenNameFromPath(String path) {
    switch (path) {
      case Routes.profile:
        return 'Perfil';
      case Routes.horarios:
        return 'Horarios';
      case Routes.operaciones:
        return 'Operaciones';
      case Routes.operacionesAgenda:
        return 'Agenda de operaciones';
      case Routes.operacionesMapaClientes:
        return 'Mapa de clientes';
      case Routes.operacionesReglas:
        return 'Reglas operativas';
      case Routes.catalogo:
        return 'Catálogo';
      case Routes.contabilidad:
        return 'Contabilidad';
      case Routes.contabilidadCierresDiarios:
        return 'Cierres diarios';
      case Routes.contabilidadFacturaFiscal:
        return 'Facturas fiscales';
      case Routes.contabilidadPagosPendientes:
        return 'Pagos pendientes';
      case Routes.clientes:
        return 'Clientes';
      case Routes.clienteNuevo:
        return 'Nuevo cliente';
      case Routes.ventas:
        return 'Ventas';
      case Routes.registrarVenta:
        return 'Registrar venta';
      case Routes.cotizaciones:
        return 'Cotizaciones';
      case Routes.cotizacionesHistorial:
        return 'Historial de cotizaciones';
      case Routes.nomina:
        return 'Nómina';
      case Routes.misPagos:
        return 'Mis pagos';
      case Routes.manualInterno:
        return 'Manual interno';
      case Routes.configuracion:
        return 'Configuración';
      case Routes.administracion:
        return 'Administración';
      case Routes.salidasTecnicas:
        return 'Salidas técnicas';
      case Routes.users:
      case Routes.user:
        return 'Usuarios';
    }

    if (path.startsWith('/clientes/') && path.endsWith('/editar')) {
      return 'Editar cliente';
    }
    if (path.startsWith('/clientes/')) {
      return 'Detalle de cliente';
    }
    if (path.startsWith('/users/')) {
      return 'Detalle de usuario';
    }
    return null;
  }

  void _openAssistant(
    BuildContext context,
    WidgetRef ref,
    AiChatContext assistantContext,
  ) {
    final controller = ref.read(aiAssistantControllerProvider.notifier);
    controller.setContext(assistantContext);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GlobalAiChatSheet(),
    );
  }
}
