class BusinessRuleReference {
  const BusinessRuleReference({
    required this.id,
    required this.module,
    required this.category,
    required this.title,
  });

  final String id;
  final String module;
  final String category;
  final String title;

  Map<String, dynamic> toMap() => {
    'id': id,
    'module': module,
    'category': category,
    'title': title,
  };
}

enum BusinessRuleSeverity { info, warning, critical }

class BusinessRule {
  const BusinessRule({
    required this.id,
    required this.module,
    required this.category,
    required this.title,
    required this.content,
    required this.keywords,
    required this.severity,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
    this.summary,
  });

  final String id;
  final String module;
  final String category;
  final String title;
  final String? summary;
  final String content;
  final List<String> keywords;
  final BusinessRuleSeverity severity;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  BusinessRuleReference toReference() => BusinessRuleReference(
    id: id,
    module: module,
    category: category,
    title: title,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'module': module,
    'category': category,
    'title': title,
    'summary': summary,
    'content': content,
    'keywords': keywords,
    'severity': severity.name,
    'active': active,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };
}
