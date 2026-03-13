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
  DateTime? _desktopFrom;
  DateTime? _desktopTo;
  _DesktopPayrollStatus _desktopStatus = _DesktopPayrollStatus.all;

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

  bool _isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1240;

  List<PayrollHistoryItem> _applyDesktopFilters(
    List<PayrollHistoryItem> items,
  ) {
    final filtered =
        items
            .where((item) {
              if (_desktopStatus == _DesktopPayrollStatus.paid &&
                  !item.isPaid) {
                return false;
              }
              if (_desktopStatus == _DesktopPayrollStatus.pending &&
                  item.isPaid) {
                return false;
              }

              if (_desktopFrom != null) {
                final from = DateTime(
                  _desktopFrom!.year,
                  _desktopFrom!.month,
                  _desktopFrom!.day,
                );
                if (item.periodEnd.isBefore(from)) return false;
              }

              if (_desktopTo != null) {
                final to = DateTime(
                  _desktopTo!.year,
                  _desktopTo!.month,
                  _desktopTo!.day,
                  23,
                  59,
                  59,
                );
                if (item.periodStart.isAfter(to)) return false;
              }

              return true;
            })
            .toList(growable: false)
          ..sort((a, b) => b.periodEnd.compareTo(a.periodEnd));

    return filtered;
  }

  Future<void> _pickDesktopDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_desktopFrom ?? now.subtract(const Duration(days: 180)))
        : (_desktopTo ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isFrom) {
        _desktopFrom = picked;
        if (_desktopTo != null && _desktopTo!.isBefore(picked)) {
          _desktopTo = picked;
        }
      } else {
        _desktopTo = picked;
        if (_desktopFrom != null && picked.isBefore(_desktopFrom!)) {
          _desktopFrom = picked;
        }
      }
    });
  }

  void _resetDesktopFilters() {
    setState(() {
      _desktopFrom = null;
      _desktopTo = null;
      _desktopStatus = _DesktopPayrollStatus.all;
    });
  }

  Widget _buildDesktopBody(
    BuildContext context, {
    required PayrollHistoryItem? currentPeriod,
    required List<PayrollHistoryItem> historyItems,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final filteredHistory = _applyDesktopFilters(historyItems);
    final filteredPaid = filteredHistory
        .where((item) => item.isPaid)
        .toList(growable: false);
    final totalBenefits = filteredPaid.fold<double>(
      0,
      (sum, item) => sum + item.benefitsAmount,
    );
    final totalCommission = filteredPaid.fold<double>(
      0,
      (sum, item) => sum + item.commissionFromSales,
    );
    final totalNet = filteredPaid.fold<double>(
      0,
      (sum, item) => sum + item.netTotal,
    );
    final totalGross = filteredPaid.fold<double>(
      0,
      (sum, item) => sum + item.grossTotal,
    );
    final latestPaid = filteredPaid.isEmpty ? null : filteredPaid.first;
    final activeFilterCount = [
      if (_desktopFrom != null) 1,
      if (_desktopTo != null) 1,
      if (_desktopStatus != _DesktopPayrollStatus.all) 1,
    ].length;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompactDesktop = screenWidth < 1440;

    Widget heroActions({required bool compact}) {
      if (compact) {
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: currentPeriod == null
                    ? null
                    : () => _showPayrollDetailsDialog(currentPeriod),
                icon: const Icon(Icons.list_alt_outlined),
                label: const Text('Quincena actual'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        );
      }

      return SizedBox(
        width: 270,
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: currentPeriod == null
                    ? null
                    : () => _showPayrollDetailsDialog(currentPeriod),
                icon: const Icon(Icons.list_alt_outlined),
                label: const Text('Quincena actual'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final sidebar = _DesktopPaymentsSidebar(
      scheme: scheme,
      money: money,
      activeFilterCount: activeFilterCount,
      currentPeriod: currentPeriod,
      desktopStatus: _desktopStatus,
      desktopFrom: _desktopFrom,
      desktopTo: _desktopTo,
      totalBenefits: totalBenefits,
      totalCommission: totalCommission,
      totalGross: totalGross,
      filteredPaidCount: filteredPaid.length,
      latestPaid: latestPaid,
      error: _error,
      onStatusChanged: (status) => setState(() => _desktopStatus = status),
      onPickFrom: () => _pickDesktopDate(isFrom: true),
      onPickTo: () => _pickDesktopDate(isFrom: false),
      onResetFilters: _resetDesktopFilters,
      onDetails: currentPeriod == null
          ? null
          : () => _showPayrollDetailsDialog(currentPeriod),
      onPdf: currentPeriod == null
          ? null
          : () => _openPayrollPdfPreview(currentPeriod),
    );

    final content = _DesktopPaymentsContent(
      money: money,
      totalBenefits: totalBenefits,
      totalCommission: totalCommission,
      totalNet: totalNet,
      activeFilterCount: activeFilterCount,
      filteredHistory: filteredHistory,
      onTapDetails: _showPayrollDetailsDialog,
      onOpenPdf: _openPayrollPdfPreview,
    );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.08),
            scheme.primary.withValues(alpha: 0.02),
            scheme.surface,
          ],
        ),
      ),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0F3D91), Color(0xFF081A33)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.18),
                        blurRadius: 28,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: isCompactDesktop
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _DesktopPaymentsMetric(
                                  label: 'Beneficio acumulado',
                                  value: money.format(totalBenefits),
                                  icon: Icons.workspace_premium_outlined,
                                  accent: const Color(0xFFFDE68A),
                                  dark: true,
                                ),
                                _DesktopPaymentsMetric(
                                  label: 'Neto pagado',
                                  value: money.format(totalNet),
                                  icon: Icons.account_balance_wallet_outlined,
                                  accent: const Color(0xFF86EFAC),
                                  dark: true,
                                ),
                                _DesktopPaymentsMetric(
                                  label: 'Quincenas filtradas',
                                  value: filteredHistory.length.toString(),
                                  icon: Icons.calendar_month_outlined,
                                  accent: const Color(0xFF93C5FD),
                                  dark: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            heroActions(compact: true),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _DesktopPaymentsMetric(
                                    label: 'Beneficio acumulado',
                                    value: money.format(totalBenefits),
                                    icon: Icons.workspace_premium_outlined,
                                    accent: const Color(0xFFFDE68A),
                                    dark: true,
                                  ),
                                  _DesktopPaymentsMetric(
                                    label: 'Neto pagado',
                                    value: money.format(totalNet),
                                    icon: Icons.account_balance_wallet_outlined,
                                    accent: const Color(0xFF86EFAC),
                                    dark: true,
                                  ),
                                  _DesktopPaymentsMetric(
                                    label: 'Quincenas filtradas',
                                    value: filteredHistory.length.toString(),
                                    icon: Icons.calendar_month_outlined,
                                    accent: const Color(0xFF93C5FD),
                                    dark: true,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 18),
                            heroActions(compact: false),
                          ],
                        ),
                ),
                const SizedBox(height: 22),
                isCompactDesktop
                    ? Column(
                        children: [
                          sidebar,
                          const SizedBox(height: 16),
                          content,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 340, child: sidebar),
                          const SizedBox(width: 20),
                          Expanded(child: content),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;
    final isDesktop = _isDesktop(context);

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
        .where(
          (item) =>
              !hasCurrentPeriod || item.periodId != currentPeriod.periodId,
        )
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
                  onTap: () => context.push(Routes.profile),
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
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isDesktop
          ? RefreshIndicator(
              onRefresh: _load,
              child: _buildDesktopBody(
                context,
                currentPeriod: hasCurrentPeriod ? currentPeriod : null,
                historyItems: historyItems,
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
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
              pw.Text(
                'Extras: ${money.format(item.overtimeAmount + item.bonusesAmount)}',
              ),
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
    final net = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
    ).format(item.netTotal);
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
              _DetailRow(
                label: 'Estado',
                value: item.isPaid ? 'Pagado' : 'Pendiente',
              ),
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

enum _DesktopPayrollStatus {
  all('Todo'),
  paid('Pagado'),
  pending('Pendiente');

  const _DesktopPayrollStatus(this.label);
  final String label;
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
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
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
  const _CurrentPeriodCard({required this.item, this.onPdf, this.onDetails});

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
    final net = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
    ).format(item!.netTotal);

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
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
            Text(
              item!.periodTitle,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
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
        title: Text(
          item.periodTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(range),
        leading: Icon(
          item.isPaid ? Icons.verified_outlined : Icons.schedule_outlined,
          color: item.isPaid ? Colors.green : Colors.orange,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(net, style: const TextStyle(fontWeight: FontWeight.w700)),
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
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
  const _DetailRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

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
  const _PayrollPdfPreviewScreen({required this.title, required this.buildPdf});

  final String title;
  final Future<Uint8List> Function() buildPdf;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('PDF · $title')),
      body: PdfPreview(
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        build: (_) => buildPdf(),
      ),
    );
  }
}

class _DesktopPaymentsPanel extends StatelessWidget {
  const _DesktopPaymentsPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _DesktopPaymentsSidebar extends StatelessWidget {
  const _DesktopPaymentsSidebar({
    required this.scheme,
    required this.money,
    required this.activeFilterCount,
    required this.currentPeriod,
    required this.desktopStatus,
    required this.desktopFrom,
    required this.desktopTo,
    required this.totalBenefits,
    required this.totalCommission,
    required this.totalGross,
    required this.filteredPaidCount,
    required this.latestPaid,
    required this.error,
    required this.onStatusChanged,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onResetFilters,
    required this.onDetails,
    required this.onPdf,
  });

  final ColorScheme scheme;
  final NumberFormat money;
  final int activeFilterCount;
  final PayrollHistoryItem? currentPeriod;
  final _DesktopPayrollStatus desktopStatus;
  final DateTime? desktopFrom;
  final DateTime? desktopTo;
  final double totalBenefits;
  final double totalCommission;
  final double totalGross;
  final int filteredPaidCount;
  final PayrollHistoryItem? latestPaid;
  final String? error;
  final ValueChanged<_DesktopPayrollStatus> onStatusChanged;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onResetFilters;
  final VoidCallback? onDetails;
  final VoidCallback? onPdf;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DesktopPaymentsPanel(
          title: 'Filtros',
          subtitle: 'Refina pagos y beneficios por fecha y estado',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _DesktopPayrollStatus.values
                    .map(
                      (status) => _DesktopStatusChip(
                        label: status.label,
                        selected: desktopStatus == status,
                        onTap: () => onStatusChanged(status),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
              _DesktopFilterButton(
                label: 'Desde',
                value: desktopFrom == null
                    ? 'Cualquier fecha'
                    : DateFormat('dd/MM/yyyy').format(desktopFrom!),
                icon: Icons.event_available_outlined,
                onTap: onPickFrom,
              ),
              const SizedBox(height: 10),
              _DesktopFilterButton(
                label: 'Hasta',
                value: desktopTo == null
                    ? 'Cualquier fecha'
                    : DateFormat('dd/MM/yyyy').format(desktopTo!),
                icon: Icons.event_busy_outlined,
                onTap: onPickTo,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: activeFilterCount == 0 ? null : onResetFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Limpiar filtros'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DesktopPaymentsPanel(
          title: 'Resumen personal',
          subtitle: 'Lectura ejecutiva del historial visible',
          child: Column(
            children: [
              _DesktopInfoLine(
                label: 'Beneficio total alcanzado',
                value: money.format(totalBenefits),
                emphasized: true,
              ),
              _DesktopInfoLine(
                label: 'Comisión acumulada',
                value: money.format(totalCommission),
              ),
              _DesktopInfoLine(
                label: 'Total bruto',
                value: money.format(totalGross),
              ),
              _DesktopInfoLine(
                label: 'Pagos completados',
                value: filteredPaidCount.toString(),
              ),
              _DesktopInfoLine(
                label: 'Último pago',
                value: latestPaid == null
                    ? 'Sin pagos'
                    : DateFormat('dd/MM/yyyy').format(latestPaid!.periodEnd),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DesktopPaymentsPanel(
          title: 'Quincena en curso',
          subtitle: currentPeriod == null
              ? 'No hay una quincena abierta ahora mismo'
              : currentPeriod!.periodTitle,
          child: _DesktopCurrentPeriodCard(
            item: currentPeriod,
            onDetails: onDetails,
            onPdf: onPdf,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: scheme.error.withValues(alpha: 0.24)),
            ),
            child: Text(
              error!,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ],
    );
  }
}

class _DesktopPaymentsContent extends StatelessWidget {
  const _DesktopPaymentsContent({
    required this.money,
    required this.totalBenefits,
    required this.totalCommission,
    required this.totalNet,
    required this.activeFilterCount,
    required this.filteredHistory,
    required this.onTapDetails,
    required this.onOpenPdf,
  });

  final NumberFormat money;
  final double totalBenefits;
  final double totalCommission;
  final double totalNet;
  final int activeFilterCount;
  final List<PayrollHistoryItem> filteredHistory;
  final ValueChanged<PayrollHistoryItem> onTapDetails;
  final ValueChanged<PayrollHistoryItem> onOpenPdf;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 920;
            final cardWidth = isNarrow
                ? constraints.maxWidth
                : (constraints.maxWidth - 28) / 3;

            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _DesktopPaymentsKpiCard(
                    title: 'Beneficio filtrado',
                    value: money.format(totalBenefits),
                    subtitle: 'Beneficios visibles dentro del rango actual',
                    icon: Icons.verified_outlined,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _DesktopPaymentsKpiCard(
                    title: 'Comisión por ventas',
                    value: money.format(totalCommission),
                    subtitle: 'Comisión acumulada en el historial filtrado',
                    icon: Icons.auto_graph_outlined,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _DesktopPaymentsKpiCard(
                    title: 'Neto recibido',
                    value: money.format(totalNet),
                    subtitle: 'Pagos netos ya liquidados',
                    icon: Icons.payments_outlined,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _DesktopPaymentsPanel(
          title: 'Historial de pagos',
          subtitle: activeFilterCount == 0
              ? 'Vista completa de tus quincenas registradas'
              : 'Resultados refinados por el filtro actual',
          child: filteredHistory.isEmpty
              ? const _DesktopPaymentsEmptyState()
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 920),
                    child: Column(
                      children: [
                        const _DesktopPaymentsHistoryHeader(),
                        ...filteredHistory.map(
                          (item) => _DesktopPaymentsHistoryRow(
                            item: item,
                            onTap: () => onTapDetails(item),
                            onPdf: () => onOpenPdf(item),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DesktopPaymentsMetric extends StatelessWidget {
  const _DesktopPaymentsMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.dark = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = dark ? Colors.white : theme.colorScheme.onSurface;
    final muted = dark
        ? Colors.white.withValues(alpha: 0.72)
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      constraints: const BoxConstraints(minWidth: 170, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.10)
            : accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.14)
              : accent.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: dark ? 0.18 : 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: dark ? Colors.white : accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopStatusChip extends StatelessWidget {
  const _DesktopStatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? scheme.onPrimary : scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DesktopFilterButton extends StatelessWidget {
  const _DesktopFilterButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopInfoLine extends StatelessWidget {
  const _DesktopInfoLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
              color: emphasized ? scheme.primary : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopCurrentPeriodCard extends StatelessWidget {
  const _DesktopCurrentPeriodCard({
    required this.item,
    required this.onDetails,
    required this.onPdf,
  });

  final PayrollHistoryItem? item;
  final VoidCallback? onDetails;
  final VoidCallback? onPdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');

    if (item == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
        child: const Text(
          'No tienes una quincena abierta ahora mismo.',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }

    final range =
        '${DateFormat('dd/MM/yyyy').format(item!.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item!.periodEnd)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item!.periodTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(range, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          _DesktopInfoLine(
            label: 'Neto estimado',
            value: money.format(item!.netTotal),
            emphasized: true,
          ),
          _DesktopInfoLine(
            label: 'Beneficios',
            value: money.format(item!.benefitsAmount),
          ),
          _DesktopInfoLine(
            label: 'Comisión',
            value: money.format(item!.commissionFromSales),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDetails,
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Detalles'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopPaymentsKpiCard extends StatelessWidget {
  const _DesktopPaymentsKpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary, size: 20),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _DesktopPaymentsHistoryHeader extends StatelessWidget {
  const _DesktopPaymentsHistoryHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          const SizedBox(width: 36),
          Expanded(flex: 3, child: Text('Quincena', style: style)),
          const SizedBox(width: 14),
          Expanded(flex: 2, child: Text('Rango', style: style)),
          const SizedBox(width: 14),
          SizedBox(
            width: 130,
            child: Text('Beneficios', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 130,
            child: Text('Comisión', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 140,
            child: Text('Neto', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 84,
            child: Text('Estado', style: style, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 114),
        ],
      ),
    );
  }
}

class _DesktopPaymentsHistoryRow extends StatelessWidget {
  const _DesktopPaymentsHistoryRow({
    required this.item,
    required this.onTap,
    required this.onPdf,
  });

  final PayrollHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.periodStart)} - ${DateFormat('dd/MM/yyyy').format(item.periodEnd)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Row(
        children: [
          Icon(
            item.isPaid ? Icons.verified_outlined : Icons.schedule_outlined,
            color: item.isPaid
                ? const Color(0xFF15803D)
                : const Color(0xFFEA580C),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              item.periodTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: Text(
              range,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 130,
            child: Text(
              money.format(item.benefitsAmount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 130,
            child: Text(
              money.format(item.commissionFromSales),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 140,
            child: Text(
              money.format(item.netTotal),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 84,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: item.isPaid
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFFEDD5),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              item.isPaid ? 'Pagado' : 'Pendiente',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: item.isPaid
                    ? const Color(0xFF166534)
                    : const Color(0xFF9A3412),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Ver detalles',
            onPressed: onTap,
            icon: const Icon(Icons.visibility_outlined),
          ),
          IconButton(
            tooltip: 'PDF',
            onPressed: onPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
    );
  }
}

class _DesktopPaymentsEmptyState extends StatelessWidget {
  const _DesktopPaymentsEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 44, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            'No hay resultados con este filtro',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Ajusta las fechas o el estado para volver a mostrar tus quincenas registradas.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
