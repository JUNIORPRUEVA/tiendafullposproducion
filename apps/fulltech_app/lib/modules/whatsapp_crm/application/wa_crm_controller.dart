import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/wa_crm_repository.dart';
import '../models/wa_crm_conversation.dart';
import '../models/wa_crm_message.dart';

// ─── CRM Instance Entry (for webhook management panel) ────────────────────

class WaCrmInstanceEntry {
  const WaCrmInstanceEntry({
    required this.id,
    required this.instanceName,
    required this.status,
    required this.webhookEnabled,
    required this.isCompany,
    required this.userName,
    this.userId,
    this.userRole,
    this.phoneNumber,
  });

  final String id;
  final String instanceName;
  final String status;
  final bool webhookEnabled;
  final bool isCompany;
  final String userName;
  final String? userId;
  final String? userRole;
  final String? phoneNumber;

  factory WaCrmInstanceEntry.fromJson(Map<String, dynamic> json) {
    return WaCrmInstanceEntry(
      id: sanitizeWaText(json['id']) ?? '',
      instanceName: sanitizeWaText(json['instanceName']) ?? '',
      status: sanitizeWaText(json['status']) ?? 'pending',
      webhookEnabled: json['webhookEnabled'] as bool? ?? false,
      isCompany: json['isCompany'] as bool? ?? false,
      userName: sanitizeWaText(json['userName']) ?? 'Sin nombre',
      userId: sanitizeWaText(json['userId']),
      userRole: sanitizeWaText(json['userRole']),
      phoneNumber: sanitizeWaText(json['phoneNumber']),
    );
  }

  WaCrmInstanceEntry copyWithWebhook(bool enabled) => WaCrmInstanceEntry(
    id: id,
    instanceName: instanceName,
    status: status,
    webhookEnabled: enabled,
    isCompany: isCompany,
    userName: userName,
    userId: userId,
    userRole: userRole,
    phoneNumber: phoneNumber,
  );
}

// ─── User selector ────────────────────────────────────────────────────────

class WaCrmAiAlert {
  const WaCrmAiAlert({
    required this.type,
    required this.severity,
    required this.contact,
    required this.description,
  });

  final String
  type; // fraud | misconduct | no_response | angry_customer | spelling | unanswered
  final String severity; // high | medium | low
  final String contact;
  final String description;

  factory WaCrmAiAlert.fromJson(Map<String, dynamic> json) {
    return WaCrmAiAlert(
      type: sanitizeWaText(json['type']) ?? 'unknown',
      severity: sanitizeWaText(json['severity']) ?? 'low',
      contact: sanitizeWaText(json['contact']) ?? '',
      description: sanitizeWaText(json['description']) ?? '',
    );
  }
}

class WaCrmConversationAnalysis {
  const WaCrmConversationAnalysis({
    required this.contact,
    required this.messageCount,
    required this.status,
    required this.issues,
    required this.summary,
  });

  final String contact;
  final int messageCount;
  final String
  status; // interested | not_interested | angry | no_response | closed | pending
  final List<String> issues;
  final String summary;

  factory WaCrmConversationAnalysis.fromJson(Map<String, dynamic> json) {
    return WaCrmConversationAnalysis(
      contact: sanitizeWaText(json['contact']) ?? '',
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      status: sanitizeWaText(json['status']) ?? 'pending',
      issues:
          (json['issues'] as List<dynamic>?)
              ?.map((e) => sanitizeWaText(e) ?? '')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      summary: sanitizeWaText(json['summary']) ?? '',
    );
  }
}

class WaCrmExecutiveAiReport {
  const WaCrmExecutiveAiReport({
    required this.estadoGeneral,
    required this.resumenEjecutivo,
    required this.totalConversacionesAnalizadas,
    required this.totalMensajesAnalizados,
    required this.casosNormales,
    required this.casosConAlerta,
    required this.casosCriticos,
    required this.posiblesFraudesDetectados,
    required this.clientesSinRespuesta,
    required this.recomendacionesConcretas,
    required this.conversacionesProblematicas,
    this.responsabilidadDetectada = const [],
  });

  final String estadoGeneral;
  final String resumenEjecutivo;
  final int totalConversacionesAnalizadas;
  final int totalMensajesAnalizados;
  final int casosNormales;
  final int casosConAlerta;
  final int casosCriticos;
  final int posiblesFraudesDetectados;
  final int clientesSinRespuesta;
  final List<String> recomendacionesConcretas;
  final List<Map<String, dynamic>> conversacionesProblematicas;
  final List<Map<String, dynamic>> responsabilidadDetectada;

  factory WaCrmExecutiveAiReport.fromJson(Map<String, dynamic> json) {
    return WaCrmExecutiveAiReport(
      estadoGeneral: sanitizeWaText(json['estadoGeneral']) ?? 'Normal',
      resumenEjecutivo: sanitizeWaText(json['resumenEjecutivo']) ?? '',
      totalConversacionesAnalizadas:
          (json['totalConversacionesAnalizadas'] as num?)?.toInt() ?? 0,
      totalMensajesAnalizados:
          (json['totalMensajesAnalizados'] as num?)?.toInt() ?? 0,
      casosNormales: (json['casosNormales'] as num?)?.toInt() ?? 0,
      casosConAlerta: (json['casosConAlerta'] as num?)?.toInt() ?? 0,
      casosCriticos: (json['casosCriticos'] as num?)?.toInt() ?? 0,
      posiblesFraudesDetectados:
          (json['posiblesFraudesDetectados'] as num?)?.toInt() ?? 0,
      clientesSinRespuesta:
          (json['clientesSinRespuesta'] as num?)?.toInt() ?? 0,
      recomendacionesConcretas:
          (json['recomendacionesConcretas'] as List<dynamic>?)
              ?.map((e) => sanitizeWaText(e) ?? '')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      conversacionesProblematicas:
          (json['conversacionesProblematicas'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList() ??
          const [],
      responsabilidadDetectada:
          (json['responsabilidadDetectada'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList() ??
          const [],
    );
  }

  String toPlainText() {
    final lines = <String>[
      'Estado general: $estadoGeneral',
      '',
      'Resumen ejecutivo:',
      resumenEjecutivo,
      '',
      'Total conversaciones analizadas: $totalConversacionesAnalizadas',
      'Total mensajes analizados: $totalMensajesAnalizados',
      'Casos normales: $casosNormales',
      'Casos con alerta: $casosConAlerta',
      'Casos críticos: $casosCriticos',
      'Posibles fraudes detectados: $posiblesFraudesDetectados',
      'Clientes sin respuesta: $clientesSinRespuesta',
      '',
      'Recomendaciones:',
      ...recomendacionesConcretas.map((item) => '- $item'),
    ];
    if (conversacionesProblematicas.isNotEmpty) {
      lines.addAll(['', 'Conversaciones problemáticas:']);
      for (final item in conversacionesProblematicas) {
        lines.add(
          '- ${sanitizeWaText(item['contacto']) ?? 'Sin contacto'} | ${sanitizeWaText(item['prioridad']) ?? 'prioridad N/A'} | ${sanitizeWaText(item['motivo']) ?? 'No hay evidencia suficiente'} | Acción: ${sanitizeWaText(item['accionRecomendada']) ?? 'Revisar'}',
        );
      }
    }
    if (responsabilidadDetectada.isNotEmpty) {
      lines.addAll(['', 'Responsabilidad detectada:']);
      for (final item in responsabilidadDetectada) {
        lines.add(
          '- ${sanitizeWaText(item['cliente']) ?? 'Cliente no identificado'} | ${sanitizeWaText(item['atendidoPor']) ?? 'Atendido por N/A'} | ${sanitizeWaText(item['estado']) ?? 'No hay evidencia suficiente'} | ${sanitizeWaText(item['evidencia']) ?? 'No hay evidencia suficiente'}',
        );
      }
    }
    return lines.join('\n');
  }
}

class WaCrmAiQuestionAnswer {
  const WaCrmAiQuestionAnswer({
    required this.question,
    required this.answer,
    required this.generatedAt,
  });

  final String question;
  final String answer;
  final DateTime generatedAt;
}

class WaCrmDailyAiSummary {
  const WaCrmDailyAiSummary({
    required this.source,
    required this.summary,
    required this.stats,
    this.alerts = const [],
    this.conversationAnalysis = const [],
    this.report,
    this.cached = false,
    this.generatedAt,
    this.analysisReportId,
    this.dateRange = const {},
  });

  final String source;
  final String summary;
  final Map<String, dynamic> stats;
  final List<WaCrmAiAlert> alerts;
  final List<WaCrmConversationAnalysis> conversationAnalysis;
  final WaCrmExecutiveAiReport? report;
  final bool cached;
  final String? generatedAt;
  final String? analysisReportId;
  final Map<String, dynamic> dateRange;

  factory WaCrmDailyAiSummary.fromJson(Map<String, dynamic> json) {
    return WaCrmDailyAiSummary(
      source: sanitizeWaText(json['source']) ?? 'rules-only',
      summary: sanitizeWaText(json['summary']) ?? '',
      stats: (json['stats'] as Map?)?.cast<String, dynamic>() ?? const {},
      alerts:
          (json['alerts'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(WaCrmAiAlert.fromJson)
              .toList() ??
          const [],
      conversationAnalysis:
          (json['conversationAnalysis'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(WaCrmConversationAnalysis.fromJson)
              .toList() ??
          const [],
      report: (json['report'] as Map?) == null
          ? null
          : WaCrmExecutiveAiReport.fromJson(
              (json['report'] as Map).cast<String, dynamic>(),
            ),
      cached: json['cached'] == true,
      generatedAt: sanitizeWaText(json['generatedAt']),
      analysisReportId: sanitizeWaText(json['analysisReportId']),
      dateRange:
          (json['dateRange'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

enum WaCrmMessageDateFilter {
  all,
  today,
  yesterday,
  last7Days,
  thisMonth,
  custom,
}

enum WaCrmAiAnalysisScope { conversation, filter }

class WaCrmUser {
  const WaCrmUser({
    required this.id,
    required this.name,
    required this.role,
    this.instanceId,
    this.instanceStatus,
    this.phone,
  });

  final String id;
  final String name;
  final String role;
  final String? instanceId;
  final String? instanceStatus;
  final String? phone;

  factory WaCrmUser.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return WaCrmUser(
      id: sanitizeWaText(user?['id'] ?? json['id']) ?? '',
      name: sanitizeWaText(user?['nombreCompleto']) ?? 'Sin nombre',
      role: sanitizeWaText(user?['role']) ?? '',
      instanceId: sanitizeWaText(json['id']),
      instanceStatus: sanitizeWaText(json['status']),
      phone: sanitizeWaText(json['phoneNumber'] ?? json['phone_number']),
    );
  }
}

// ─── State ────────────────────────────────────────────────────────────────

class WaCrmState {
  const WaCrmState({
    this.users = const [],
    this.loadingUsers = false,
    this.selectedUser,
    this.conversations = const [],
    this.loadingConversations = false,
    this.selectedConversation,
    this.messages = const [],
    this.loadingMessages = false,
    this.sending = false,
    this.composerUnlocked = false,
    this.composerUnlockedConversationKey,
    this.error,
    this.allInstances = const [],
    this.loadingInstances = false,
    this.aiSummary,
    this.loadingAiSummary = false,
    this.aiSummaryError,
    this.aiSummaryDate,
    this.aiAnalysisScope = WaCrmAiAnalysisScope.filter,
    this.aiQuestionHistory = const [],
    this.askingAiQuestion = false,
    this.messageDateFilter = WaCrmMessageDateFilter.all,
    this.customMessageDate,
    this.highlightedConversationIds = const <String>{},
    this.syncingInBackground = false,
    this.isOffline = false,
  });

  final List<WaCrmUser> users;
  final bool loadingUsers;
  final WaCrmUser? selectedUser;
  final List<WaCrmConversation> conversations;
  final bool loadingConversations;
  final WaCrmConversation? selectedConversation;
  final List<WaCrmMessage> messages;
  final bool loadingMessages;
  final bool sending;
  final bool composerUnlocked;
  final String? composerUnlockedConversationKey;
  final String? error;
  final List<WaCrmInstanceEntry> allInstances;
  final bool loadingInstances;
  final WaCrmDailyAiSummary? aiSummary;
  final bool loadingAiSummary;
  final String? aiSummaryError;
  final DateTime? aiSummaryDate;
  final WaCrmAiAnalysisScope aiAnalysisScope;
  final List<WaCrmAiQuestionAnswer> aiQuestionHistory;
  final bool askingAiQuestion;
  final WaCrmMessageDateFilter messageDateFilter;
  final DateTime? customMessageDate;
  final Set<String> highlightedConversationIds;
  final bool syncingInBackground;
  final bool isOffline;

  WaCrmState copyWith({
    List<WaCrmUser>? users,
    bool? loadingUsers,
    WaCrmUser? Function()? selectedUser,
    List<WaCrmConversation>? conversations,
    bool? loadingConversations,
    WaCrmConversation? Function()? selectedConversation,
    List<WaCrmMessage>? messages,
    bool? loadingMessages,
    bool? sending,
    bool? composerUnlocked,
    String? Function()? composerUnlockedConversationKey,
    String? Function()? error,
    List<WaCrmInstanceEntry>? allInstances,
    bool? loadingInstances,
    WaCrmDailyAiSummary? Function()? aiSummary,
    bool? loadingAiSummary,
    String? Function()? aiSummaryError,
    DateTime? Function()? aiSummaryDate,
    WaCrmAiAnalysisScope? aiAnalysisScope,
    List<WaCrmAiQuestionAnswer>? aiQuestionHistory,
    bool? askingAiQuestion,
    WaCrmMessageDateFilter? messageDateFilter,
    DateTime? Function()? customMessageDate,
    Set<String>? highlightedConversationIds,
    bool? syncingInBackground,
    bool? isOffline,
  }) {
    return WaCrmState(
      users: users ?? this.users,
      loadingUsers: loadingUsers ?? this.loadingUsers,
      selectedUser: selectedUser != null ? selectedUser() : this.selectedUser,
      conversations: conversations ?? this.conversations,
      loadingConversations: loadingConversations ?? this.loadingConversations,
      selectedConversation: selectedConversation != null
          ? selectedConversation()
          : this.selectedConversation,
      messages: messages ?? this.messages,
      loadingMessages: loadingMessages ?? this.loadingMessages,
      sending: sending ?? this.sending,
      composerUnlocked: composerUnlocked ?? this.composerUnlocked,
      composerUnlockedConversationKey: composerUnlockedConversationKey != null
          ? composerUnlockedConversationKey()
          : this.composerUnlockedConversationKey,
      error: error != null ? error() : this.error,
      allInstances: allInstances ?? this.allInstances,
      loadingInstances: loadingInstances ?? this.loadingInstances,
      aiSummary: aiSummary != null ? aiSummary() : this.aiSummary,
      loadingAiSummary: loadingAiSummary ?? this.loadingAiSummary,
      aiSummaryError: aiSummaryError != null
          ? aiSummaryError()
          : this.aiSummaryError,
      aiSummaryDate: aiSummaryDate != null
          ? aiSummaryDate()
          : this.aiSummaryDate,
      aiAnalysisScope: aiAnalysisScope ?? this.aiAnalysisScope,
      aiQuestionHistory: aiQuestionHistory ?? this.aiQuestionHistory,
      askingAiQuestion: askingAiQuestion ?? this.askingAiQuestion,
      messageDateFilter: messageDateFilter ?? this.messageDateFilter,
      customMessageDate: customMessageDate != null
          ? customMessageDate()
          : this.customMessageDate,
      highlightedConversationIds:
          highlightedConversationIds ?? this.highlightedConversationIds,
      syncingInBackground: syncingInBackground ?? this.syncingInBackground,
      isOffline: isOffline ?? this.isOffline,
    );
  }
}

// ─── Controller ──────────────────────────────────────────────────────────

final waCrmControllerProvider =
    StateNotifierProvider<WaCrmController, WaCrmState>((ref) {
      return WaCrmController(ref.watch(waCrmRepositoryProvider));
    });

class WaCrmController extends StateNotifier<WaCrmState> {
  WaCrmController(this._repo) : super(const WaCrmState());

  final WaCrmRepository _repo;
  bool _autoSyncedWebhookEvents = false;
  final Map<String, Timer> _highlightTimers = {};

  @override
  void dispose() {
    for (final timer in _highlightTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  // ─── Clear selection (mobile back) ──────────────────────────────────

  void clearSelection() {
    state = state.copyWith(selectedConversation: () => null, messages: []);
  }

  void setMessageDateFilter(
    WaCrmMessageDateFilter filter, {
    DateTime? customDate,
  }) {
    state = state.copyWith(
      messageDateFilter: filter,
      customMessageDate: () => customDate,
    );
  }

  void clearMessageDateFilter() {
    state = state.copyWith(
      messageDateFilter: WaCrmMessageDateFilter.all,
      customMessageDate: () => null,
    );
  }

  void _pulseConversation(String conversationId) {
    final current = {...state.highlightedConversationIds, conversationId};
    state = state.copyWith(highlightedConversationIds: current);
    _highlightTimers[conversationId]?.cancel();
    _highlightTimers[conversationId] = Timer(const Duration(seconds: 4), () {
      final updated = {...state.highlightedConversationIds}
        ..remove(conversationId);
      state = state.copyWith(highlightedConversationIds: updated);
      _highlightTimers.remove(conversationId);
    });
  }

  List<WaCrmConversation> _sortConversations(
    List<WaCrmConversation> conversations,
  ) {
    final sorted = [...conversations];
    sorted.sort((a, b) {
      final timeCompare = b.activityAt.compareTo(a.activityAt);
      if (timeCompare != 0) return timeCompare;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return sorted;
  }

  // ─── Load all instances with webhook status ──────────────────────────

  Future<void> loadAllInstances() async {
    final cached = await _repo.cachedInstances();
    if (cached.isNotEmpty) {
      state = state.copyWith(allInstances: cached, loadingInstances: false);
    } else {
      state = state.copyWith(loadingInstances: true);
    }
    try {
      final raw = await _repo.listAllInstancesForCrm();
      final instances = raw.map(WaCrmInstanceEntry.fromJson).toList();
      state = state.copyWith(
        allInstances: instances,
        loadingInstances: false,
        isOffline: false,
      );
      if (!_autoSyncedWebhookEvents) {
        _autoSyncedWebhookEvents = true;
        unawaited(_resyncEnabledWebhookEvents(instances));
      }
    } catch (e, st) {
      debugPrint('[WaCrm] loadAllInstances error: $e\n$st');
      state = state.copyWith(loadingInstances: false, isOffline: true);
    }
  }

  Future<void> _resyncEnabledWebhookEvents(
    List<WaCrmInstanceEntry> instances,
  ) async {
    for (final instance in instances.where((item) => item.webhookEnabled)) {
      try {
        await _repo.setInstanceWebhook(instance.instanceName, enabled: true);
      } catch (e) {
        debugPrint(
          '[WaCrm] auto webhook event sync failed for ${instance.instanceName}: $e',
        );
      }
    }
  }

  // ─── Set webhook for a specific instance ────────────────────────────

  Future<String> setInstanceWebhook(
    String instanceName, {
    required bool enabled,
  }) async {
    // Optimistic update
    final updated = state.allInstances.map((inst) {
      return inst.instanceName == instanceName
          ? inst.copyWithWebhook(enabled)
          : inst;
    }).toList();
    state = state.copyWith(allInstances: updated);

    try {
      final webhookUrl = await _repo.setInstanceWebhook(
        instanceName,
        enabled: enabled,
      );
      return webhookUrl;
    } catch (e, st) {
      debugPrint('[WaCrm] setInstanceWebhook error: $e\n$st');
      // Revert on error
      final reverted = state.allInstances.map((inst) {
        return inst.instanceName == instanceName
            ? inst.copyWithWebhook(!enabled)
            : inst;
      }).toList();
      state = state.copyWith(allInstances: reverted);
      rethrow;
    }
  }

  // ─── Load users ─────────────────────────────────────────────────────

  Future<void> loadUsers() async {
    final cached = await _repo.cachedUsers();
    if (cached.isNotEmpty) {
      state = state.copyWith(
        users: cached,
        loadingUsers: false,
        error: () => null,
      );
      if (state.selectedUser == null) {
        await selectUser(cached.first);
      }
    } else {
      state = state.copyWith(loadingUsers: true, error: () => null);
    }
    try {
      final raw = await _repo.listUsers();
      final users = raw.map(WaCrmUser.fromJson).toList();
      state = state.copyWith(
        users: users,
        loadingUsers: false,
        isOffline: false,
      );
      // Auto-select first user
      if (users.isNotEmpty && state.selectedUser == null) {
        await selectUser(users.first);
      }
    } catch (e, st) {
      debugPrint('[WaCrm] loadUsers error: $e\n$st');
      state = state.copyWith(
        loadingUsers: false,
        isOffline: cached.isNotEmpty,
        error: () => 'Error cargando usuarios: $e',
      );
    }
    // Also refresh the instance+webhook list
    unawaited(loadAllInstances());
  }

  // ─── Select user (loads conversations) ───────────────────────────────

  Future<void> selectUser(WaCrmUser user) async {
    final cachedConversations = await _repo.cachedConversations(user.id);
    state = state.copyWith(
      selectedUser: () => user,
      conversations: _sortConversations(
        _mergeConversationsByPhone(cachedConversations),
      ),
      selectedConversation: () => null,
      messages: [],
      composerUnlocked: false,
      composerUnlockedConversationKey: () => null,
      aiSummary: () => null,
      aiSummaryError: () => null,
      aiQuestionHistory: const [],
      askingAiQuestion: false,
    );
    unawaited(loadConversations(user.id));
  }

  Future<void> generateDailyAiSummary({DateTime? date}) async {
    final user = state.selectedUser;
    if (user == null) {
      state = state.copyWith(
        aiSummaryError: () => 'Selecciona un usuario para generar el resumen.',
      );
      return;
    }

    final selectedDate = date ?? state.aiSummaryDate ?? DateTime.now();
    final normalizedDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    state = state.copyWith(
      loadingAiSummary: true,
      aiSummaryError: () => null,
      aiSummaryDate: () => normalizedDate,
    );
    try {
      final raw = await _repo.summarizeDailyActivity(
        userId: user.id,
        date: normalizedDate,
      );
      state = state.copyWith(
        aiSummary: () => WaCrmDailyAiSummary.fromJson(raw),
        loadingAiSummary: false,
        aiQuestionHistory: const [],
      );
    } catch (e, st) {
      debugPrint('[WaCrm] generateDailyAiSummary error: $e\n$st');
      final fallback = _buildLocalDailyAiSummary(
        user: user,
        date: normalizedDate,
        reason: e,
      );
      state = state.copyWith(
        loadingAiSummary: false,
        aiSummary: () => fallback,
        aiSummaryError: () => null,
      );
    }
  }

  Future<void> analyzeWithAi({
    required WaCrmAiAnalysisScope scope,
    bool forceRefresh = false,
  }) async {
    final user = state.selectedUser;
    if (user == null) {
      state = state.copyWith(
        aiSummaryError: () => 'Selecciona un usuario para analizar con IA.',
      );
      return;
    }
    if (scope == WaCrmAiAnalysisScope.conversation &&
        state.selectedConversation == null) {
      state = state.copyWith(
        aiSummaryError: () => 'Selecciona una conversación para analizarla.',
      );
      return;
    }
    final filter = _apiFilterFor(state.messageDateFilter);
    if (filter == null) {
      state = state.copyWith(
        aiSummaryError: () =>
            'Selecciona un filtro de fecha: Hoy, Ayer, Últimos 7 días, Este mes o Fecha personalizada.',
      );
      return;
    }

    state = state.copyWith(
      loadingAiSummary: true,
      aiSummaryError: () => null,
      aiAnalysisScope: scope,
      aiSummaryDate: () => state.customMessageDate,
    );
    try {
      final raw = await _repo.analyzeWithAi(
        scope: scope == WaCrmAiAnalysisScope.conversation
            ? 'conversation'
            : 'filter',
        filter: filter,
        userId: user.id,
        conversationId: scope == WaCrmAiAnalysisScope.conversation
            ? state.selectedConversation?.id
            : null,
        customDate: state.messageDateFilter == WaCrmMessageDateFilter.custom
            ? state.customMessageDate
            : null,
        forceRefresh: forceRefresh,
      );
      state = state.copyWith(
        aiSummary: () => WaCrmDailyAiSummary.fromJson(raw),
        loadingAiSummary: false,
        aiQuestionHistory: const [],
      );
    } catch (e, st) {
      debugPrint('[WaCrm] analyzeWithAi error: $e\n$st');
      state = state.copyWith(
        loadingAiSummary: false,
        aiSummaryError: () => 'No se pudo generar el análisis de IA: $e',
      );
    }
  }

  Future<void> askCurrentAiReport(String question) async {
    final cleanQuestion = question.trim();
    final summary = state.aiSummary;
    final reportId = summary?.analysisReportId;
    if (cleanQuestion.isEmpty) return;
    if (reportId == null || reportId.isEmpty) {
      state = state.copyWith(
        aiSummaryError: () =>
            'Genera primero un análisis avanzado para poder preguntar sobre el informe.',
      );
      return;
    }

    state = state.copyWith(askingAiQuestion: true, aiSummaryError: () => null);
    try {
      final raw = await _repo.askAiAnalysis(
        analysisReportId: reportId,
        question: cleanQuestion,
        conversationId:
            state.aiAnalysisScope == WaCrmAiAnalysisScope.conversation
            ? state.selectedConversation?.id
            : null,
        dateRange: summary?.dateRange,
      );
      final answer =
          sanitizeWaText(raw['answer']) ??
          'No hay evidencia suficiente en el reporte para afirmar eso.';
      state = state.copyWith(
        askingAiQuestion: false,
        aiQuestionHistory: [
          ...state.aiQuestionHistory,
          WaCrmAiQuestionAnswer(
            question: cleanQuestion,
            answer: answer,
            generatedAt: DateTime.now(),
          ),
        ],
      );
    } catch (e, st) {
      debugPrint('[WaCrm] askCurrentAiReport error: $e\n$st');
      state = state.copyWith(
        askingAiQuestion: false,
        aiSummaryError: () => 'No se pudo responder la pregunta: $e',
      );
    }
  }

  String? _apiFilterFor(WaCrmMessageDateFilter filter) {
    switch (filter) {
      case WaCrmMessageDateFilter.today:
        return 'today';
      case WaCrmMessageDateFilter.yesterday:
        return 'yesterday';
      case WaCrmMessageDateFilter.last7Days:
        return 'last7Days';
      case WaCrmMessageDateFilter.thisMonth:
        return 'thisMonth';
      case WaCrmMessageDateFilter.custom:
        return 'custom';
      case WaCrmMessageDateFilter.all:
        return null;
    }
  }

  WaCrmDailyAiSummary _buildLocalDailyAiSummary({
    required WaCrmUser user,
    required DateTime date,
    required Object reason,
  }) {
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final contacts = state.conversations.length;
    final loadedMessages = state.messages.length;
    final unread = state.conversations.fold<int>(
      0,
      (sum, conv) => sum + conv.unreadCount,
    );
    final recentContacts = state.conversations
        .take(5)
        .map((conv) => conv.displayName)
        .where((name) => name.trim().isNotEmpty)
        .join(', ');
    final reasonText = _friendlySummaryFailure(reason);
    final summary = [
      'Resumen parcial del $day para ${user.name}.',
      'No se pudo completar el analisis de IA en este intento ($reasonText), pero el reporte no se detuvo.',
      'Datos disponibles en pantalla: $contacts conversaciones cargadas, $loadedMessages mensajes de la conversacion abierta y $unread mensajes sin leer.',
      if (recentContacts.isNotEmpty) 'Contactos recientes: $recentContacts.',
      'Recomendacion: revisar primero conversaciones sin leer, clientes con mensajes recientes y cualquier chat que quedo sin respuesta.',
    ].join('\n\n');

    return WaCrmDailyAiSummary(
      source: 'local-fallback',
      summary: summary,
      stats: {
        'date': day,
        'userName': user.name,
        'totalMessages': loadedMessages,
        'incomingMessages': state.messages.where((m) => m.isIncoming).length,
        'outgoingMessages': state.messages.where((m) => m.isOutgoing).length,
        'contacts': contacts,
        'mediaMessages': state.messages
            .where((m) => m.messageType != WaMessageType.text)
            .length,
      },
      alerts: const [],
      conversationAnalysis: state.conversations
          .take(8)
          .map(
            (conv) => WaCrmConversationAnalysis(
              contact: conv.displayName,
              messageCount: conv.lastMessage == null ? 0 : 1,
              status: 'pending',
              issues: conv.unreadCount > 0
                  ? ['Tiene ${conv.unreadCount} mensaje(s) sin leer']
                  : const [],
              summary: conv.lastMessage?.previewText ?? 'Sin vista previa.',
            ),
          )
          .toList(),
    );
  }

  String _friendlySummaryFailure(Object error) {
    final text = error.toString();
    if (text.contains('receiveTimeout') || text.contains('timeout')) {
      return 'la API tardo mas de lo esperado';
    }
    if (text.contains('SocketException') || text.contains('connection')) {
      return 'hubo un problema de conexion';
    }
    return 'servicio no disponible temporalmente';
  }

  // ─── Load conversations ───────────────────────────────────────────────

  Future<void> loadConversations(String userId) async {
    final hasLocal =
        state.conversations.isNotEmpty && state.selectedUser?.id == userId;
    if (!hasLocal) {
      final cached = await _repo.cachedConversations(userId);
      if (cached.isNotEmpty) {
        state = state.copyWith(
          conversations: _sortConversations(_mergeConversationsByPhone(cached)),
          loadingConversations: false,
          error: () => null,
        );
      }
    }
    state = state.copyWith(
      loadingConversations: state.conversations.isEmpty,
      syncingInBackground: state.conversations.isNotEmpty,
      error: () => null,
    );
    try {
      final lastSync = await _repo.lastConversationSync(userId);
      final convs = _sortConversations(
        _mergeConversationsByPhone(
          await _repo.getConversations(userId, updatedAfter: lastSync),
        ),
      );
      final mergedConvs = _sortConversations(
        _mergeConversationsByPhone([...state.conversations, ...convs]),
      );
      final selected = state.selectedConversation;
      final selectedReplacement = selected == null
          ? null
          : mergedConvs.cast<WaCrmConversation?>().firstWhere(
              (conv) =>
                  conv?.id == selected.id ||
                  (conv?.instanceId == selected.instanceId &&
                      conv?.cleanPhone != null &&
                      conv?.cleanPhone == selected.cleanPhone),
              orElse: () => selected,
            );
      state = state.copyWith(
        conversations: mergedConvs,
        loadingConversations: false,
        syncingInBackground: false,
        isOffline: false,
        selectedConversation: () => selectedReplacement,
      );
    } catch (e, st) {
      debugPrint('[WaCrm] loadConversations error: $e\n$st');
      state = state.copyWith(
        loadingConversations: false,
        syncingInBackground: false,
        isOffline: state.conversations.isNotEmpty,
        error: () => state.conversations.isEmpty
            ? 'Error cargando conversaciones: $e'
            : null,
      );
    }
  }

  // ─── Select conversation (loads messages) ────────────────────────────

  Future<void> selectConversation(WaCrmConversation conv) async {
    final cachedMessages = await _repo.cachedMessages(conv.id);
    state = state.copyWith(
      selectedConversation: () => conv,
      messages: cachedMessages,
      composerUnlocked: false,
      composerUnlockedConversationKey: () => null,
    );
    unawaited(loadMessages(conv.id));
    // Mark as read
    try {
      await _repo.markRead(conv.id);
      final updated = state.conversations.map((c) {
        return c.id == conv.id
            ? WaCrmConversation(
                id: c.id,
                instanceId: c.instanceId,
                remoteJid: c.remoteJid,
                remotePhone: c.remotePhone,
                remoteName: c.remoteName,
                remoteAvatarUrl: c.remoteAvatarUrl,
                lastMessageAt: c.lastMessageAt,
                unreadCount: 0,
                messageCount: c.messageCount,
                lastMessage: c.lastMessage,
              )
            : c;
      }).toList();
      state = state.copyWith(conversations: _sortConversations(updated));
      final userId = state.selectedUser?.id;
      final readConversation = updated.cast<WaCrmConversation?>().firstWhere(
        (item) => item?.id == conv.id,
        orElse: () => null,
      );
      if (userId != null && readConversation != null) {
        unawaited(_repo.cacheConversation(userId, readConversation));
      }
    } catch (_) {}
  }

  // ─── Load messages ───────────────────────────────────────────────────

  Future<void> loadMessages(String conversationId) async {
    if (state.messages.isEmpty) {
      final cached = await _repo.cachedMessages(conversationId);
      if (cached.isNotEmpty) {
        state = state.copyWith(messages: cached, loadingMessages: false);
      }
    }
    state = state.copyWith(
      loadingMessages: state.messages.isEmpty,
      syncingInBackground: state.messages.isNotEmpty,
      error: () => null,
    );
    try {
      final lastSync = await _repo.lastMessageSync(conversationId);
      final msgs = await _repo.getMessages(conversationId, after: lastSync);
      state = state.copyWith(
        messages: _mergeMessages(state.messages, msgs),
        loadingMessages: false,
        syncingInBackground: false,
        isOffline: false,
      );
    } catch (e, st) {
      debugPrint('[WaCrm] loadMessages error: $e\n$st');
      state = state.copyWith(
        loadingMessages: false,
        syncingInBackground: false,
        isOffline: state.messages.isNotEmpty,
        error: () =>
            state.messages.isEmpty ? 'Error cargando mensajes: $e' : null,
      );
    }
  }

  // ─── Send reply ──────────────────────────────────────────────────────

  Future<void> refreshActiveView() async {
    final user = state.selectedUser;
    if (user == null) return;
    try {
      state = state.copyWith(
        syncingInBackground: state.conversations.isNotEmpty,
      );
      final lastConversationSync = await _repo.lastConversationSync(user.id);
      final convs = _sortConversations(
        _mergeConversationsByPhone(
          await _repo.getConversations(
            user.id,
            updatedAfter: lastConversationSync,
          ),
        ),
      );
      final mergedConvs = _sortConversations(
        _mergeConversationsByPhone([...state.conversations, ...convs]),
      );
      final selected = state.selectedConversation;
      WaCrmConversation? selectedReplacement;
      if (selected != null) {
        selectedReplacement = mergedConvs.cast<WaCrmConversation?>().firstWhere(
          (conv) =>
              conv?.id == selected.id ||
              (conv?.instanceId == selected.instanceId &&
                  conv?.cleanPhone != null &&
                  conv?.cleanPhone == selected.cleanPhone),
          orElse: () => selected,
        );
      }

      List<WaCrmMessage>? messages;
      if (selectedReplacement != null) {
        final lastMessageSync = await _repo.lastMessageSync(
          selectedReplacement.id,
        );
        final fresh = await _repo.getMessages(
          selectedReplacement.id,
          after: lastMessageSync,
        );
        messages = _mergeMessages(state.messages, fresh);
      }

      state = state.copyWith(
        conversations: mergedConvs,
        selectedConversation: () => selectedReplacement,
        messages: messages ?? state.messages,
        syncingInBackground: false,
        isOffline: false,
      );
    } catch (e) {
      debugPrint('[WaCrm] refreshActiveView error: $e');
      state = state.copyWith(
        syncingInBackground: false,
        isOffline: state.conversations.isNotEmpty || state.messages.isNotEmpty,
      );
    }
  }

  Future<void> sendReply(String text) async {
    final conv = state.selectedConversation;
    final canWrite =
        conv != null &&
        state.composerUnlocked &&
        state.composerUnlockedConversationKey == conv.mergeKey;
    if (conv == null || text.trim().isEmpty || !canWrite) return;

    state = state.copyWith(sending: true, error: () => null);
    try {
      await _repo.reply(conv.id, text.trim());
      state = state.copyWith(sending: false);
      // Silently refresh without clearing state or showing spinner
      _silentRefreshMessages(conv.id);
    } catch (e, st) {
      debugPrint('[WaCrm] sendReply error: $e\n$st');
      state = state.copyWith(
        sending: false,
        error: () => 'Error enviando mensaje: $e',
      );
    }
  }

  Future<void> sendMediaReply({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? caption,
  }) async {
    final conv = state.selectedConversation;
    final canWrite =
        conv != null &&
        state.composerUnlocked &&
        state.composerUnlockedConversationKey == conv.mergeKey;
    if (conv == null || bytes.isEmpty || !canWrite) return;

    state = state.copyWith(sending: true, error: () => null);
    try {
      await _repo.replyMedia(
        conversationId: conv.id,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        caption: caption,
      );
      state = state.copyWith(sending: false);
      _silentRefreshMessages(conv.id);
    } catch (e, st) {
      debugPrint('[WaCrm] sendMediaReply error: $e\n$st');
      state = state.copyWith(
        sending: false,
        error: () => 'Error enviando archivo: $e',
      );
    }
  }

  Future<bool> unlockComposer(String password) async {
    try {
      await _repo.unlockCompose(password);
      final conv = state.selectedConversation;
      state = state.copyWith(
        composerUnlocked: conv != null,
        composerUnlockedConversationKey: () => conv?.mergeKey,
        error: () => null,
      );
      return true;
    } catch (e, st) {
      debugPrint('[WaCrm] unlockComposer error: $e\n$st');
      state = state.copyWith(
        composerUnlocked: false,
        composerUnlockedConversationKey: () => null,
        error: () => 'No se pudo desbloquear el envio: $e',
      );
      return false;
    }
  }

  /// Refreshes messages in the background without the loading spinner.
  void _silentRefreshMessages(String conversationId) {
    _repo
        .lastMessageSync(conversationId)
        .then((lastSync) {
          return _repo.getMessages(conversationId, after: lastSync);
        })
        .then((msgs) {
          if (state.selectedConversation?.id == conversationId) {
            state = state.copyWith(
              messages: _mergeMessages(state.messages, msgs),
            );
          }
        })
        .catchError((e) {
          debugPrint('[WaCrm] _silentRefreshMessages error: $e');
        });
  }

  String? _normalizedPhoneFromRaw(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;
    final local = raw.split('@').first.split(':').first;
    final digits = local.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  WaCrmConversation? _findConversationByPhone(String? normalizedPhone) {
    if (normalizedPhone == null || normalizedPhone.isEmpty) return null;
    for (final conv in state.conversations) {
      if (conv.cleanPhone == normalizedPhone) return conv;
    }
    return null;
  }

  List<WaCrmConversation> _mergeConversationsByPhone(
    List<WaCrmConversation> conversations,
  ) {
    final byKey = <String, WaCrmConversation>{};
    for (final conv in conversations) {
      if (conv.isGroup) continue;
      final phone = conv.cleanPhone;
      final key = phone == null || phone.isEmpty
          ? '${conv.instanceId}:${conv.remoteJid}'
          : '${conv.instanceId}:$phone';
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = conv;
        continue;
      }
      final existingTime = existing.activityAt;
      final convTime = conv.activityAt;
      final newest = convTime.isAfter(existingTime) ? conv : existing;
      final oldest = convTime.isAfter(existingTime) ? existing : conv;
      byKey[key] = WaCrmConversation(
        id: newest.id,
        instanceId: newest.instanceId,
        remoteJid: newest.remoteJid.isNotEmpty
            ? newest.remoteJid
            : oldest.remoteJid,
        remotePhone: newest.cleanPhone ?? oldest.cleanPhone,
        remoteName:
            newest.remoteName != null &&
                newest.remoteName!.trim().toLowerCase() != 'me'
            ? newest.remoteName
            : oldest.remoteName,
        remoteAvatarUrl:
            (newest.remoteAvatarUrl != null &&
                newest.remoteAvatarUrl!.trim().isNotEmpty)
            ? newest.remoteAvatarUrl
            : oldest.remoteAvatarUrl,
        lastMessageAt: newest.lastMessageAt ?? oldest.lastMessageAt,
        unreadCount: newest.unreadCount + oldest.unreadCount,
        messageCount: newest.messageCount + oldest.messageCount,
        lastMessage: newest.lastMessage ?? oldest.lastMessage,
      );
    }
    return _sortConversations(byKey.values.toList());
  }

  List<WaCrmMessage> _mergeMessages(
    List<WaCrmMessage> existing,
    List<WaCrmMessage> incoming,
  ) {
    if (incoming.isEmpty) return existing;
    final byId = <String, WaCrmMessage>{};
    for (final message in existing) {
      byId[message.id] = message;
    }
    for (final message in incoming) {
      byId[message.id] = message;
    }
    final merged = byId.values.toList();
    merged.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return merged;
  }

  // ─── Real-time message push ───────────────────────────────────────────

  void handleRealtimeMessage(Map<String, dynamic> data) {
    try {
      final convData = data['conversation'] as Map<String, dynamic>?;
      final convId =
          sanitizeWaText(data['conversationId']) ??
          sanitizeWaText(data['conversation_id']) ??
          sanitizeWaText(convData?['id']);
      final payloadMessage = data['message'] as Map<String, dynamic>?;
      final msgData = payloadMessage ?? (data['id'] != null ? data : null);

      if (convId == null || msgData == null) return;

      final incomingConv = convData != null
          ? WaCrmConversation.fromJson(convData)
          : null;
      final incomingPhone =
          incomingConv?.cleanPhone ??
          _normalizedPhoneFromRaw(sanitizeWaText(msgData['remotePhone'])) ??
          _normalizedPhoneFromRaw(sanitizeWaText(msgData['remoteJid']));
      final byPhone = _findConversationByPhone(incomingPhone);

      final targetConversationId = (byPhone != null && byPhone.id != convId)
          ? byPhone.id
          : convId;
      final requiresConversationRefresh =
          byPhone != null && byPhone.id != convId;

      final normalizedMsg = <String, dynamic>{
        ...msgData,
        'conversation_id': targetConversationId,
        if (msgData['sentAt'] == null && msgData['createdAt'] != null)
          'sentAt': msgData['createdAt'],
        if (msgData['body'] == null && msgData['text'] != null)
          'body': msgData['text'],
      };
      final msg = WaCrmMessage.fromJson(normalizedMsg);

      final selected = state.selectedConversation;
      final selectedPhone = selected?.cleanPhone;
      final sameSelectedConversation =
          selected?.id == targetConversationId ||
          (selected != null &&
              selected.instanceId ==
                  (incomingConv?.instanceId ?? selected.instanceId) &&
              selectedPhone != null &&
              selectedPhone == incomingPhone);

      // If this conversation is currently open, append message
      var messageWasAlreadyOpen = false;
      if (sameSelectedConversation) {
        final alreadyExists = state.messages.any((m) => m.id == msg.id);
        messageWasAlreadyOpen = alreadyExists;
        state = state.copyWith(messages: _mergeMessages(state.messages, [msg]));
        if (selected?.id != targetConversationId && incomingConv != null) {
          state = state.copyWith(
            selectedConversation: () => incomingConv.copyWith(
              id: targetConversationId,
              lastMessageAt: () => incomingConv.lastMessageAt ?? msg.sentAt,
              unreadCount: 0,
              messageCount: incomingConv.messageCount + (alreadyExists ? 0 : 1),
              lastMessage: () => msg,
            ),
          );
        }
      }

      // Update conversation list (bump lastMessageAt + unreadCount)
      final existingConv = state.conversations
          .cast<WaCrmConversation?>()
          .firstWhere(
            (c) => c?.id == targetConversationId,
            orElse: () => byPhone,
          );
      final preferredBase = existingConv ?? incomingConv;
      final incomingRawPhone = incomingConv?.remotePhone;
      final incomingName = incomingConv?.remoteName;
      final incomingAvatar = incomingConv?.remoteAvatarUrl;
      final baseConv = preferredBase?.copyWith(
        instanceId: incomingConv?.instanceId,
        remoteJid: incomingConv?.remoteJid,
        remotePhone: incomingRawPhone?.trim().isNotEmpty == true
            ? () => incomingRawPhone
            : null,
        remoteName: incomingName?.trim().isNotEmpty == true
            ? () => incomingName
            : null,
        remoteAvatarUrl: incomingAvatar?.trim().isNotEmpty == true
            ? () => incomingAvatar
            : null,
      );
      if (baseConv != null) {
        final alreadyLastMessage = baseConv.lastMessage?.id == msg.id;
        final isDuplicateMessage = messageWasAlreadyOpen || alreadyLastMessage;
        final shouldIncrementUnread =
            msg.isIncoming && !sameSelectedConversation && !isDuplicateMessage;
        final updatedConv = baseConv.copyWith(
          id: targetConversationId,
          lastMessageAt: () => msg.sentAt,
          unreadCount: shouldIncrementUnread
              ? baseConv.unreadCount + 1
              : sameSelectedConversation
              ? 0
              : baseConv.unreadCount,
          messageCount: baseConv.messageCount + (isDuplicateMessage ? 0 : 1),
          lastMessage: () => msg,
        );
        final withoutTarget = state.conversations
            .where((c) => c.id != targetConversationId)
            .toList();
        state = state.copyWith(
          conversations: _mergeConversationsByPhone([
            updatedConv,
            ...withoutTarget,
          ]),
          selectedConversation: sameSelectedConversation
              ? () => updatedConv.copyWith(unreadCount: 0)
              : null,
        );
        final userId = state.selectedUser?.id;
        if (userId != null) {
          unawaited(
            _repo.cacheRealtimeMessage(
              userId: userId,
              conversation: updatedConv,
              message: msg,
            ),
          );
        }
        _pulseConversation(targetConversationId);
      }

      if (requiresConversationRefresh && state.selectedUser != null) {
        unawaited(loadConversations(state.selectedUser!.id));
      }
    } catch (e) {
      debugPrint('[WaCrm] handleRealtimeMessage error: $e');
    }
  }
}
