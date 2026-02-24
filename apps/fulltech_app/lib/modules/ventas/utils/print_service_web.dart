import 'dart:html' as html;
import 'dart:convert';

import 'package:intl/intl.dart';

import '../sales_models.dart';

Future<void> printSalesSummary({
  required String employeeName,
  required DateTime from,
  required DateTime to,
  required SalesSummaryModel summary,
  required List<SaleModel> sales,
}) async {
  final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
  final dateFmt = DateFormat('dd/MM/yyyy');

  final rows = sales
      .map(
        (sale) =>
            '''
<tr>
  <td>${dateFmt.format(sale.saleDate ?? DateTime.now())}</td>
  <td>${sale.customerName ?? 'Sin cliente'}</td>
  <td style="text-align:right;">${currency.format(sale.totalSold)}</td>
  <td style="text-align:right;">${currency.format(sale.totalProfit)}</td>
  <td style="text-align:right;">${currency.format(sale.commissionAmount)}</td>
</tr>
''',
      )
      .join();

  final htmlContent =
      '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Comprobante quincenal</title>
  <style>
    body { font-family: Arial, sans-serif; padding: 24px; color: #111; }
    h1 { margin: 0 0 8px; }
    .meta { margin-bottom: 16px; }
    .summary { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-bottom: 16px; }
    .card { border: 1px solid #ddd; border-radius: 8px; padding: 10px; }
    .label { font-size: 12px; color: #555; }
    .value { font-size: 18px; font-weight: 700; }
    table { width: 100%; border-collapse: collapse; }
    th, td { border: 1px solid #ddd; padding: 8px; font-size: 12px; }
    th { background: #f5f5f5; text-align: left; }
  </style>
</head>
<body>
  <h1>Comprobante quincenal de comisión</h1>
  <div class="meta">
    <div><strong>Empleado:</strong> $employeeName</div>
    <div><strong>Rango:</strong> ${dateFmt.format(from)} - ${dateFmt.format(to)}</div>
  </div>

  <div class="summary">
    <div class="card"><div class="label">Total vendido</div><div class="value">${currency.format(summary.totalSold)}</div></div>
    <div class="card"><div class="label">Total utilidad</div><div class="value">${currency.format(summary.totalProfit)}</div></div>
    <div class="card"><div class="label">Total comisión</div><div class="value">${currency.format(summary.totalCommission)}</div></div>
  </div>

  <table>
    <thead>
      <tr>
        <th>Fecha</th>
        <th>Cliente</th>
        <th>Total vendido</th>
        <th>Utilidad</th>
        <th>Comisión</th>
      </tr>
    </thead>
    <tbody>
      $rows
    </tbody>
  </table>

  <script>
    window.onload = function() { window.print(); }
  </script>
</body>
</html>
''';

  final win = html.window.open('', '_blank');
  if (win is html.Window) {
    final dataUrl = Uri.dataFromString(
      htmlContent,
      mimeType: 'text/html',
      encoding: utf8,
    ).toString();
    win.location.href = dataUrl;
  }
}
