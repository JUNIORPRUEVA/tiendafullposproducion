import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/auth_provider.dart';
import '../../../routing/routes.dart';
import '../../domain/models/ai_chat_context.dart';
import '../../application/ai_assistant_controller.dart';
import 'ai_assistant_sheet.dart';

class GlobalAiAssistantEntryPoint extends ConsumerStatefulWidget {
  const GlobalAiAssistantEntryPoint({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GlobalAiAssistantEntryPoint> createState() =>
      _GlobalAiAssistantEntryPointState();
}

class _GlobalAiAssistantEntryPointState
    extends ConsumerState<GlobalAiAssistantEntryPoint> {
  bool _desktopPanelOpen = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    if (!auth.isAuthenticated) return widget.child;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    return Stack(
      children: [
        widget.child,
        if (isDesktop) ...[
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_desktopPanelOpen,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 90),
                curve: Curves.easeOut,
                opacity: _desktopPanelOpen ? 1 : 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => _closeDesktopPanel(),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_desktopPanelOpen,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 110),
                curve: Curves.easeOutCubic,
                offset: _desktopPanelOpen ? Offset.zero : const Offset(1, 0),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 90),
                  curve: Curves.easeOut,
                  opacity: _desktopPanelOpen ? 1 : 0,
                  child: RepaintBoundary(
                    child: GlobalAiChatSheet(onClose: _closeDesktopPanel),
                  ),
                ),
              ),
            ),
          ),
        ],
        Positioned(
          right: isDesktop ? 0 : 18,
          bottom: isDesktop ? 26 : 18,
          child: Builder(
            builder: (innerContext) {
              final assistantContext = _buildAssistantContext(innerContext);

              return _AiAssistantDockButton(
                onPressed: () =>
                    _openAssistant(innerContext, ref, assistantContext),
                isActive: isDesktop && _desktopPanelOpen,
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
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    if (isDesktop) {
      controller.setContext(assistantContext);
      setState(() => _desktopPanelOpen = !_desktopPanelOpen);
      return;
    }

    controller.setContext(assistantContext);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GlobalAiChatSheet(),
    );
  }

  void _closeDesktopPanel() {
    if (!_desktopPanelOpen || !mounted) return;
    setState(() => _desktopPanelOpen = false);
  }
}

class _AiAssistantDockButton extends StatelessWidget {
  const _AiAssistantDockButton({
    required this.onPressed,
    this.isActive = false,
  });

  final VoidCallback onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(24),
      bottomLeft: const Radius.circular(24),
      topRight: Radius.circular(isDesktop ? 0 : 24),
      bottomRight: Radius.circular(isDesktop ? 0 : 24),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: borderRadius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              colors: isActive
                  ? const [
                      Color(0xFF0E2A6F),
                      Color(0xFF173DA8),
                      Color(0xFF13B8C8),
                    ]
                  : const [
                      Color(0xFF173DA8),
                      Color(0xFF2457D6),
                      Color(0xFF13B8C8),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF173DA8).withValues(alpha: 0.26),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Container(
            height: 64,
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 18 : 16,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 10),
                  const Text(
                    'IA',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
