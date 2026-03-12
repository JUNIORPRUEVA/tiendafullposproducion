import 'ai_warning.dart';

class AiValidationResult {
  const AiValidationResult({
    required this.isValid,
    required this.warnings,
    required this.summary,
  });

  final bool isValid;
  final List<AiWarning> warnings;
  final String summary;

  const AiValidationResult.empty()
    : isValid = true,
      warnings = const [],
      summary = '';
}
