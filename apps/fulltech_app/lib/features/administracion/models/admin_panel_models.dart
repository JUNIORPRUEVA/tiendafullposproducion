class AdminPanelAlert {
  final String code;
  final String title;
  final String detail;
  final String severity;

  const AdminPanelAlert({
    required this.code,
    required this.title,
    required this.detail,
    required this.severity,
  });

  factory AdminPanelAlert.fromJson(Map<String, dynamic> json) {
    return AdminPanelAlert(
      code: (json['code'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      detail: (json['detail'] ?? '').toString(),
      severity: (json['severity'] ?? 'info').toString(),
    );
  }
}

class AdminPanelOverview {
  final Map<String, dynamic> metrics;
  final List<AdminPanelAlert> alerts;
  final String generatedAt;

  const AdminPanelOverview({
    required this.metrics,
    required this.alerts,
    required this.generatedAt,
  });

  factory AdminPanelOverview.fromJson(Map<String, dynamic> json) {
    final rows = (json['alerts'] is List) ? (json['alerts'] as List) : const [];
    return AdminPanelOverview(
      metrics: (json['metrics'] is Map)
          ? (json['metrics'] as Map).cast<String, dynamic>()
          : const {},
      alerts: rows
          .whereType<Map>()
          .map((item) => AdminPanelAlert.fromJson(item.cast<String, dynamic>()))
          .toList(),
      generatedAt: (json['generatedAt'] ?? '').toString(),
    );
  }
}

class AdminAiInsights {
  final String source;
  final String message;
  final Map<String, dynamic> metrics;
  final List<AdminPanelAlert> alerts;

  const AdminAiInsights({
    required this.source,
    required this.message,
    required this.metrics,
    required this.alerts,
  });

  factory AdminAiInsights.fromJson(Map<String, dynamic> json) {
    final rows = (json['alerts'] is List) ? (json['alerts'] as List) : const [];
    return AdminAiInsights(
      source: (json['source'] ?? 'rules').toString(),
      message: (json['message'] ?? '').toString(),
      metrics: (json['metrics'] is Map)
          ? (json['metrics'] as Map).cast<String, dynamic>()
          : const {},
      alerts: rows
          .whereType<Map>()
          .map((item) => AdminPanelAlert.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}
