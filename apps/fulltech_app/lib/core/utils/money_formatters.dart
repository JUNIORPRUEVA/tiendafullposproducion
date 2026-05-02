import 'package:intl/intl.dart';

const String kRdMoneyLocaleCode = 'es_DO';

NumberFormat rdAccountingNumberFormat() {
  return NumberFormat('#,##0.00', kRdMoneyLocaleCode);
}

String formatRdAccountingAmount(num value) {
  return rdAccountingNumberFormat().format(value);
}
