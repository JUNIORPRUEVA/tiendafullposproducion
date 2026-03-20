import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Llama esto en main() antes de runApp para evitar LocaleDataException.
Future<void>? _contabilidadLocaleFuture;

Future<void> ensureContabilidadLocale({String? locale}) {
  _contabilidadLocaleFuture ??= _initializeContabilidadLocale(locale);
  return _contabilidadLocaleFuture!;
}

Future<void> _initializeContabilidadLocale(String? locale) async {
  final candidates = <String>{..._localeCandidates(locale), 'es_DO', 'es'};

  for (final candidate in candidates) {
    await initializeDateFormatting(candidate);
  }

  Intl.defaultLocale = _preferredLocale(candidates);
}

Iterable<String> _localeCandidates(String? rawLocale) sync* {
  final normalized = (rawLocale ?? '').trim().replaceAll('-', '_');
  if (normalized.isEmpty) return;

  yield normalized;

  final separator = normalized.indexOf('_');
  if (separator > 0) {
    final languageCode = normalized.substring(0, separator).trim();
    if (languageCode.isNotEmpty) {
      yield languageCode;
    }
  }
}

String _preferredLocale(Set<String> candidates) {
  for (final candidate in candidates) {
    if (candidate.toLowerCase() == 'es_do') return candidate;
  }

  for (final candidate in candidates) {
    if (candidate.toLowerCase().startsWith('es')) return candidate;
  }

  return 'es_DO';
}
