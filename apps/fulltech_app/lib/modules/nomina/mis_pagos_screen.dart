import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/string_utils.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'data/nomina_repository.dart';
import 'nomina_models.dart';

class MisPagosScreen extends ConsumerStatefulWidget {
  const MisPagosScreen({super.key});

  @override
  ConsumerState<MisPagosScreen> createState() => _MisPagosScreenState();
}

class _MisPagosScreenState extends ConsumerState<MisPagosScreen> {
  static const String _companyName = 'FULLTECH, SRL';
  static const String _companyRnc = '133080209';
  static const String _companyPhone = '8295344286';

  bool _loading = true;
  String? _error;
  List<PayrollHistoryItem> _items = const [];
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _load();
    _autoRefresh = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_loading) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ref
          .read(nominaRepositoryProvider)
          .listMyPayrollHistory();
      if (!mounted) return;
      setState(() {
        _items = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar Mis Pagos: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;

    final paidItems = _items
        .where((item) => item.periodStatus.toUpperCase() == 'PAID')
        .toList();
    final currentPeriod = _items.firstWhere(
      (item) => item.periodStatus.toUpperCase() == 'OPEN',
      orElse: () => _items.firstWhere(
        (item) => item.periodStatus.toUpperCase() == 'DRAFT',
        orElse: () => PayrollHistoryItem(
          entryId: '',
          periodId: '',
          periodTitle: '',
          periodStart: DateTime.fromMillisecondsSinceEpoch(0),
          periodEnd: DateTime.fromMillisecondsSinceEpoch(0),
          periodStatus: '',
          baseSalary: 0,
          commissionFromSales: 0,
          overtimeAmount: 0,
          bonusesAmount: 0,
          deductionsAmount: 0,
          benefitsAmount: 0,
          grossTotal: 0,
          netTotal: 0,
        ),
      ),
    );
    final hasCurrentPeriod = currentPeriod.periodId.isNotEmpty;
    final historyItems = _items
        .where((item) => !hasCurrentPeriod || item.periodId != currentPeriod.periodId)
        .toList();

    final totalHistorico = paidItems.fold<double>(
      0,
      (sum, item) => sum + item.netTotal,
    );
    final thisYear = DateTime.now().year;
    final totalAnio = paidItems
        .where((item) => item.periodEnd.year == thisYear)
        .fold<double>(0, (sum, item) => sum + item.netTotal);
    final nominasPagadas = paidItems.length.toDouble();

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Mis Pagos',
        showLogo: false,
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        trailing: currentUser == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => context.push(Routes.user),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    backgroundImage:
                        (currentUser.fotoPersonalUrl ?? '').trim().isEmpty
                            ? null
                            : NetworkImage(currentUser.fotoPersonalUrl!),
                    child: (currentUser.fotoPersonalUrl ?? '').trim().isEmpty
                        ? Text(
                            getInitials(currentUser.nombreCompleto),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
      ),
      drawer: AppDrawer(currentUser: currentUser),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SummaryStrip(
                    totalHistorico: totalHistorico,
                    totalAnio: totalAnio,
                    nominasPagadas: nominasPagadas,
                  ),
                  const SizedBox(height: 10),
                  _CurrentPeriodCard(
                    item: hasCurrentPeriod ? currentPeriod : null,
                    onPdf: hasCurrentPeriod
                      ? () => _openPayrollPdfPreview(currentPeriod)
                      : null,
                    onDetails: hasCurrentPeriod
                      ? () => _showPayrollDetailsDialog(currentPeriod)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Historial de quincenas',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (historyItems.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 36,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Aún no tienes pagos registrados',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...historyItems.map(
                      (item) => _HistoryTile(
                        item: item,
                        onTap: () => _showPayrollDetailsDialog(item),
                        onPdf: () => _openPayrollPdfPreview(item),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<Uint8List> _buildPayrollPdf(PayrollHistoryItem item) async {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item.periodEnd)}';
    final currentUser = ref.read(authStateProvider).user;
    final fallbackName = (currentUser?.nombreCompleto ?? '').trim().isNotEmpty
      ? currentUser!.nombreCompleto.trim()
      : _nameFromEmail(currentUser?.email ?? '');
    final employeeName = item.employeeName.trim().isNotEmpty
      ? item.employeeName.trim()
      : fallbackName;
    final employeeRole = _roleLabel(currentUser?.role ?? '');

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      _companyName,
                      style: pw.TextStyle(
                        fontSize: 17,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text('RNC: $_companyRnc'),
                    pw.Text('Tel: $_companyPhone'),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'COMPROBANTE DE PAGO DE NÓMINA',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 6),
              pw.Text('Empleado: $employeeName'),
              pw.Text('Rol: $employeeRole'),
              pw.Text('Quincena: ${item.periodTitle}'),
              pw.Text('Rango: $range'),
              pw.Text('Estado: ${item.isPaid ? 'Pagado' : 'Pendiente'}'),
              pw.SizedBox(height: 14),
              pw.Text('Salario quincenal: ${money.format(item.baseSalary)}'),
              pw.Text('Comisión: ${money.format(item.commissionFromSales)}'),
              pw.Text('Extras: ${money.format(item.overtimeAmount + item.bonusesAmount)}'),
              pw.Text('Beneficios: ${money.format(item.benefitsAmount)}'),
              pw.Text('Deducciones: ${money.format(item.deductionsAmount)}'),
              pw.Divider(),
              pw.Text(
                'Neto a pagar: ${money.format(item.netTotal)}',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return doc.save();
  }

  String _roleLabel(String rawRole) {
    switch (rawRole.toUpperCase()) {
      case 'ADMIN':
        return 'Administrador';
      case 'ASISTENTE':
        return 'Asistente';
      case 'MARKETING':
        return 'Marketing';
      case 'VENDEDOR':
        return 'Vendedor';
      case 'TECNICO':
        return 'Técnico';
      default:
        return rawRole.isEmpty ? 'N/D' : rawRole;
    }
  }

  String _nameFromEmail(String email) {
    final clean = email.trim();
    if (clean.isEmpty) return 'N/D';
    final username = clean.split('@').first.trim();
    if (username.isEmpty) return clean;
    final words = username
        .replaceAll('.', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.trim().isNotEmpty)
        .toList();
    if (words.isEmpty) return username;
    return words
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  Future<void> _openPayrollPdfPreview(PayrollHistoryItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PayrollPdfPreviewScreen(
          title: item.periodTitle,
          buildPdf: () => _buildPayrollPdf(item),
        ),
      ),
    );
  }

  Future<void> _showPayrollDetailsDialog(PayrollHistoryItem item) async {
    final net = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(item.netTotal);
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item.periodEnd)}';

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.periodTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(range),
              const SizedBox(height: 8),
              _DetailRow(label: 'Estado', value: item.isPaid ? 'Pagado' : 'Pendiente'),
              _DetailRow(label: 'Salario base', value: item.baseSalary),
              _DetailRow(label: 'Comisión', value: item.commissionFromSales),
              _DetailRow(
                label: 'Extras',
                value: item.overtimeAmount + item.bonusesAmount,
              ),
              _DetailRow(label: 'Beneficios', value: item.benefitsAmount),
              _DetailRow(label: 'Deducciones', value: item.deductionsAmount),
              const Divider(height: 20),
              _DetailRow(label: 'Neto quincena', value: net, bold: true),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _openPayrollPdfPreview(item),
            icon: const Icon(Icons.download_outlined),
            label: const Text('PDF'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.totalHistorico,
    required this.totalAnio,
    required this.nominasPagadas,
  });

  final double totalHistorico;
  final double totalAnio;
  final double nominasPagadas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      child: SizedBox(
        height: 72,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          children: [
            _MetricPill(
              label: 'Histórico pagado',
              value: totalHistorico,
              color: theme.colorScheme.primary,
            ),
            _MetricPill(
              label: 'Pagado este año',
              value: totalAnio,
              color: theme.colorScheme.tertiary,
            ),
            _MetricPill(
              label: 'Nóminas pagadas',
              valueText: nominasPagadas.toInt().toString(),
              color: theme.colorScheme.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    this.value,
    this.valueText,
    required this.color,
  });

  final String label;
  final double? value;
  final String? valueText;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(
            valueText ?? format.format(value ?? 0),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _CurrentPeriodCard extends StatelessWidget {
  const _CurrentPeriodCard({
    required this.item,
    this.onPdf,
    this.onDetails,
  });

  final PayrollHistoryItem? item;
  final VoidCallback? onPdf;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (item == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.event_busy_outlined, color: theme.colorScheme.outline),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'No hay quincena en curso abierta',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final range =
        '${DateFormat('dd/MM/yyyy').format(item!.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item!.periodEnd)}';
    final net = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(item!.netTotal);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Quincena en curso',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: const Text('Abierta'),
                  backgroundColor: Colors.orange.withValues(alpha: 0.15),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(item!.periodTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(range, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Neto estimado: $net',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onDetails,
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Detalles'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.item,
    required this.onTap,
    required this.onPdf,
  });

  final PayrollHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item.periodEnd)}';
    final net = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
    ).format(item.netTotal);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        title: Text(item.periodTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(range),
        leading: Icon(
          item.isPaid ? Icons.verified_outlined : Icons.schedule_outlined,
          color: item.isPaid ? Colors.green : Colors.orange,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              net,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              item.isPaid ? 'Pagado' : 'Pendiente',
              style: TextStyle(
                fontSize: 12,
                color: item.isPaid ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 2),
            InkWell(
              onTap: onPdf,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  'PDF',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.bold = false});

  final String label;
  final Object value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final text = value is num
        ? NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value)
        : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            text,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollPdfPreviewScreen extends StatelessWidget {
  const _PayrollPdfPreviewScreen({
    required this.title,
    required this.buildPdf,
  });

  final String title;
  final Future<Uint8List> Function() buildPdf;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PDF · $title'),
      ),
      body: PdfPreview(
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        build: (_) => buildPdf(),
      ),
    );
  }
}
