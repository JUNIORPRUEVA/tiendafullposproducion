import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/trace_id.dart';
import '../domain/models/ai_chat_context.dart';
import '../domain/models/ai_assistant_message.dart';
import '../domain/services/ai_assistant_service.dart';

class AiAssistantState {
  final AiChatContext context;
  final List<AiAssistantMessage> messages;
  final bool sending;
  final String? lastError;

  const AiAssistantState({
    required this.context,
    this.messages = const [],
    this.sending = false,
    this.lastError,
  });

  AiAssistantState copyWith({
    AiChatContext? context,
    List<AiAssistantMessage>? messages,
    bool? sending,
    String? lastError,
    bool clearError = false,
  }) {
    return AiAssistantState(
      context: context ?? this.context,
      messages: messages ?? this.messages,
      sending: sending ?? this.sending,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

final aiAssistantControllerProvider =
    StateNotifierProvider<AiAssistantController, AiAssistantState>((ref) {
      return AiAssistantController(ref.watch(aiAssistantServiceProvider));
    });

class AiAssistantController extends StateNotifier<AiAssistantState> {
  AiAssistantController(this._service)
    : super(AiAssistantState(context: const AiChatContext(module: 'general')));

  final AiAssistantService _service;

  void setContext(AiChatContext context) {
    state = state.copyWith(context: context);
  }

  List<Map<String, dynamic>> _buildHistoryPayload() {
    final all = state.messages;
    final start = all.length > 16 ? all.length - 16 : 0;
    final items = all.sublist(start);
    return items.map((m) {
      return {'role': m.isUser ? 'user' : 'assistant', 'content': m.content};
    }).toList();
  }

  Future<void> sendMessage(String message) async {
    final normalized = message.trim();
    if (normalized.isEmpty) return;

    if (state.sending) return;

    final now = DateTime.now();
    final nextMessages = List<AiAssistantMessage>.from(state.messages)
      ..add(
        AiAssistantMessage(
          id: TraceId.next('ai-user'),
          role: AiAssistantMessageRole.user,
          content: normalized,
          createdAt: now,
        ),
      );

    state = state.copyWith(
      messages: nextMessages,
      sending: true,
      clearError: true,
    );

    try {
      final result = await _service.chat(
        context: state.context,
        message: normalized,
        history: _buildHistoryPayload(),
      );

      final assistant = AiAssistantMessage(
        id: TraceId.next('ai-assistant'),
        role: AiAssistantMessageRole.assistant,
        content: result.content,
        citations: result.citations,
        createdAt: DateTime.now(),
      );

      state = state.copyWith(
        messages: [...state.messages, assistant],
        sending: false,
      );
    } catch (e) {
      final content = e.toString();
      final assistant = AiAssistantMessage(
        id: TraceId.next('ai-assistant-error'),
        role: AiAssistantMessageRole.assistant,
        content: content,
        createdAt: DateTime.now(),
      );
      state = state.copyWith(
        messages: [...state.messages, assistant],
        sending: false,
        lastError: content,
      );
    }
  }
}
