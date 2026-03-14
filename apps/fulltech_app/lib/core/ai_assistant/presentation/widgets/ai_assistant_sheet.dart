import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ai_assistant_controller.dart';
import '../../domain/models/ai_assistant_message.dart';

class GlobalAiChatSheet extends ConsumerStatefulWidget {
  const GlobalAiChatSheet({super.key});

  @override
  ConsumerState<GlobalAiChatSheet> createState() => _GlobalAiChatSheetState();
}

class _GlobalAiChatSheetState extends ConsumerState<GlobalAiChatSheet> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

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
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom();
    });

    return SafeArea(
      child: Align(
        alignment: isDesktop ? Alignment.centerRight : Alignment.bottomCenter,
        child: Container(
          width: isDesktop ? 520 : null,
          height: isDesktop
              ? double.infinity
              : MediaQuery.sizeOf(context).height * 0.88,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: isDesktop
                ? const BorderRadius.only(
                    topLeft: Radius.circular(28),
                    bottomLeft: Radius.circular(28),
                  )
                : const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
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
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Contexto actual: ${_prettyModule(aiState.context.module)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
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
              Expanded(
                child: _ChatMessagesList(
                  controller: _scrollController,
                  messages: aiState.messages,
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (value) async {
                          await _send(controller);
                        },
                        decoration: InputDecoration(
                          hintText: 'Escribe tu pregunta...',
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerLowest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: aiState.sending
                          ? null
                          : () => _send(controller),
                      child: aiState.sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send(AiAssistantController controller) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await controller.sendMessage(text);
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
