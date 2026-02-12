import 'package:intl/date_symbol_data_local.dart';

/// Llama esto en main() antes de runApp para evitar LocaleDataException.
Future<void> ensureContabilidadLocale() async {
  await initializeDateFormatting('es');
}
