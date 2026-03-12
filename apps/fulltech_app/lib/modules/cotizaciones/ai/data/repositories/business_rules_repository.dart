import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../manual_interno/company_manual_models.dart';
import '../../../../manual_interno/company_manual_repository.dart';
import '../../domain/models/business_rule.dart';

final businessRulesRepositoryProvider = Provider<BusinessRulesRepository>((
  ref,
) {
  return BusinessRulesRepository(ref.watch(companyManualRepositoryProvider));
});

class BusinessRulesRepository {
  BusinessRulesRepository(this._manualRepository);

  final CompanyManualRepository _manualRepository;

  List<BusinessRule>? _cachedRules;
  DateTime? _cachedAt;
  final Map<String, BusinessRule> _byIdCache = {};
  static const Duration _cacheTtl = Duration(minutes: 5);

  Future<List<BusinessRule>> loadQuotationRules({
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedRules != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheTtl) {
      return _cachedRules!;
    }

    final entries = await _manualRepository.listEntries(includeHidden: false);
    final rules = entries
        .where(_isRelevantRule)
        .map(_mapEntry)
        .toList(growable: false);

    _cachedRules = rules;
    _cachedAt = now;
    for (final rule in rules) {
      _byIdCache[rule.id] = rule;
    }
    return rules;
  }

  Future<BusinessRule?> getRuleById(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return null;
    final cached = _byIdCache[normalizedId];
    if (cached != null) return cached;

    final entry = await _manualRepository.getEntryById(normalizedId);
    final rule = _mapEntry(entry);
    _byIdCache[rule.id] = rule;
    return rule;
  }

  Future<BusinessRule?> findRuleByTitle(String title) async {
    final query = title.trim().toLowerCase();
    if (query.isEmpty) return null;
    final rules = await loadQuotationRules();
    for (final rule in rules) {
      if (rule.title.trim().toLowerCase() == query) return rule;
    }
    for (final rule in rules) {
      if (rule.title.toLowerCase().contains(query)) return rule;
    }
    return null;
  }

  bool _isRelevantRule(CompanyManualEntry entry) {
    final moduleKey = (entry.moduleKey ?? '').trim().toLowerCase();
    const allowedModules = {'', 'cotizaciones', 'cotizacion', 'ventas'};
    if (allowedModules.contains(moduleKey)) return true;

    switch (entry.kind) {
      case CompanyManualEntryKind.generalRule:
      case CompanyManualEntryKind.policy:
      case CompanyManualEntryKind.warrantyPolicy:
      case CompanyManualEntryKind.productService:
      case CompanyManualEntryKind.priceRule:
      case CompanyManualEntryKind.serviceRule:
      case CompanyManualEntryKind.moduleGuide:
        return true;
      case CompanyManualEntryKind.roleRule:
      case CompanyManualEntryKind.responsibility:
        return false;
    }
  }

  BusinessRule _mapEntry(CompanyManualEntry entry) {
    final contentBlob = [
      entry.title,
      entry.summary ?? '',
      entry.content,
      entry.moduleKey ?? '',
      entry.kind.label,
    ].join(' ');

    return BusinessRule(
      id: entry.id,
      module: (entry.moduleKey ?? 'general').trim().toLowerCase().isEmpty
          ? 'general'
          : entry.moduleKey!.trim().toLowerCase(),
      category: _mapCategory(entry.kind),
      title: entry.title,
      summary: entry.summary,
      content: entry.content,
      keywords: _tokenize(contentBlob).take(18).toList(growable: false),
      severity: _mapSeverity(entry),
      active: entry.published,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
    );
  }

  String _mapCategory(CompanyManualEntryKind kind) {
    switch (kind) {
      case CompanyManualEntryKind.priceRule:
        return 'precios';
      case CompanyManualEntryKind.warrantyPolicy:
        return 'garantias';
      case CompanyManualEntryKind.productService:
        return 'productos';
      case CompanyManualEntryKind.serviceRule:
        return 'servicios';
      case CompanyManualEntryKind.moduleGuide:
        return 'modulo';
      case CompanyManualEntryKind.policy:
        return 'politicas';
      case CompanyManualEntryKind.generalRule:
      case CompanyManualEntryKind.roleRule:
      case CompanyManualEntryKind.responsibility:
        return 'general';
    }
  }

  BusinessRuleSeverity _mapSeverity(CompanyManualEntry entry) {
    final text = '${entry.title} ${entry.content}'.toLowerCase();
    if (text.contains('prohib') || text.contains('obligatorio')) {
      return BusinessRuleSeverity.critical;
    }
    if (entry.kind == CompanyManualEntryKind.priceRule ||
        entry.kind == CompanyManualEntryKind.warrantyPolicy ||
        text.contains('mínimo') ||
        text.contains('minimo')) {
      return BusinessRuleSeverity.warning;
    }
    return BusinessRuleSeverity.info;
  }

  Iterable<String> _tokenize(String value) sync* {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâ]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöô]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    for (final token in normalized.split(' ')) {
      final cleaned = token.trim();
      if (cleaned.length >= 3) {
        yield cleaned;
      }
    }
  }
}
