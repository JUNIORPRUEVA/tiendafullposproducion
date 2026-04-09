class ServiceOrderCommissionsRange {
  final String from;
  final String to;
  final String label;

  const ServiceOrderCommissionsRange({
    required this.from,
    required this.to,
    required this.label,
  });

  factory ServiceOrderCommissionsRange.fromJson(Map<String, dynamic> json) {
    return ServiceOrderCommissionsRange(
      from: (json['from'] ?? '').toString(),
      to: (json['to'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
    );
  }
}

class ServiceOrderCommissionsSummary {
  final int totalServices;
  final double totalSold;
  final double averageSold;
  final double sellerCommissionTotal;
  final double technicianCommissionTotal;
  final double visibleCommissionTotal;
  final double totalCommission;

  const ServiceOrderCommissionsSummary({
    required this.totalServices,
    required this.totalSold,
    required this.averageSold,
    required this.sellerCommissionTotal,
    required this.technicianCommissionTotal,
    required this.visibleCommissionTotal,
    required this.totalCommission,
  });

  const ServiceOrderCommissionsSummary.empty()
    : totalServices = 0,
      totalSold = 0,
      averageSold = 0,
      sellerCommissionTotal = 0,
      technicianCommissionTotal = 0,
      visibleCommissionTotal = 0,
      totalCommission = 0;

  factory ServiceOrderCommissionsSummary.fromJson(Map<String, dynamic> json) {
    double toDouble(Object? value) => (value as num?)?.toDouble() ?? 0;

    return ServiceOrderCommissionsSummary(
      totalServices: (json['totalServices'] as num?)?.toInt() ?? 0,
      totalSold: toDouble(json['totalSold']),
      averageSold: toDouble(json['averageSold']),
      sellerCommissionTotal: toDouble(json['sellerCommissionTotal']),
      technicianCommissionTotal: toDouble(json['technicianCommissionTotal']),
      visibleCommissionTotal: toDouble(json['visibleCommissionTotal']),
      totalCommission: toDouble(json['totalCommission']),
    );
  }
}

class ServiceOrderCommissionsPagination {
  final int page;
  final int pageSize;
  final int totalItems;
  final int totalPages;
  final bool hasMore;

  const ServiceOrderCommissionsPagination({
    required this.page,
    required this.pageSize,
    required this.totalItems,
    required this.totalPages,
    required this.hasMore,
  });

  const ServiceOrderCommissionsPagination.empty()
    : page = 1,
      pageSize = 25,
      totalItems = 0,
      totalPages = 1,
      hasMore = false;

  factory ServiceOrderCommissionsPagination.fromJson(
    Map<String, dynamic> json,
  ) {
    return ServiceOrderCommissionsPagination(
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? 25,
      totalItems: (json['totalItems'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      hasMore: json['hasMore'] == true,
    );
  }
}

class ServiceOrderCommissionItem {
  final String id;
  final String clientId;
  final String clientName;
  final String quotationId;
  final String createdById;
  final String createdByName;
  final String? technicianId;
  final String? technicianName;
  final String serviceType;
  final String status;
  final DateTime? finalizedAt;
  final double totalAmount;
  final double sellerCommissionAmount;
  final double technicianCommissionAmount;
  final double visibleCommissionAmount;
  final double totalCommissionAmount;

  const ServiceOrderCommissionItem({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.quotationId,
    required this.createdById,
    required this.createdByName,
    required this.technicianId,
    required this.technicianName,
    required this.serviceType,
    required this.status,
    required this.finalizedAt,
    required this.totalAmount,
    required this.sellerCommissionAmount,
    required this.technicianCommissionAmount,
    required this.visibleCommissionAmount,
    required this.totalCommissionAmount,
  });

  factory ServiceOrderCommissionItem.fromJson(Map<String, dynamic> json) {
    double toDouble(Object? value) => (value as num?)?.toDouble() ?? 0;

    return ServiceOrderCommissionItem(
      id: (json['id'] ?? '').toString(),
      clientId: (json['clientId'] ?? '').toString(),
      clientName: (json['clientName'] ?? '').toString(),
      quotationId: (json['quotationId'] ?? '').toString(),
      createdById: (json['createdById'] ?? '').toString(),
      createdByName: (json['createdByName'] ?? '').toString(),
      technicianId: json['technicianId']?.toString(),
      technicianName: json['technicianName']?.toString(),
      serviceType: (json['serviceType'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      finalizedAt: json['finalizedAt'] != null
          ? DateTime.tryParse(json['finalizedAt'].toString())
          : null,
      totalAmount: toDouble(json['totalAmount']),
      sellerCommissionAmount: toDouble(json['sellerCommissionAmount']),
      technicianCommissionAmount: toDouble(json['technicianCommissionAmount']),
      visibleCommissionAmount: toDouble(json['visibleCommissionAmount']),
      totalCommissionAmount: toDouble(json['totalCommissionAmount']),
    );
  }
}

class ServiceOrderCommissionsResponse {
  final String period;
  final ServiceOrderCommissionsRange range;
  final ServiceOrderCommissionsSummary summary;
  final ServiceOrderCommissionsPagination pagination;
  final List<ServiceOrderCommissionItem> items;

  const ServiceOrderCommissionsResponse({
    required this.period,
    required this.range,
    required this.summary,
    required this.pagination,
    required this.items,
  });

  factory ServiceOrderCommissionsResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ServiceOrderCommissionsResponse(
      period: (json['period'] ?? 'current').toString(),
      range: ServiceOrderCommissionsRange.fromJson(
        ((json['range'] as Map?) ?? const <String, dynamic>{})
            .cast<String, dynamic>(),
      ),
      summary: ServiceOrderCommissionsSummary.fromJson(
        ((json['summary'] as Map?) ?? const <String, dynamic>{})
            .cast<String, dynamic>(),
      ),
      pagination: ServiceOrderCommissionsPagination.fromJson(
        ((json['pagination'] as Map?) ?? const <String, dynamic>{})
            .cast<String, dynamic>(),
      ),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => ServiceOrderCommissionItem.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const <ServiceOrderCommissionItem>[],
    );
  }
}
