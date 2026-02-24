class ServiceAssignmentModel {
  final String id;
  final String userId;
  final String role;
  final String userName;

  ServiceAssignmentModel({
    required this.id,
    required this.userId,
    required this.role,
    required this.userName,
  });

  factory ServiceAssignmentModel.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ServiceAssignmentModel(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      role: (json['role'] ?? 'assistant').toString(),
      userName: (user['nombreCompleto'] ?? user['email'] ?? 'Técnico').toString(),
    );
  }
}

class ServiceStepModel {
  final String id;
  final String stepKey;
  final String stepLabel;
  final bool isDone;
  final DateTime? doneAt;

  ServiceStepModel({
    required this.id,
    required this.stepKey,
    required this.stepLabel,
    required this.isDone,
    this.doneAt,
  });

  factory ServiceStepModel.fromJson(Map<String, dynamic> json) {
    return ServiceStepModel(
      id: (json['id'] ?? '').toString(),
      stepKey: (json['stepKey'] ?? '').toString(),
      stepLabel: (json['stepLabel'] ?? '').toString(),
      isDone: json['isDone'] == true,
      doneAt: json['doneAt'] == null ? null : DateTime.tryParse(json['doneAt'].toString()),
    );
  }
}

class ServiceFileModel {
  final String id;
  final String fileUrl;
  final String fileType;
  final DateTime? createdAt;

  ServiceFileModel({
    required this.id,
    required this.fileUrl,
    required this.fileType,
    this.createdAt,
  });

  factory ServiceFileModel.fromJson(Map<String, dynamic> json) {
    return ServiceFileModel(
      id: (json['id'] ?? '').toString(),
      fileUrl: (json['fileUrl'] ?? '').toString(),
      fileType: (json['fileType'] ?? '').toString(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
    );
  }
}

class ServiceUpdateModel {
  final String id;
  final String type;
  final String message;
  final String changedBy;
  final DateTime? createdAt;

  ServiceUpdateModel({
    required this.id,
    required this.type,
    required this.message,
    required this.changedBy,
    this.createdAt,
  });

  factory ServiceUpdateModel.fromJson(Map<String, dynamic> json) {
    final changedBy =
        (json['changedBy'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ServiceUpdateModel(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      changedBy: (changedBy['nombreCompleto'] ?? 'Sistema').toString(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
    );
  }
}

class ServiceModel {
  final String id;
  final String title;
  final String description;
  final String serviceType;
  final String category;
  final String status;
  final int priority;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? completedAt;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String createdByUserId;
  final String createdByName;
  final List<ServiceAssignmentModel> assignments;
  final List<ServiceStepModel> steps;
  final List<ServiceFileModel> files;
  final List<ServiceUpdateModel> updates;

  ServiceModel({
    required this.id,
    required this.title,
    required this.description,
    required this.serviceType,
    required this.category,
    required this.status,
    required this.priority,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.createdByUserId,
    required this.createdByName,
    required this.assignments,
    required this.steps,
    required this.files,
    required this.updates,
    this.scheduledStart,
    this.scheduledEnd,
    this.completedAt,
  });

  factory ServiceModel.fromJson(Map<String, dynamic> json) {
    final customer = (json['customer'] as Map?)?.cast<String, dynamic>() ?? const {};
    final createdBy = (json['createdBy'] as Map?)?.cast<String, dynamic>() ?? const {};

    List<T> parseList<T>(dynamic raw, T Function(Map<String, dynamic>) parser) {
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((item) => parser(item.cast<String, dynamic>()))
          .toList();
    }

    return ServiceModel(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      serviceType: (json['serviceType'] ?? 'other').toString(),
      category: (json['category'] ?? '').toString(),
      status: (json['status'] ?? 'reserved').toString(),
      priority: (json['priority'] is int)
          ? json['priority'] as int
          : int.tryParse('${json['priority']}') ?? 2,
      scheduledStart: json['scheduledStart'] == null
          ? null
          : DateTime.tryParse(json['scheduledStart'].toString()),
      scheduledEnd: json['scheduledEnd'] == null
          ? null
          : DateTime.tryParse(json['scheduledEnd'].toString()),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.tryParse(json['completedAt'].toString()),
      customerId: (customer['id'] ?? '').toString(),
      customerName: (customer['nombre'] ?? '').toString(),
      customerPhone: (customer['telefono'] ?? '').toString(),
      customerAddress: (json['addressSnapshot'] ?? customer['direccion'] ?? '').toString(),
      createdByUserId: (json['createdByUserId'] ?? '').toString(),
      createdByName: (createdBy['nombreCompleto'] ?? '').toString(),
      assignments: parseList(json['assignments'], ServiceAssignmentModel.fromJson),
      steps: parseList(json['steps'], ServiceStepModel.fromJson),
      files: parseList(json['files'], ServiceFileModel.fromJson),
      updates: parseList(json['updates'], ServiceUpdateModel.fromJson),
    );
  }
}

class OperationsDashboardModel {
  final int installationsPendingToday;
  final int warrantiesOpen;
  final double averageHoursByLifecycle;
  final Map<String, int> activeByStatus;
  final List<Map<String, dynamic>> technicianPerformance;

  OperationsDashboardModel({
    required this.installationsPendingToday,
    required this.warrantiesOpen,
    required this.averageHoursByLifecycle,
    required this.activeByStatus,
    required this.technicianPerformance,
  });

  factory OperationsDashboardModel.empty() => OperationsDashboardModel(
        installationsPendingToday: 0,
        warrantiesOpen: 0,
        averageHoursByLifecycle: 0,
        activeByStatus: const {},
        technicianPerformance: const [],
      );

  factory OperationsDashboardModel.fromJson(Map<String, dynamic> json) {
    final byStatusRaw = json['activeByStatus'];
    final byStatus = <String, int>{};
    if (byStatusRaw is List) {
      for (final row in byStatusRaw.whereType<Map>()) {
        final item = row.cast<String, dynamic>();
        byStatus[(item['status'] ?? '').toString()] =
            int.tryParse('${item['count']}') ?? 0;
      }
    }

    final perfRaw = json['technicianPerformance'];
    final perf = perfRaw is List
        ? perfRaw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : <Map<String, dynamic>>[];

    return OperationsDashboardModel(
      installationsPendingToday:
          int.tryParse('${json['installationsPendingToday']}') ?? 0,
      warrantiesOpen: int.tryParse('${json['warrantiesOpen']}') ?? 0,
      averageHoursByLifecycle:
          double.tryParse('${json['averageHoursByLifecycle']}') ?? 0,
      activeByStatus: byStatus,
      technicianPerformance: perf,
    );
  }
}

class ServicesPageModel {
  final List<ServiceModel> items;
  final int total;
  final int page;
  final int pageSize;

  ServicesPageModel({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory ServicesPageModel.fromJson(Map<String, dynamic> json) {
    final listRaw = json['items'];
    final items = listRaw is List
        ? listRaw
            .whereType<Map>()
            .map((row) => ServiceModel.fromJson(row.cast<String, dynamic>()))
            .toList()
        : <ServiceModel>[];

    return ServicesPageModel(
      items: items,
      total: int.tryParse('${json['total']}') ?? items.length,
      page: int.tryParse('${json['page']}') ?? 1,
      pageSize: int.tryParse('${json['pageSize']}') ?? 30,
    );
  }
}
