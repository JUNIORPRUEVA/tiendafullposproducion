import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/business_rules_repository.dart';
import '../domain/models/ai_chat_message.dart';
import '../domain/models/ai_validation_result.dart';
import '../domain/models/ai_warning.dart';
import '../domain/models/business_rule.dart';
import '../domain/models/quotation_context.dart';
import '../domain/services/quotation_ai_service.dart';
import '../domain/services/quotation_rule_validator.dart';

final quotationAiControllerProvider =
    StateNotifierProvider.autoDispose<QuotationAiController, QuotationAiState>((ref) {
      return QuotationAiController(
        ref: ref,
        aiService: ref.watch(quotationAiServiceProvider),
        rulesRepository: ref.watch(businessRulesRepositoryProvider),
        validator: const QuotationRuleValidator(),
      );
    });

class QuotationAiState {
  const QuotationAiState({
    required this.loadingRules,
    required this.analyzing,
    required this.sendingMessage,
    required this.rules,
    required this.context,
    required this.localValidation,
    required this.aiValidation,
    required this.messages,
    required this.visibleWarnings,
    required this.analysisError,
    required this.chatError,
    required this.hasLoadedRules,
  });

  factory QuotationAiState.initial() => QuotationAiState(
    loadingRules: false,
    analyzing: false,
    sendingMessage: false,
    rules: const [],
    context: null,
    localValidation: const AiValidationResult.empty(),
    aiValidation: const AiValidationResult.empty(),
    messages: [
      AiChatMessage(
        id: 'assistant-intro',
        role: AiChatRole.assistant,
        content:
            'Trabajo solo con reglas oficiales del sistema. Si una política no existe, te lo diré claramente.',
        createdAt: DateTime.now(),
      ),
    ],
    visibleWarnings: const [],
    analysisError: null,
    chatError: null,
    hasLoadedRules: false,
  );

  final bool loadingRules;
  final bool analyzing;
  final bool sendingMessage;
  final List<BusinessRule> rules;
  final QuotationContext? context;
  final AiValidationResult localValidation;
  final AiValidationResult aiValidation;
  final List<AiChatMessage> messages;
  final List<AiWarning> visibleWarnings;
  final String? analysisError;
  final String? chatError;
  final bool hasLoadedRules;

  QuotationAiState copyWith({
    bool? loadingRules,
    bool? analyzing,
    bool? sendingMessage,
    List<BusinessRule>? rules,
    QuotationContext? context,
    bool clearContext = false,
    AiValidationResult? localValidation,
    AiValidationResult? aiValidation,
    List<AiChatMessage>? messages,
    List<AiWarning>? visibleWarnings,
    String? analysisError,
    bool clearAnalysisError = false,
    String? chatError,
    bool clearChatError = false,
    bool? hasLoadedRules,
  }) {
    return QuotationAiState(
      loadingRules: loadingRules ?? this.loadingRules,
      analyzing: analyzing ?? this.analyzing,
      sendingMessage: sendingMessage ?? this.sendingMessage,
      rules: rules ?? this.rules,
      context: clearContext ? null : (context ?? this.context),
      localValidation: localValidation ?? this.localValidation,
      aiValidation: aiValidation ?? this.aiValidation,
      messages: messages ?? this.messages,
      visibleWarnings: visibleWarnings ?? this.visibleWarnings,
      analysisError: clearAnalysisError ? null : (analysisError ?? this.analysisError),
      chatError: clearChatError ? null : (chatError ?? this.chatError),
      hasLoadedRules: hasLoadedRules ?? this.hasLoadedRules,
    );
  }
}

class QuotationAiController extends StateNotifier<QuotationAiState> {
  QuotationAiController({
    required this.ref,
    required QuotationAiService aiService,
    required BusinessRulesRepository rulesRepository,
    required QuotationRuleValidator validator,
  }) : _aiService = aiService,
       _rulesRepository = rulesRepository,
       _validator = validator,
       super(QuotationAiState.initial()) {
    unawaited(_ensureRulesLoaded());
  }

  final Ref ref;
  final QuotationAiService _aiService;
  final BusinessRulesRepository _rulesRepository;
  final QuotationRuleValidator _validator;

  final Map<String, AiValidationResult> _analysisCache = {};
  final Map<String, AiChatMessage> _chatCache = {};
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> refreshRules() async {
    await _ensureRulesLoaded(forceRefresh: true);
  }

  Future<void> setContext(
    QuotationContext context, {
    bool triggerAi = true,
  }) async {
    final sameSignature = state.context?.signature == context.signature;
    state = state.copyWith(
      context: context,
      clearAnalysisError: true,
      clearChatError: true,
    );

    if (!state.hasLoadedRules) {
      await _ensureRulesLoaded();
    }

    _applyLocalValidation();
    if (!triggerAi || sameSignature || context.items.isEmpty) {
      return;
    }
    _scheduleAiAnalysis();
  }

  Future<void> explainWarnings() async {
    if (state.visibleWarnings.isEmpty) return;
    final titles = state.visibleWarnings
        .where((warning) => warning.type != AiWarningType.success)
        .map((warning) => warning.title)
        .take(4)
        .join(', ');
    await sendMessage(
      'Explícame estas advertencias con base en las reglas oficiales: $titles',
    );
  }

  Future<void> sendMessage(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final context = state.context;
    if (context == null) return;

    final userMessage = AiChatMessage(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      role: AiChatRole.user,
      content: trimmed,
      createdAt: DateTime.now(),
    );

    final placeholder = AiChatMessage(
      id: 'assistant-loading-${DateTime.now().microsecondsSinceEpoch}',
      role: AiChatRole.assistant,
      content: 'Consultando reglas oficiales...',
      createdAt: DateTime.now(),
      isLoading: true,
    );

    state = state.copyWith(
      sendingMessage: true,
      messages: [...state.messages, userMessage, placeholder],
      clearChatError: true,
    );

    final cacheKey = '${context.signature}::$trimmed';
    final cached = _chatCache[cacheKey];
    if (cached != null) {
      _replaceLoadingMessage(cached);
      return;
    }

    try {
      final response = await _aiService.sendMessage(
        context: context,
        message: trimmed,
      );
      _chatCache[cacheKey] = response;
      _replaceLoadingMessage(response);
      _logDebug('chat.response', response.content);
    } catch (error) {
      final fallback = AiChatMessage(
        id: 'assistant-error-${DateTime.now().microsecondsSinceEpoch}',
        role: AiChatRole.assistant,
        content:
            'No pude consultar la IA en este momento. Las validaciones locales continúan activas.',
        createdAt: DateTime.now(),
        isError: true,
      );
      _replaceLoadingMessage(fallback, chatError: '$error');
      _logDebug('chat.error', error);
    }
  }

  Future<void> askQuickAction(String prompt) => sendMessage(prompt);

  BusinessRule? findRule({String? ruleId, String? title}) {
    final normalizedId = (ruleId ?? '').trim();
    if (normalizedId.isNotEmpty) {
      for (final rule in state.rules) {
        if (rule.id == normalizedId) return rule;
      }
    }

    final normalizedTitle = (title ?? '').trim().toLowerCase();
    if (normalizedTitle.isNotEmpty) {
      for (final rule in state.rules) {
        if (rule.title.trim().toLowerCase() == normalizedTitle) return rule;
      }
      for (final rule in state.rules) {
        if (rule.title.toLowerCase().contains(normalizedTitle)) return rule;
      }
    }
    return null;
  }

  Future<BusinessRule?> loadRuleDetail({String? ruleId, String? title}) async {
    final existing = findRule(ruleId: ruleId, title: title);
    if (existing != null) return existing;

    final normalizedId = (ruleId ?? '').trim();
    if (normalizedId.isNotEmpty) {
      final rule = await _rulesRepository.getRuleById(normalizedId);
      if (rule != null) {
        state = state.copyWith(rules: [...state.rules, rule]);
      }
      return rule;
    }

    final normalizedTitle = (title ?? '').trim();
    if (normalizedTitle.isEmpty) return null;
    final rule = await _rulesRepository.findRuleByTitle(normalizedTitle);
    if (rule != null && state.rules.every((item) => item.id != rule.id)) {
      state = state.copyWith(rules: [...state.rules, rule]);
    }
    return rule;
  }

  Future<void> _ensureRulesLoaded({bool forceRefresh = false}) async {
    if (state.loadingRules) return;
    state = state.copyWith(loadingRules: true, clearAnalysisError: true);
    try {
      final rules = await _rulesRepository.loadQuotationRules(
        forceRefresh: forceRefresh,
      );
      state = state.copyWith(
        loadingRules: false,
        rules: rules,
        hasLoadedRules: true,
      );
      _applyLocalValidation();
    } catch (error) {
      state = state.copyWith(
        loadingRules: false,
        hasLoadedRules: true,
        analysisError: '$error',
      );
      _logDebug('rules.error', error);
    }
  }

  void _applyLocalValidation() {
    final context = state.context;
    if (context == null) return;

    final localValidation = _validator.validate(
      context: context,
      rules: state.rules,
    );

    state = state.copyWith(
      localValidation: localValidation,
      visibleWarnings: _mergeWarnings(localValidation.warnings, state.aiValidation.warnings),
    );
    _logDebug('local.validation', localValidation.summary);
  }

  void _scheduleAiAnalysis() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1100), () {
      unawaited(_runAiAnalysis());
    });
  }

  Future<void> _runAiAnalysis() async {
    final context = state.context;
    if (context == null || context.items.isEmpty) return;

    final signature = context.signature;
    final cached = _analysisCache[signature];
    if (cached != null) {
      state = state.copyWith(
        aiValidation: cached,
        visibleWarnings: _mergeWarnings(state.localValidation.warnings, cached.warnings),
        clearAnalysisError: true,
      );
      return;
    }

    state = state.copyWith(analyzing: true, clearAnalysisError: true);
    try {
      final aiValidation = await _aiService.analyzeQuotation(
        context: context,
        instruction: 'Revisa esta cotización y genera advertencias no bloqueantes usando solo reglas oficiales.',
      );
      _analysisCache[signature] = aiValidation;
      state = state.copyWith(
        analyzing: false,
        aiValidation: aiValidation,
        visibleWarnings: _mergeWarnings(state.localValidation.warnings, aiValidation.warnings),
      );
      _logDebug('ai.validation', aiValidation.summary);
    } catch (error) {
      state = state.copyWith(analyzing: false, analysisError: '$error');
      _logDebug('ai.validation.error', error);
    }
  }

  void _replaceLoadingMessage(AiChatMessage message, {String? chatError}) {
    final messages = [...state.messages];
    final index = messages.lastIndexWhere((item) => item.isLoading);
    if (index >= 0) {
      messages[index] = message;
    } else {
      messages.add(message);
    }

    state = state.copyWith(
      sendingMessage: false,
      messages: messages,
      chatError: chatError,
      clearChatError: chatError == null,
    );
  }

  List<AiWarning> _mergeWarnings(
    List<AiWarning> localWarnings,
    List<AiWarning> aiWarnings,
  ) {
    final merged = <AiWarning>[];
    final seen = <String>{};
    for (final warning in [...localWarnings, ...aiWarnings]) {
      final key = '${warning.title}|${warning.relatedRuleId}|${warning.type.name}';
      if (seen.add(key)) {
        merged.add(warning);
      }
    }
    return merged;
  }

  void _logDebug(String label, Object? payload) {
    if (!kDebugMode) return;
    debugPrint('[QuotationAiController] $label => $payload');
  }
}