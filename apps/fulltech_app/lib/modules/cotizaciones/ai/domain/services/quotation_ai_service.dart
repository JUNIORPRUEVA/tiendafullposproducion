import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/openai_datasource.dart';
import '../models/ai_chat_message.dart';
import '../models/ai_validation_result.dart';
import '../models/ai_warning.dart';
import '../models/business_rule.dart';
import '../models/quotation_context.dart';

final quotationAiServiceProvider = Provider<QuotationAiService>((ref) {
  return QuotationAiService(ref.watch(quotationOpenAiDataSourceProvider));
});

class QuotationAiService {
  QuotationAiService(this._dataSource);

  final QuotationOpenAiDataSource _dataSource;

  Future<AiValidationResult> analyzeQuotation({
    required QuotationContext context,
    String? instruction,
  }) async {
    final payload = await _dataSource.analyzeQuotation(
      context: context,
      instruction: instruction,
    );

    final rawWarnings = payload['warnings'];
    final warnings = rawWarnings is List
        ? rawWarnings
              .whereType<Map>()
              .map((item) => _warningFromMap(item.cast<String, dynamic>()))
              .toList(growable: false)
        : const <AiWarning>[];

    final summary = (payload['summary'] ?? '').toString().trim();
    return AiValidationResult(
      isValid: warnings.every(
        (warning) => warning.type != AiWarningType.warning,
      ),
      warnings: warnings,
      summary: summary,
    );
  }

  Future<AiChatMessage> sendMessage({
    required QuotationContext context,
    required String message,
  }) async {
    final payload = await _dataSource.chat(context: context, message: message);
    final rawCitations = payload['citations'];
    final citations = rawCitations is List
        ? rawCitations
              .whereType<Map>()
              .map((item) => _referenceFromMap(item.cast<String, dynamic>()))
              .toList(growable: false)
        : const <BusinessRuleReference>[];

    return AiChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: AiChatRole.assistant,
      content: (payload['content'] ?? '').toString().trim(),
      createdAt: DateTime.now(),
      relatedRuleId: _nullableString(payload['relatedRuleId']),
      relatedRuleTitle: _nullableString(payload['relatedRuleTitle']),
      citations: citations,
    );
  }

  AiWarning _warningFromMap(Map<String, dynamic> map) {
    final typeRaw = (map['type'] ?? '').toString().trim().toLowerCase();
    final type = switch (typeRaw) {
      'warning' => AiWarningType.warning,
      'success' => AiWarningType.success,
      _ => AiWarningType.info,
    };
    return AiWarning(
      id: (map['id'] ?? DateTime.now().microsecondsSinceEpoch).toString(),
      title: (map['title'] ?? '').toString().trim(),
      description: (map['description'] ?? '').toString().trim(),
      type: type,
      relatedRuleId: _nullableString(map['relatedRuleId']),
      relatedRuleTitle: _nullableString(map['relatedRuleTitle']),
      suggestedAction: _nullableString(map['suggestedAction']),
      createdAt: DateTime.now(),
    );
  }

  BusinessRuleReference _referenceFromMap(Map<String, dynamic> map) {
    return BusinessRuleReference(
      id: (map['id'] ?? '').toString(),
      module: (map['module'] ?? 'general').toString(),
      category: (map['category'] ?? 'general').toString(),
      title: (map['title'] ?? '').toString(),
    );
  }

  String? _nullableString(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
