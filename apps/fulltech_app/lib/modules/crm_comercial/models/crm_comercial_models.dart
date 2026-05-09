class CrmComercialUserRef {
  const CrmComercialUserRef({
    required this.id,
    required this.nombreCompleto,
    this.role,
  });

  final String id;
  final String nombreCompleto;
  final String? role;

  factory CrmComercialUserRef.fromJson(Map<String, dynamic> json) {
    return CrmComercialUserRef(
      id: (json['id'] ?? '').toString(),
      nombreCompleto: (json['nombreCompleto'] ?? 'Sin nombre').toString(),
      role: json['role']?.toString(),
    );
  }
}

class CrmComercialStatusEntry {
  const CrmComercialStatusEntry({
    required this.id,
    required this.estadoNuevo,
    this.estadoAnterior,
    this.nota,
    this.createdAt,
    this.changedBy,
  });

  final String id;
  final String estadoNuevo;
  final String? estadoAnterior;
  final String? nota;
  final DateTime? createdAt;
  final CrmComercialUserRef? changedBy;

  factory CrmComercialStatusEntry.fromJson(Map<String, dynamic> json) {
    return CrmComercialStatusEntry(
      id: (json['id'] ?? '').toString(),
      estadoNuevo: (json['estadoNuevo'] ?? '').toString(),
      estadoAnterior: json['estadoAnterior']?.toString(),
      nota: json['nota']?.toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      changedBy: (json['changedByUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['changedByUser'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class CrmComercialNote {
  const CrmComercialNote({
    required this.id,
    required this.note,
    this.createdAt,
    this.author,
  });

  final String id;
  final String note;
  final DateTime? createdAt;
  final CrmComercialUserRef? author;

  factory CrmComercialNote.fromJson(Map<String, dynamic> json) {
    return CrmComercialNote(
      id: (json['id'] ?? '').toString(),
      note: (json['note'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      author: (json['authorUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['authorUser'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class CrmComercialActivity {
  const CrmComercialActivity({
    required this.id,
    required this.activityType,
    required this.description,
    this.dueAt,
    this.completedAt,
    this.createdAt,
    this.assignedTo,
    this.createdBy,
  });

  final String id;
  final String activityType;
  final String description;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final CrmComercialUserRef? assignedTo;
  final CrmComercialUserRef? createdBy;

  factory CrmComercialActivity.fromJson(Map<String, dynamic> json) {
    return CrmComercialActivity(
      id: (json['id'] ?? '').toString(),
      activityType: (json['activityType'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      dueAt: DateTime.tryParse((json['dueAt'] ?? '').toString()),
      completedAt: DateTime.tryParse((json['completedAt'] ?? '').toString()),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      assignedTo: (json['assignedToUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['assignedToUser'] as Map<String, dynamic>,
            )
          : null,
      createdBy: (json['createdByUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['createdByUser'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class CrmComercialCustomer {
  const CrmComercialCustomer({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.estadoActual,
    this.direccion,
    this.ciudad,
    this.etiqueta,
    this.nextAction,
    this.nextActionAt,
    this.updatedAt,
    this.responsable,
    this.statusHistory = const [],
    this.notes = const [],
    this.activities = const [],
  });

  final String id;
  final String nombre;
  final String telefono;
  final String estadoActual;
  final String? direccion;
  final String? ciudad;
  final String? etiqueta;
  final String? nextAction;
  final DateTime? nextActionAt;
  final DateTime? updatedAt;
  final CrmComercialUserRef? responsable;
  final List<CrmComercialStatusEntry> statusHistory;
  final List<CrmComercialNote> notes;
  final List<CrmComercialActivity> activities;

  factory CrmComercialCustomer.fromJson(Map<String, dynamic> json) {
    return CrmComercialCustomer(
      id: (json['id'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      telefono: (json['telefono'] ?? '').toString(),
      estadoActual: (json['estadoActual'] ?? '').toString(),
      direccion: json['direccion']?.toString(),
      ciudad: json['ciudad']?.toString(),
      etiqueta: json['etiqueta']?.toString(),
      nextAction: json['nextAction']?.toString(),
      nextActionAt: DateTime.tryParse((json['nextActionAt'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
      responsable: (json['responsableUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['responsableUser'] as Map<String, dynamic>,
            )
          : null,
      statusHistory: ((json['statusHistory'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialStatusEntry.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      notes: ((json['notes'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialNote.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      activities: ((json['activities'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialActivity.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class CrmComercialCustomerListResponse {
  const CrmComercialCustomerListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<CrmComercialCustomer> items;
  final int total;
  final int page;
  final int pageSize;

  factory CrmComercialCustomerListResponse.fromJson(Map<String, dynamic> json) {
    return CrmComercialCustomerListResponse(
      items: ((json['items'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialCustomer.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? 20,
    );
  }
}

class CrmComercialWhatsappInstance {
  const CrmComercialWhatsappInstance({
    required this.id,
    required this.instanceName,
    required this.status,
    required this.webhookEnabled,
    required this.isCompany,
    this.userId,
    this.userName,
    this.userRole,
    this.phoneNumber,
  });

  final String id;
  final String instanceName;
  final String status;
  final bool webhookEnabled;
  final bool isCompany;
  final String? userId;
  final String? userName;
  final String? userRole;
  final String? phoneNumber;

  factory CrmComercialWhatsappInstance.fromJson(Map<String, dynamic> json) {
    return CrmComercialWhatsappInstance(
      id: (json['id'] ?? '').toString(),
      instanceName: (json['instanceName'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString(),
      webhookEnabled: json['webhookEnabled'] == true,
      isCompany: json['isCompany'] == true,
      userId: json['userId']?.toString(),
      userName: json['userName']?.toString(),
      userRole: json['userRole']?.toString(),
      phoneNumber: json['phoneNumber']?.toString(),
    );
  }
}

class CrmComercialSettings {
  const CrmComercialSettings({
    required this.id,
    required this.enabled,
    this.selectedWhatsappInstanceId,
    this.selectedWhatsappInstanceName,
    this.updatedAt,
    this.selectedInstanceExists,
    this.warning,
    this.realMessagesReady,
  });

  final String id;
  final bool enabled;
  final String? selectedWhatsappInstanceId;
  final String? selectedWhatsappInstanceName;
  final DateTime? updatedAt;
  final bool? selectedInstanceExists;
  final String? warning;
  final bool? realMessagesReady;

  factory CrmComercialSettings.fromJson(Map<String, dynamic> json) {
    return CrmComercialSettings(
      id: (json['id'] ?? 'global').toString(),
      enabled: json['enabled'] == true,
      selectedWhatsappInstanceId:
          json['selectedWhatsappInstanceId']?.toString(),
      selectedWhatsappInstanceName:
          json['selectedWhatsappInstanceName']?.toString(),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
      selectedInstanceExists: json['selectedInstanceExists'] is bool
          ? json['selectedInstanceExists'] as bool
          : null,
      warning: json['warning']?.toString(),
      realMessagesReady: json['realMessagesReady'] is bool
          ? json['realMessagesReady'] as bool
          : null,
    );
  }
}

class CrmComercialInboxConversation {
  const CrmComercialInboxConversation({
    required this.id,
    required this.contactName,
    this.remotePhone,
    this.remoteJid,
    this.remoteAvatarUrl,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.lastMessageType,
    this.lastMessageDirection,
    this.unreadCount = 0,
    this.messageCount = 0,
    this.crmCustomerId,
    this.crmCustomerName,
    this.crmCustomerStatus,
    this.isNewContact = false,
    this.canConvertToCrm = false,
  });

  final String id;
  final String contactName;
  final String? remotePhone;
  final String? remoteJid;
  final String? remoteAvatarUrl;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final String? lastMessageType;
  final String? lastMessageDirection;
  final int unreadCount;
  final int messageCount;
  final String? crmCustomerId;
  final String? crmCustomerName;
  final String? crmCustomerStatus;
  final bool isNewContact;
  final bool canConvertToCrm;

  bool get isOutgoingLastMessage =>
      (lastMessageDirection ?? '').toUpperCase() == 'OUTGOING';

  factory CrmComercialInboxConversation.fromJson(Map<String, dynamic> json) {
    return CrmComercialInboxConversation(
      id: (json['id'] ?? '').toString(),
      contactName: (json['contactName'] ?? 'Nuevo contacto').toString(),
      remotePhone: json['remotePhone']?.toString(),
      remoteJid: json['remoteJid']?.toString(),
      remoteAvatarUrl: json['remoteAvatarUrl']?.toString(),
      lastMessageAt: DateTime.tryParse((json['lastMessageAt'] ?? '').toString()),
      lastMessagePreview: json['lastMessagePreview']?.toString(),
      lastMessageType: json['lastMessageType']?.toString(),
      lastMessageDirection: json['lastMessageDirection']?.toString(),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      crmCustomerId: json['crmCustomerId']?.toString(),
      crmCustomerName: json['crmCustomerName']?.toString(),
      crmCustomerStatus: json['crmCustomerStatus']?.toString(),
      isNewContact: json['isNewContact'] == true,
      canConvertToCrm: json['canConvertToCrm'] == true,
    );
  }
}

class CrmComercialInboxMessage {
  const CrmComercialInboxMessage({
    required this.id,
    required this.direction,
    required this.messageType,
    this.body,
    this.caption,
    this.mediaUrl,
    this.mediaMimeType,
    this.senderName,
    this.sentAt,
    this.mediaStorageKey,
    this.mediaStatus,
    this.originalFileName,
    this.mediaFileSize,
  });

  final String id;
  final String direction;
  final String messageType;
  final String? body;
  final String? caption;
  final String? mediaUrl;
  final String? mediaMimeType;
  final String? senderName;
  final DateTime? sentAt;
  final String? mediaStorageKey;
  final String? mediaStatus;
  final String? originalFileName;
  final int? mediaFileSize;

  bool get isOutgoing => direction.toUpperCase() == 'OUTGOING';
  bool get mediaFailed => (mediaStatus ?? '').toLowerCase() == 'failed';

  String get displayText {
    final main = (body ?? '').trim();
    if (main.isNotEmpty) return main;
    final alt = (caption ?? '').trim();
    if (alt.isNotEmpty) return alt;
    return '[${messageType.toLowerCase()}]';
  }

  factory CrmComercialInboxMessage.fromJson(Map<String, dynamic> json) {
    return CrmComercialInboxMessage(
      id: (json['id'] ?? '').toString(),
      direction: (json['direction'] ?? 'INCOMING').toString(),
      messageType: (json['messageType'] ?? 'TEXT').toString(),
      body: json['body']?.toString(),
      caption: json['caption']?.toString(),
      mediaUrl: json['mediaUrl']?.toString(),
      mediaMimeType: json['mediaMimeType']?.toString(),
      senderName: json['senderName']?.toString(),
      sentAt: DateTime.tryParse((json['sentAt'] ?? '').toString()),
      mediaStorageKey: json['mediaStorageKey']?.toString(),
      mediaStatus: json['mediaStatus']?.toString(),
      originalFileName: json['originalFileName']?.toString(),
      mediaFileSize: json['mediaFileSize'] is int ? json['mediaFileSize'] as int : null,
    );
  }
}

class CrmComercialInboxConversationListResponse {
  const CrmComercialInboxConversationListResponse({
    required this.items,
    this.warning,
  });

  final List<CrmComercialInboxConversation> items;
  final String? warning;

  factory CrmComercialInboxConversationListResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return CrmComercialInboxConversationListResponse(
      items: ((json['items'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) =>
              CrmComercialInboxConversation.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      warning: json['warning']?.toString(),
    );
  }
}

class CrmComercialInboxMessageListResponse {
  const CrmComercialInboxMessageListResponse({
    required this.items,
    this.conversation,
    this.warning,
  });

  final List<CrmComercialInboxMessage> items;
  final CrmComercialInboxConversation? conversation;
  final String? warning;

  factory CrmComercialInboxMessageListResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final conversationJson = json['conversation'];
    return CrmComercialInboxMessageListResponse(
      items: ((json['items'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map(
            (entry) =>
                CrmComercialInboxMessage.fromJson(entry.cast<String, dynamic>()),
          )
          .toList(growable: false),
      conversation: conversationJson is Map<String, dynamic>
          ? CrmComercialInboxConversation.fromJson(conversationJson)
          : null,
      warning: json['warning']?.toString(),
    );
  }
}

class CrmComercialAiReplySuggestion {
  const CrmComercialAiReplySuggestion({
    required this.intent,
    required this.suggestedReply,
    required this.nextAction,
    required this.missingData,
    required this.confidence,
    required this.dataUsed,
  });

  final String intent;
  final String suggestedReply;
  final String nextAction;
  final List<String> missingData;
  final double confidence;
  final List<String> dataUsed;

  factory CrmComercialAiReplySuggestion.fromJson(Map<String, dynamic> json) {
    return CrmComercialAiReplySuggestion(
      intent: (json['intent'] ?? '').toString(),
      suggestedReply: (json['suggestedReply'] ?? '').toString(),
      nextAction: (json['nextAction'] ?? '').toString(),
      missingData: ((json['missingData'] as List<dynamic>?) ?? const [])
          .map((entry) => entry.toString())
          .where((entry) => entry.trim().isNotEmpty)
          .toList(growable: false),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      dataUsed: ((json['dataUsed'] as List<dynamic>?) ?? const [])
          .map((entry) => entry.toString())
          .where((entry) => entry.trim().isNotEmpty)
          .toList(growable: false),
    );
  }
}

class CrmComercialFollowupTask {
    const CrmComercialFollowupTask({
      required this.id,
      required this.customerId,
      required this.title,
      required this.status,
      required this.effectiveStatus,
      required this.priority,
      this.description,
      this.dueDate,
      this.completedAt,
      this.createdAt,
      this.assignedTo,
      this.createdBy,
      this.completedBy,
    });

    final String id;
    final String customerId;
    final String title;
    final String status;
    final String effectiveStatus;
    final String priority;
    final String? description;
    final DateTime? dueDate;
    final DateTime? completedAt;
    final DateTime? createdAt;
    final CrmComercialUserRef? assignedTo;
    final CrmComercialUserRef? createdBy;
    final CrmComercialUserRef? completedBy;

    bool get isPending => effectiveStatus == 'PENDIENTE';
    bool get isOverdue => effectiveStatus == 'VENCIDA';
    bool get isCompleted => status == 'COMPLETADA';
    bool get isCancelled => status == 'CANCELADA';
    bool get isActive => status == 'PENDIENTE';

    factory CrmComercialFollowupTask.fromJson(Map<String, dynamic> json) {
      return CrmComercialFollowupTask(
        id: (json['id'] ?? '').toString(),
        customerId: (json['customerId'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        status: (json['status'] ?? 'PENDIENTE').toString(),
        effectiveStatus:
            (json['effectiveStatus'] ?? json['status'] ?? 'PENDIENTE').toString(),
        priority: (json['priority'] ?? 'NORMAL').toString(),
        description: json['description']?.toString(),
        dueDate: DateTime.tryParse((json['dueDate'] ?? '').toString()),
        completedAt: DateTime.tryParse((json['completedAt'] ?? '').toString()),
        createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
        assignedTo: (json['assignedUser'] is Map<String, dynamic>)
            ? CrmComercialUserRef.fromJson(
                json['assignedUser'] as Map<String, dynamic>)
            : null,
        createdBy: (json['createdByUser'] is Map<String, dynamic>)
            ? CrmComercialUserRef.fromJson(
                json['createdByUser'] as Map<String, dynamic>)
            : null,
        completedBy: (json['completedByUser'] is Map<String, dynamic>)
            ? CrmComercialUserRef.fromJson(
                json['completedByUser'] as Map<String, dynamic>)
            : null,
      );
    }
  }
