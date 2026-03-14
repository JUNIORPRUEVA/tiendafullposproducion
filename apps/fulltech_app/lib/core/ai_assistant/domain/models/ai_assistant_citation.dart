class AiAssistantCitation {
  final String id;
  final String module;
  final String category;
  final String title;

  const AiAssistantCitation({
    required this.id,
    required this.module,
    required this.category,
    required this.title,
  });

  factory AiAssistantCitation.fromMap(Map<String, dynamic> map) {
    return AiAssistantCitation(
      id: (map['id'] ?? '').toString(),
      module: (map['module'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
    );
  }
}
