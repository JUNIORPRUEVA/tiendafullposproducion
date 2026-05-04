class MarketingFlowConfig {
  const MarketingFlowConfig({
    required this.id,
    required this.active,
    required this.paused,
    required this.dailyStoriesCount,
    required this.generationTime,
    required this.autoRegenerate,
    required this.regenerateAfterHours,
    required this.priorityProducts,
    required this.targetCity,
    required this.brandTone,
  });

  final String id;
  final bool active;
  final bool paused;
  final int dailyStoriesCount;
  final String generationTime;
  final bool autoRegenerate;
  final int regenerateAfterHours;
  final List<String> priorityProducts;
  final String targetCity;
  final String brandTone;

  factory MarketingFlowConfig.fromJson(Map<String, dynamic> json) {
    return MarketingFlowConfig(
      id: '${json['id'] ?? ''}',
      active: json['active'] == true,
      paused: json['paused'] == true,
      dailyStoriesCount: (json['dailyStoriesCount'] as num?)?.toInt() ?? 3,
      generationTime: '${json['generationTime'] ?? '08:00'}',
      autoRegenerate: json['autoRegenerate'] == true,
      regenerateAfterHours:
          (json['regenerateAfterHours'] as num?)?.toInt() ?? 6,
      priorityProducts: (json['priorityProducts'] is List)
          ? (json['priorityProducts'] as List)
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const [],
      targetCity: '${json['targetCity'] ?? ''}',
      brandTone: '${json['brandTone'] ?? ''}',
    );
  }
}

enum MarketingStoryType { sales, trust, educational }

enum MarketingStoryStatus { pending, approved, rejected, regenerated }

MarketingStoryType parseStoryType(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  switch (normalized) {
    case 'TRUST':
      return MarketingStoryType.trust;
    case 'EDUCATIONAL':
      return MarketingStoryType.educational;
    case 'SALES':
    default:
      return MarketingStoryType.sales;
  }
}

MarketingStoryStatus parseStoryStatus(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  switch (normalized) {
    case 'APPROVED':
      return MarketingStoryStatus.approved;
    case 'REJECTED':
      return MarketingStoryStatus.rejected;
    case 'REGENERATED':
      return MarketingStoryStatus.regenerated;
    case 'PENDING':
    default:
      return MarketingStoryStatus.pending;
  }
}

String storyTypeApiValue(MarketingStoryType type) {
  switch (type) {
    case MarketingStoryType.sales:
      return 'SALES';
    case MarketingStoryType.trust:
      return 'TRUST';
    case MarketingStoryType.educational:
      return 'EDUCATIONAL';
  }
}

String storyStatusApiValue(MarketingStoryStatus status) {
  switch (status) {
    case MarketingStoryStatus.pending:
      return 'PENDING';
    case MarketingStoryStatus.approved:
      return 'APPROVED';
    case MarketingStoryStatus.rejected:
      return 'REJECTED';
    case MarketingStoryStatus.regenerated:
      return 'REGENERATED';
  }
}

class MarketingStory {
  const MarketingStory({
    required this.id,
    required this.date,
    required this.type,
    required this.title,
    required this.shortText,
    required this.longText,
    required this.hashtags,
    required this.imagePrompt,
    required this.imageUrl,
    required this.status,
    required this.generationAttempt,
    required this.approvedByUserName,
    required this.approvedAt,
    required this.rejectedAt,
    required this.updatedAt,
  });

  final String id;
  final DateTime date;
  final MarketingStoryType type;
  final String title;
  final String shortText;
  final String longText;
  final List<String> hashtags;
  final String imagePrompt;
  final String imageUrl;
  final MarketingStoryStatus status;
  final int generationAttempt;
  final String approvedByUserName;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final DateTime? updatedAt;

  int get regeneratedCount =>
      generationAttempt <= 1 ? 0 : generationAttempt - 1;

  factory MarketingStory.fromJson(Map<String, dynamic> json) {
    final approvedBy = json['approvedByUser'];
    final approvedByName = approvedBy is Map
        ? '${approvedBy['nombreCompleto'] ?? ''}'.trim()
        : '';

    return MarketingStory(
      id: '${json['id'] ?? ''}',
      date: DateTime.tryParse('${json['date'] ?? ''}') ?? DateTime.now(),
      type: parseStoryType('${json['type'] ?? ''}'),
      title: '${json['title'] ?? ''}',
      shortText: '${json['shortText'] ?? ''}',
      longText: '${json['longText'] ?? ''}',
      hashtags: (json['hashtags'] is List)
          ? (json['hashtags'] as List)
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const [],
      imagePrompt: '${json['imagePrompt'] ?? ''}',
      imageUrl: '${json['imageUrl'] ?? ''}',
      status: parseStoryStatus('${json['status'] ?? ''}'),
      generationAttempt: (json['generationAttempt'] as num?)?.toInt() ?? 1,
      approvedByUserName: approvedByName,
      approvedAt: DateTime.tryParse('${json['approvedAt'] ?? ''}'),
      rejectedAt: DateTime.tryParse('${json['rejectedAt'] ?? ''}'),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
    );
  }
}

class MarketingDashboard {
  const MarketingDashboard({
    required this.flowStatus,
    required this.pendingApprovalCount,
    required this.approvedTodayCount,
    required this.lastGenerationAt,
    required this.nextSuggestedGeneration,
  });

  final String flowStatus;
  final int pendingApprovalCount;
  final int approvedTodayCount;
  final DateTime? lastGenerationAt;
  final DateTime? nextSuggestedGeneration;

  factory MarketingDashboard.fromJson(Map<String, dynamic> json) {
    return MarketingDashboard(
      flowStatus: '${json['flowStatus'] ?? 'INACTIVO'}',
      pendingApprovalCount:
          (json['pendingApprovalCount'] as num?)?.toInt() ?? 0,
      approvedTodayCount: (json['approvedTodayCount'] as num?)?.toInt() ?? 0,
      lastGenerationAt: DateTime.tryParse('${json['lastGenerationAt'] ?? ''}'),
      nextSuggestedGeneration: DateTime.tryParse(
        '${json['nextSuggestedGeneration'] ?? ''}',
      ),
    );
  }
}

class MarketingHistoryResponse {
  const MarketingHistoryResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<MarketingStory> items;
  final int total;
  final int page;
  final int limit;

  factory MarketingHistoryResponse.fromJson(Map<String, dynamic> json) {
    final rows = (json['items'] is List) ? (json['items'] as List) : const [];
    return MarketingHistoryResponse(
      items: rows
          .whereType<Map>()
          .map((item) => MarketingStory.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 20,
    );
  }
}
