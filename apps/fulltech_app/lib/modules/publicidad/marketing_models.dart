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

// ── Research models ──────────────────────────────────────────────────────────

enum MarketingResearchStatus { draft, approved, rejected, used }

MarketingResearchStatus parseResearchStatus(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  switch (normalized) {
    case 'APPROVED':
      return MarketingResearchStatus.approved;
    case 'REJECTED':
      return MarketingResearchStatus.rejected;
    case 'USED':
      return MarketingResearchStatus.used;
    case 'DRAFT':
    default:
      return MarketingResearchStatus.draft;
  }
}

String researchStatusLabel(MarketingResearchStatus s) {
  switch (s) {
    case MarketingResearchStatus.draft:
      return 'Borrador';
    case MarketingResearchStatus.approved:
      return 'Aprobada';
    case MarketingResearchStatus.rejected:
      return 'Rechazada';
    case MarketingResearchStatus.used:
      return 'Usada';
  }
}

class MarketingResearchConfig {
  const MarketingResearchConfig({
    required this.id,
    required this.defaultResearchPrompt,
    required this.businessName,
    required this.businessLocation,
    required this.businessDescription,
    required this.mainServices,
    required this.priorityServices,
    required this.targetMarket,
    required this.brandTone,
    required this.learningEnabled,
    required this.researchFrequencyDays,
    required this.requireApproval,
  });

  final String id;
  final String defaultResearchPrompt;
  final String businessName;
  final String businessLocation;
  final String businessDescription;
  final List<String> mainServices;
  final List<String> priorityServices;
  final String targetMarket;
  final String brandTone;
  final bool learningEnabled;
  final int researchFrequencyDays;
  final bool requireApproval;

  factory MarketingResearchConfig.fromJson(Map<String, dynamic> json) {
    return MarketingResearchConfig(
      id: '${json['id'] ?? ''}',
      defaultResearchPrompt: '${json['defaultResearchPrompt'] ?? ''}',
      businessName: '${json['businessName'] ?? 'FULLTECH SRL'}',
      businessLocation: '${json['businessLocation'] ?? 'Higüey, La Altagracia, República Dominicana'}',
      businessDescription: '${json['businessDescription'] ?? ''}',
      mainServices: _parseStringList(json['mainServices']),
      priorityServices: _parseStringList(json['priorityServices']),
      targetMarket: '${json['targetMarket'] ?? ''}',
      brandTone: '${json['brandTone'] ?? ''}',
      learningEnabled: json['learningEnabled'] == true,
      researchFrequencyDays: (json['researchFrequencyDays'] as num?)?.toInt() ?? 2,
      requireApproval: json['requireApproval'] == true,
    );
  }
}

List<String> _parseStringList(dynamic value) {
  if (value is List) {
    return value.map((item) => '$item'.trim()).where((item) => item.isNotEmpty).toList(growable: false);
  }
  class MarketingResearchConfig {
    const MarketingResearchConfig({
      required this.id,
      required this.defaultResearchPrompt,
      required this.businessName,
      required this.businessLocation,
  class MarketingDashboardResearch {
    const MarketingDashboardResearch({
      required this.id,
      required this.status,
      required this.date,
      required this.confidenceScore,
      required this.dataSources,
      required this.createdAt,
    });

    final String id;
    final String status;
    final DateTime date;
    final double confidenceScore;
    final List<String> dataSources;
    final DateTime? createdAt;

    factory MarketingDashboardResearch.fromJson(Map<String, dynamic> json) {
      return MarketingDashboardResearch(
        id: '${json['id'] ?? ''}',
        status: '${json['status'] ?? ''}',
        date: DateTime.tryParse('${json['date'] ?? ''}') ?? DateTime.now(),
        confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0.5,
        dataSources: _parseStringList(json['dataSources']),
        createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
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
      required this.latestResearch,
      required this.researchUsable,
      required this.nextAutoResearch,
      required this.researchFrequencyDays,
      required this.serviceRadiusKm,
      required this.serviceZone,
      required this.storiesFromCurrentResearch,
    });

    final String flowStatus;
    final int pendingApprovalCount;
    final int approvedTodayCount;
    final DateTime? lastGenerationAt;
    final DateTime? nextSuggestedGeneration;
    final MarketingDashboardResearch? latestResearch;
    final bool researchUsable;
    final DateTime? nextAutoResearch;
    final int researchFrequencyDays;
    final int serviceRadiusKm;
    final String serviceZone;
    final int storiesFromCurrentResearch;

    factory MarketingDashboard.fromJson(Map<String, dynamic> json) {
      final rawResearch = json['latestResearch'];
      return MarketingDashboard(
        flowStatus: '${json['flowStatus'] ?? 'INACTIVO'}',
        pendingApprovalCount: (json['pendingApprovalCount'] as num?)?.toInt() ?? 0,
        approvedTodayCount: (json['approvedTodayCount'] as num?)?.toInt() ?? 0,
        lastGenerationAt: DateTime.tryParse('${json['lastGenerationAt'] ?? ''}'),
        nextSuggestedGeneration: DateTime.tryParse('${json['nextSuggestedGeneration'] ?? ''}'),
        latestResearch: rawResearch is Map
            ? MarketingDashboardResearch.fromJson(rawResearch.cast<String, dynamic>())
            : null,
        researchUsable: json['researchUsable'] == true,
        nextAutoResearch: DateTime.tryParse('${json['nextAutoResearch'] ?? ''}'),
        researchFrequencyDays: (json['researchFrequencyDays'] as num?)?.toInt() ?? 2,
        serviceRadiusKm: (json['serviceRadiusKm'] as num?)?.toInt() ?? 25,
        serviceZone: '${json['serviceZone'] ?? 'Higüey, La Altagracia'}',
        storiesFromCurrentResearch: (json['storiesFromCurrentResearch'] as num?)?.toInt() ?? 0,
      );
    }
  }
    final List<String> priorityServices;
    final String targetMarket;
    final String brandTone;
    final bool learningEnabled;
    final int researchFrequencyDays;
    // New company profile fields
    final String phone;
    final String address;
    final String city;
    final String province;
    final String country;
    final double? latitude;
    final double? longitude;
    final int serviceRadiusKm;
    final List<String> serviceZones;
    final String defaultCTA;
    final List<String> brandColors;
    final String businessHours;
    final String internalNotes;

    factory MarketingResearchConfig.fromJson(Map<String, dynamic> json) {
      return MarketingResearchConfig(
        id: '${json['id'] ?? ''}',
        defaultResearchPrompt: '${json['defaultResearchPrompt'] ?? ''}',
        businessName: '${json['businessName'] ?? 'FULLTECH SRL'}',
        businessLocation: '${json['businessLocation'] ?? 'Higüey, La Altagracia, República Dominicana'}',
        businessDescription: '${json['businessDescription'] ?? ''}',
        mainServices: _parseStringList(json['mainServices']),
        priorityServices: _parseStringList(json['priorityServices']),
        targetMarket: '${json['targetMarket'] ?? ''}',
        brandTone: '${json['brandTone'] ?? ''}',
        learningEnabled: json['learningEnabled'] == true,
        researchFrequencyDays: (json['researchFrequencyDays'] as num?)?.toInt() ?? 2,
        phone: '${json['phone'] ?? ''}',
        address: '${json['address'] ?? ''}',
        city: '${json['city'] ?? 'Higüey'}',
        province: '${json['province'] ?? 'La Altagracia'}',
        country: '${json['country'] ?? 'República Dominicana'}',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        serviceRadiusKm: (json['serviceRadiusKm'] as num?)?.toInt() ?? 25,
        serviceZones: _parseStringList(json['serviceZones']),
        defaultCTA: '${json['defaultCTA'] ?? ''}',
        brandColors: _parseStringList(json['brandColors']),
        businessHours: '${json['businessHours'] ?? ''}',
        internalNotes: '${json['internalNotes'] ?? ''}',
      );
    }
  }
  final List<String> avoidThis;
  final double confidenceScore;
  final List<String> dataSources;
  final MarketingResearchStatus status;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;

  factory MarketingResearch.fromJson(Map<String, dynamic> json) {
    return MarketingResearch(
      id: '${json['id'] ?? ''}',
      date: DateTime.tryParse('${json['date'] ?? ''}') ?? DateTime.now(),
      researchPrompt: '${json['researchPrompt'] ?? ''}',
      marketSummary: '${json['marketSummary'] ?? ''}',
      competitorPublishingPatterns: '${json['competitorPublishingPatterns'] ?? ''}',
      commonOffers: '${json['commonOffers'] ?? ''}',
      observedPriceRanges: '${json['observedPriceRanges'] ?? ''}',
      strongAngles: _parseStringList(json['strongAngles']),
      weakAngles: _parseStringList(json['weakAngles']),
      contentOpportunities: '${json['contentOpportunities'] ?? ''}',
      recommendedProducts: _parseStringList(json['recommendedProducts']),
      recommendedContentTypes: _parseStringList(json['recommendedContentTypes']),
      recommendedOffers: _parseStringList(json['recommendedOffers']),
      recommendedHooks: _parseStringList(json['recommendedHooks']),
      recommendedCTAs: _parseStringList(json['recommendedCTAs']),
      doMoreOfThis: _parseStringList(json['doMoreOfThis']),
      avoidThis: _parseStringList(json['avoidThis']),
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0.5,
      dataSources: _parseStringList(json['dataSources']),
      status: parseResearchStatus('${json['status'] ?? ''}'),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      approvedAt: DateTime.tryParse('${json['approvedAt'] ?? ''}'),
      rejectedAt: DateTime.tryParse('${json['rejectedAt'] ?? ''}'),
    );
  }
}

class MarketingLearningStats {
  const MarketingLearningStats({
    required this.activeCount,
    required this.discardedCount,
    required this.topInsights,
  });

  final int activeCount;
  final int discardedCount;
  final List<String> topInsights;

  factory MarketingLearningStats.fromJson(Map<String, dynamic> json) {
    final raw = (json['topInsights'] as List?) ?? const [];
    return MarketingLearningStats(
      activeCount: (json['activeCount'] as num?)?.toInt() ?? 0,
      discardedCount: (json['discardedCount'] as num?)?.toInt() ?? 0,
      topInsights: raw
          .whereType<Map>()
          .map((item) => '${item['insight'] ?? ''}')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }
}
