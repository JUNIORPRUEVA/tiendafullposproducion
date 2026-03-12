enum AiWarningType { info, warning, success }

class AiWarning {
  const AiWarning({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.relatedRuleId,
    required this.relatedRuleTitle,
    required this.suggestedAction,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String description;
  final AiWarningType type;
  final String? relatedRuleId;
  final String? relatedRuleTitle;
  final String? suggestedAction;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'type': type.name,
    'relatedRuleId': relatedRuleId,
    'relatedRuleTitle': relatedRuleTitle,
    'suggestedAction': suggestedAction,
    'createdAt': createdAt.toIso8601String(),
  };
}
