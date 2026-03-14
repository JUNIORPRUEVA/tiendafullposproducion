import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/ai_assistant_datasource.dart';
import '../models/ai_chat_context.dart';
import '../models/ai_assistant_citation.dart';

final aiAssistantServiceProvider = Provider<AiAssistantService>((ref) {
  return AiAssistantService(ref.watch(aiAssistantDataSourceProvider));
});

class AiAssistantChatResult {
  final String content;
  final bool denied;
  final List<AiAssistantCitation> citations;

  const AiAssistantChatResult({
    required this.content,
    required this.denied,
    required this.citations,
  });
}

class AiAssistantService {
  final AiAssistantDataSource _dataSource;

  AiAssistantService(this._dataSource);

  Future<AiAssistantChatResult> chat({
    required AiChatContext context,
    required String message,
    required List<Map<String, dynamic>> history,
  }) async {
    final res = await _dataSource.chat(
      context: context,
      message: message,
      history: history,
    );

    final content = (res['content'] ?? res['message'] ?? '').toString();
    final denied = res['denied'] == true;

    final rawCitations = res['citations'];
    final citations = <AiAssistantCitation>[];
    if (rawCitations is List) {
      for (final item in rawCitations) {
        if (item is Map) {
          citations.add(
            AiAssistantCitation.fromMap(item.cast<String, dynamic>()),
          );
        }
      }
    }

    return AiAssistantChatResult(
      content: content.trim().isEmpty
          ? 'No pude generar una respuesta válida. Inténtalo de nuevo.'
          : content,
      denied: denied,
      citations: citations,
    );
  }
}
