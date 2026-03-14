import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ai_assistant_controller.dart';
import '../../domain/models/ai_chat_context.dart';
import '../../domain/models/ai_assistant_message.dart';

class GlobalAiChatSheet extends ConsumerStatefulWidget {
  const GlobalAiChatSheet({super.key});

  @override
  ConsumerState<GlobalAiChatSheet> createState() => _GlobalAiChatSheetState();
}

class _GlobalAiChatSheetState extends ConsumerState<GlobalAiChatSheet> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const _defaultQuickPrompts = <String>[
    'Cual es mi informacion en la app',
    'Que productos hay en catalogo',
    'Explicame esta pantalla',
    'Que puedo hacer en este modulo',
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiState = ref.watch(aiAssistantControllerProvider);
    final controller = ref.read(aiAssistantControllerProvider.notifier);
    final size = MediaQuery.sizeOf(context);
    final isDesktop = size.width >= 900;
    final quickPrompts = _quickPromptsForContext(aiState.context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom();
    });

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isDesktop ? 0 : 10,
          isDesktop ? 18 : 10,
          isDesktop ? 18 : 10,
          isDesktop ? 18 : 0,
        ),
        child: Align(
          alignment: isDesktop ? Alignment.centerRight : Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 420 : size.width,
              maxHeight: isDesktop ? 760 : size.height * 0.82,
            ),
            child: Container(
              width: isDesktop ? 420 : null,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.32,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.surfaceContainerHighest,
                            theme.colorScheme.surface,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Asistente FULLTECH',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _buildContextLabel(aiState.context),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'IA interna',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: quickPrompts
                                .map(
                                  (prompt) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ActionChip(
                                      onPressed: aiState.sending
                                          ? null
                                          : () =>
                                                _sendPreset(controller, prompt),
                                      backgroundColor: theme
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      side: BorderSide(
                                        color: theme.colorScheme.outlineVariant
                                            .withValues(alpha: 0.28),
                                      ),
                                      label: Text(
                                        prompt,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _ChatMessagesList(
                        controller: _scrollController,
                        messages: aiState.messages,
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) async {
                                await _send(controller);
                              },
                              decoration: InputDecoration(
                                hintText: 'Escribe tu pregunta...',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                filled: true,
                                fillColor:
                                    theme.colorScheme.surfaceContainerLowest,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.28),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.28),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 48,
                            width: 48,
                            child: FilledButton(
                              onPressed: aiState.sending
                                  ? null
                                  : () => _send(controller),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              child: aiState.sending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_upward_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<String> _quickPromptsForContext(AiChatContext context) {
    switch (context.module.trim().toLowerCase()) {
      case 'catalogo':
      case 'catálogo':
        return const [
          'Que productos hay en catalogo',
          'Buscame taladros disponibles en catalogo',
          'Que categorias de productos existen',
          'Muestrame productos con precio',
        ];
      case 'clientes':
        return const [
          'Explicame esta pantalla',
          'Que informacion puedo ver del cliente',
          'Que acciones puedo hacer aqui',
          'Resumen del cliente seleccionado',
        ];
      case 'operaciones':
        return const [
          'Explicame esta pantalla',
          'Resumen del servicio actual',
          'Que puedo hacer en este modulo',
          'Cual es el siguiente paso recomendado',
        ];
      case 'cotizaciones':
        return const [
          'Explicame esta pantalla',
          'Resumen de la cotizacion actual',
          'Que reglas aplican aqui',
          'Que puedo hacer en este modulo',
        ];
      case 'profile':
      case 'nomina':
        return const [
          'Cual es mi informacion en la app',
          'Cual es mi rol',
          'Que datos mios puedes ver',
          'Explicame esta pantalla',
        ];
      default:
        return _defaultQuickPrompts;
    }
  }

  Future<void> _send(AiAssistantController controller) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await controller.sendMessage(text);
  }

  Future<void> _sendPreset(
    AiAssistantController controller,
    String prompt,
  ) async {
    _messageController.clear();
    await controller.sendMessage(prompt);
  }

  String _buildContextLabel(AiChatContext context) {
    final module = _prettyModule(context.module);
    final screen = (context.screenName ?? '').trim();
    if (screen.isEmpty) return 'Contexto actual: $module';
    return 'Contexto actual: $module · $screen';
  }

  String _prettyModule(String module) {
    final normalized = module.trim().toLowerCase();
    switch (normalized) {
      case 'operaciones':
        return 'Operaciones';
      case 'clientes':
        return 'Clientes';
      case 'catalogo':
      case 'catálogo':
        return 'Catálogo';
      case 'ventas':
        return 'Ventas';
      case 'cotizaciones':
        return 'Cotizaciones';
      case 'nomina':
      case 'nómina':
        return 'Nómina';
      case 'manual-interno':
        return 'Manual Interno';
      case 'configuracion':
        return 'Configuración';
      case 'administracion':
        return 'Administración';
      default:
        return 'General';
    }
  }
}

class _ChatMessagesList extends StatelessWidget {
  const _ChatMessagesList({required this.controller, required this.messages});

  final ScrollController controller;
  final List<AiAssistantMessage> messages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (messages.isEmpty) {
      return ListView(
        reverse: true,
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Pregúntame sobre procesos, pantallas y reglas del Manual Interno. Si estás en una pantalla específica, abre el asistente desde ahí para mejor contexto.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      reverse: true,
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[messages.length - 1 - index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _MessageBubble(message: msg),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AiAssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    final background = isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerLowest;

    final foreground = isUser
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: isUser
                ? null
                : Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  message.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    height: 1.35,
                  ),
                ),
                if (!isUser && message.citations.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Fuentes: ${message.citations.map((c) => c.title).take(3).join(' • ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
