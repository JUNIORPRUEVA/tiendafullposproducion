import 'ai_assistant_citation.dart';

class AiAssistantMessage {
  final String id;
  final AiAssistantMessageRole role;
  final String content;
  final DateTime createdAt;
  final List<AiAssistantCitation> citations;

  const AiAssistantMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.citations = const [],
  });

  bool get isUser => role == AiAssistantMessageRole.user;
}

enum AiAssistantMessageRole { user, assistant }
