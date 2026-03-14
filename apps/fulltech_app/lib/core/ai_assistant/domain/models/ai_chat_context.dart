class AiChatContext {
  final String module;
  final String? screenName;
  final String? route;
  final String? entityType;
  final String? entityId;

  const AiChatContext({
    required this.module,
    this.screenName,
    this.route,
    this.entityType,
    this.entityId,
  });

  Map<String, dynamic> toMap() {
    return {
      'module': module,
      if ((screenName ?? '').trim().isNotEmpty) 'screenName': screenName,
      if ((route ?? '').trim().isNotEmpty) 'route': route,
      if ((entityType ?? '').trim().isNotEmpty) 'entityType': entityType,
      if ((entityId ?? '').trim().isNotEmpty) 'entityId': entityId,
    };
  }

  AiChatContext copyWith({
    String? module,
    String? screenName,
    String? route,
    String? entityType,
    String? entityId,
  }) {
    return AiChatContext(
      module: module ?? this.module,
      screenName: screenName ?? this.screenName,
      route: route ?? this.route,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
    );
  }
}
