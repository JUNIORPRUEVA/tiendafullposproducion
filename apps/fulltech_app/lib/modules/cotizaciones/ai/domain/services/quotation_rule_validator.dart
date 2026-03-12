import '../models/ai_validation_result.dart';
import '../models/ai_warning.dart';
import '../models/business_rule.dart';
import '../models/quotation_context.dart';

class QuotationRuleValidator {
  const QuotationRuleValidator();

  AiValidationResult validate({
    required QuotationContext context,
    required List<BusinessRule> rules,
  }) {
    if (rules.isEmpty) {
      return const AiValidationResult(
        isValid: true,
        warnings: [],
        summary: 'Validación local sin reglas cargadas.',
      );
    }

    final warnings = <AiWarning>[];

    final priceRule = _findRule(rules, const ['precio', 'minimo']);
    final dvrRule = _findRule(rules, const ['dvr', 'camara']);
    final installationRule = _findRule(rules, const ['instal', 'recargo']);
    final warrantyRule = _findRule(rules, const ['garant']);

    for (final item in context.items) {
      if (priceRule != null &&
          item.officialUnitPrice != null &&
          item.unitPrice < item.officialUnitPrice!) {
        warnings.add(
          AiWarning(
            id: 'price-${item.productId}',
            title: 'Precio ajustado por debajo del valor oficial',
            description:
                'La línea ${item.productName} fue cotizada por debajo del precio oficial disponible en el sistema. Revisa la política de precios antes de enviar.',
            type: AiWarningType.warning,
            relatedRuleId: priceRule.id,
            relatedRuleTitle: priceRule.title,
            suggestedAction:
                'Verificar precio mínimo o autorización comercial.',
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    final totalCameras = context.items
        .where(
          (item) => _containsAny('${item.productName} ${item.category}', const [
            'camara',
            'camera',
          ]),
        )
        .fold<double>(0, (sum, item) => sum + item.qty);
    final currentDvrChannels = _parseDvrChannels(
      context.currentDvrType ??
          context.items
              .where(
                (item) =>
                    _containsAny(item.productName, const ['dvr', 'nvr', 'xvr']),
              )
              .map((item) => item.productName)
              .join(' '),
    );
    final requiredDvrChannels =
        _parseDvrChannels(context.requiredDvrType) ??
        (dvrRule != null ? _deriveRequiredDvrChannels(totalCameras) : null);

    if (dvrRule != null && totalCameras > 0 && requiredDvrChannels != null) {
      if (currentDvrChannels == null) {
        warnings.add(
          AiWarning(
            id: 'dvr-missing',
            title: 'Posible DVR faltante',
            description:
                'La cotización incluye cámaras, pero no se detectó un DVR/NVR asociado. Revisa la política oficial para confirmar el equipo requerido.',
            type: AiWarningType.warning,
            relatedRuleId: dvrRule.id,
            relatedRuleTitle: dvrRule.title,
            suggestedAction:
                'Validar el DVR correspondiente a la cantidad de cámaras.',
            createdAt: DateTime.now(),
          ),
        );
      } else if (currentDvrChannels < requiredDvrChannels) {
        warnings.add(
          AiWarning(
            id: 'dvr-capacity',
            title: 'DVR posiblemente insuficiente',
            description:
                'La cantidad de cámaras parece requerir un DVR de al menos $requiredDvrChannels canales, pero el contexto actual apunta a $currentDvrChannels canales.',
            type: AiWarningType.warning,
            relatedRuleId: dvrRule.id,
            relatedRuleTitle: dvrRule.title,
            suggestedAction:
                'Verificar la regla de DVR antes de cerrar la cotización.',
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    if (installationRule != null &&
        (context.installationType ?? '').toLowerCase().contains('compleja')) {
      final hasComplexCharge = context.extraCharges.any(
        (item) =>
            _containsAny(item, const ['recargo', 'compleja', 'instalacion']),
      );
      if (!hasComplexCharge) {
        warnings.add(
          AiWarning(
            id: 'complex-installation',
            title: 'Instalación compleja sin recargo visible',
            description:
                'El contexto indica instalación compleja, pero no se detectó un recargo asociado en la cotización actual.',
            type: AiWarningType.warning,
            relatedRuleId: installationRule.id,
            relatedRuleTitle: installationRule.title,
            suggestedAction:
                'Confirmar si aplica cargo adicional por instalación compleja.',
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    if (warrantyRule != null &&
        (context.notes ?? '').trim().isNotEmpty &&
        _containsAny(context.notes!, const ['garantia']) &&
        !_containsAny(warrantyRule.content, const ['garantia'])) {
      warnings.add(
        AiWarning(
          id: 'warranty-note',
          title: 'Revisa la garantía mencionada',
          description:
              'La cotización menciona garantía en las observaciones. Verifica que coincida con la política oficial vigente.',
          type: AiWarningType.info,
          relatedRuleId: warrantyRule.id,
          relatedRuleTitle: warrantyRule.title,
          suggestedAction:
              'Comparar el texto de garantía con la regla oficial.',
          createdAt: DateTime.now(),
        ),
      );
    }
    return AiValidationResult(
      isValid: warnings.every(
        (warning) => warning.type != AiWarningType.warning,
      ),
      warnings: warnings,
      summary: warnings.isEmpty
          ? 'Sin alertas locales.'
          : warnings.first.description,
    );
  }

  BusinessRule? _findRule(List<BusinessRule> rules, List<String> terms) {
    for (final rule in rules) {
      final text = '${rule.title} ${rule.summary ?? ''} ${rule.content}'
          .toLowerCase();
      if (terms.every(text.contains)) return rule;
    }
    for (final rule in rules) {
      final text = '${rule.title} ${rule.summary ?? ''} ${rule.content}'
          .toLowerCase();
      if (terms.any(text.contains)) return rule;
    }
    return null;
  }

  bool _containsAny(String value, List<String> tokens) {
    final text = value.toLowerCase();
    return tokens.any(text.contains);
  }

  int? _parseDvrChannels(String? value) {
    final text = (value ?? '').toLowerCase();
    if (text.isEmpty) return null;
    final match = RegExp(r'(\d{1,2})\s*(canales|canal)').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  int? _deriveRequiredDvrChannels(double totalCameras) {
    if (totalCameras <= 0) return null;
    if (totalCameras <= 4) return 4;
    if (totalCameras <= 8) return 8;
    if (totalCameras <= 16) return 16;
    return 32;
  }
}
