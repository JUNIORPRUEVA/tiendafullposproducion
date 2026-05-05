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

enum MarketingImageStatus {
  pending,
  pendingMedia,
  generated,
  generatedPlaceholder,
  failed,
}

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

MarketingImageStatus parseImageStatus(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  switch (normalized) {
    case 'PENDING_MEDIA':
      return MarketingImageStatus.pendingMedia;
    case 'GENERATED':
      return MarketingImageStatus.generated;
    case 'GENERATED_PLACEHOLDER':
      return MarketingImageStatus.generatedPlaceholder;
    case 'FAILED':
      return MarketingImageStatus.failed;
    case 'PENDING':
    default:
      return MarketingImageStatus.pending;
  }
}

class MarketingMediaAsset {
  const MarketingMediaAsset({
    required this.id,
    required this.fileUrl,
    required this.thumbnailUrl,
    required this.fileName,
    required this.mimeType,
    required this.category,
    required this.relatedService,
    required this.tags,
    required this.description,
    required this.isActive,
    required this.isFeatured,
    required this.useCount,
    required this.lastUsedAt,
  });

  final String id;
  final String fileUrl;
  final String? thumbnailUrl;
  final String fileName;
  final String mimeType;
  final String category;
  final String? relatedService;
  final List<String> tags;
  final String? description;
  final bool isActive;
  final bool isFeatured;
  final int useCount;
  final DateTime? lastUsedAt;

  factory MarketingMediaAsset.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return MarketingMediaAsset(
      id: '${json['id'] ?? ''}',
      fileUrl: '${json['fileUrl'] ?? ''}',
      thumbnailUrl: (json['thumbnailUrl'] ?? '').toString().trim().isEmpty
          ? null
          : '${json['thumbnailUrl']}',
      fileName: '${json['fileName'] ?? ''}',
      mimeType: '${json['mimeType'] ?? ''}',
      category: '${json['category'] ?? ''}',
      relatedService: (json['relatedService'] ?? '').toString().trim().isEmpty
          ? null
          : '${json['relatedService']}',
      tags: tags,
      description: (json['description'] ?? '').toString().trim().isEmpty
          ? null
          : '${json['description']}',
      isActive: json['isActive'] != false,
      isFeatured: json['isFeatured'] == true,
      useCount: (json['useCount'] as num?)?.toInt() ?? 0,
      lastUsedAt: DateTime.tryParse('${json['lastUsedAt'] ?? ''}'),
    );
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
    required this.researchId,
    required this.mediaAssetId,
    required this.visualConcept,
    required this.designNotes,
    required this.imageStatus,
    required this.generatedImageUrl,
    required this.generatedImageProvider,
    required this.usedResearchAngle,
    required this.usedOffer,
    required this.usedCTA,
    required this.mediaAsset,
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
  final String? researchId;
  final String? mediaAssetId;
  final String visualConcept;
  final String designNotes;
  final MarketingImageStatus imageStatus;
  final String generatedImageUrl;
  final String generatedImageProvider;
  final String usedResearchAngle;
  final String usedOffer;
  final String usedCTA;
  final MarketingMediaAsset? mediaAsset;

  int get regeneratedCount =>
      generationAttempt <= 1 ? 0 : generationAttempt - 1;

  factory MarketingStory.fromJson(Map<String, dynamic> json) {
    final approvedBy = json['approvedByUser'];
    final rawAsset = json['mediaAsset'];
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
      researchId: (json['researchId'] ?? '').toString().trim().isEmpty
          ? null
          : '${json['researchId']}',
      mediaAssetId: (json['mediaAssetId'] ?? '').toString().trim().isEmpty
          ? null
          : '${json['mediaAssetId']}',
      visualConcept: '${json['visualConcept'] ?? ''}',
      designNotes: '${json['designNotes'] ?? ''}',
      imageStatus: parseImageStatus('${json['imageStatus'] ?? ''}'),
      generatedImageUrl: '${json['generatedImageUrl'] ?? ''}',
      generatedImageProvider: '${json['generatedImageProvider'] ?? ''}',
      usedResearchAngle: '${json['usedResearchAngle'] ?? ''}',
      usedOffer: '${json['usedOffer'] ?? ''}',
      usedCTA: '${json['usedCTA'] ?? ''}',
      mediaAsset: rawAsset is Map
          ? MarketingMediaAsset.fromJson(rawAsset.cast<String, dynamic>())
          : null,
    );
  }
}

class MarketingDashboardResearch {
  const MarketingDashboardResearch({
    required this.id,
    required this.status,
    required this.confidenceScore,
    required this.createdAt,
  });

  final String id;
  final String status;
  final double confidenceScore;
  final DateTime? createdAt;

  factory MarketingDashboardResearch.fromJson(Map<String, dynamic> json) {
    return MarketingDashboardResearch(
      id: '${json['id'] ?? ''}',
      status: '${json['status'] ?? ''}',
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0,
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
    return MarketingDashboard(
      flowStatus: '${json['flowStatus'] ?? 'INACTIVO'}',
      pendingApprovalCount:
          (json['pendingApprovalCount'] as num?)?.toInt() ?? 0,
      approvedTodayCount: (json['approvedTodayCount'] as num?)?.toInt() ?? 0,
      lastGenerationAt: DateTime.tryParse('${json['lastGenerationAt'] ?? ''}'),
      nextSuggestedGeneration: DateTime.tryParse(
        '${json['nextSuggestedGeneration'] ?? ''}',
      ),
      latestResearch: json['latestResearch'] is Map
          ? MarketingDashboardResearch.fromJson(
              (json['latestResearch'] as Map).cast<String, dynamic>(),
            )
          : null,
      researchUsable: json['researchUsable'] == true,
      nextAutoResearch: DateTime.tryParse('${json['nextAutoResearch'] ?? ''}'),
      researchFrequencyDays:
          (json['researchFrequencyDays'] as num?)?.toInt() ?? 2,
      serviceRadiusKm: (json['serviceRadiusKm'] as num?)?.toInt() ?? 25,
      serviceZone: '${json['serviceZone'] ?? 'Higüey, La Altagracia'}',
      storiesFromCurrentResearch:
          (json['storiesFromCurrentResearch'] as num?)?.toInt() ?? 0,
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
