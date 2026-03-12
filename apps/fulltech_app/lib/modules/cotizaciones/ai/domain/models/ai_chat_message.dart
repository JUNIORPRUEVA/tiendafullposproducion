import 'business_rule.dart';

enum AiChatRole { assistant, user }

class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.relatedRuleId,
    this.relatedRuleTitle,
    this.citations = const [],
    this.isLoading = false,
    this.isError = false,
  });

  final String id;
  final AiChatRole role;
  final String content;
  final DateTime createdAt;
  final String? relatedRuleId;
  final String? relatedRuleTitle;
  final List<BusinessRuleReference> citations;
  final bool isLoading;
  final bool isError;

  AiChatMessage copyWith({
    String? id,
    AiChatRole? role,
    String? content,
    DateTime? createdAt,
    String? relatedRuleId,
    String? relatedRuleTitle,
    List<BusinessRuleReference>? citations,
    bool? isLoading,
    bool? isError,
  }) {
    return AiChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      relatedRuleId: relatedRuleId ?? this.relatedRuleId,
      relatedRuleTitle: relatedRuleTitle ?? this.relatedRuleTitle,
      citations: citations ?? this.citations,
      isLoading: isLoading ?? this.isLoading,
      isError: isError ?? this.isError,
    );
  }
}
