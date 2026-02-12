import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import '../ventas/presentation/cierres_view.dart';
import 'models/close_models.dart';
import 'widgets/app_card.dart';
import 'widgets/kpi_chip.dart';
import 'widgets/max_width_container.dart';
import 'widgets/section_title.dart';
import 'widgets/status_badge.dart';

class ContabilidadScreen extends ConsumerStatefulWidget {
  const ContabilidadScreen({super.key});

  @override
  ConsumerState<ContabilidadScreen> createState() => _ContabilidadScreenState();
}

class _ContabilidadScreenState extends ConsumerState<ContabilidadScreen> {
  DateTime _date = DateTime.now();

  String _formatMoney(double v) => '\$${v.toStringAsFixed(2)}';
  String _formatDate(DateTime d) => DateFormat('EEEE, dd MMM yyyy', 'es').format(d);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final role = user?.role ?? '';
    final isAdmin = role == 'ADMIN';

    // TODO: Conectar a backend. Por ahora demo para construir UI premium.
    final closes = <CloseSummary>[
      const CloseSummary(
        type: CloseType.capsulas,
        status: 'pending',
        cash: 0,
        transfer: 0,
        card: 0,
        expenses: 0,
        cashDelivered: 0,
      ),
      const CloseSummary(
        type: CloseType.pos,
        status: 'draft',
        cash: 4500,
        transfer: 8200,
        card: 6300,
        expenses: 1200,
        cashDelivered: 3000,
      ),
      const CloseSummary(
        type: CloseType.tienda,
        status: 'closed',
        cash: 9800,
        transfer: 15100,
        card: 7200,
        expenses: 950,
        cashDelivered: 8850,
      ),
    ];

    final totalCash = closes.fold<double>(0, (s, c) => s + c.cash);
    final totalTransfer = closes.fold<double>(0, (s, c) => s + c.transfer);
    final totalCard = closes.fold<double>(0, (s, c) => s + c.card);
    final totalExpenses = closes.fold<double>(0, (s, c) => s + c.expenses);
    final totalDelivered = closes.fold<double>(0, (s, c) => s + c.cashDelivered);

    final cashOnHand = totalCash - totalExpenses - totalDelivered;
    final depositRequired = cashOnHand >= 20000;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cierres del día'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CierresView())),
            child: const Text('Ver todos', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      drawer: AppDrawer(currentUser: user),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: MaxWidthContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: AppCard(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Fecha',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatDate(_date),
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _date,
                                    firstDate: DateTime(_date.year - 2),
                                    lastDate: DateTime(_date.year + 2),
                                  );
                                  if (picked != null) setState(() => _date = picked);
                                },
                                child: const Text('Cambiar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            // TODO: Navegar a AdminDashboard
                          },
                          icon: const Icon(Icons.analytics_outlined),
                          label: const Text('Admin'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (depositRequired)
                    AppCard(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'DEPÓSITO OBLIGATORIO · Efectivo en caja ${_formatMoney(cashOnHand)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                          FilledButton(
                            onPressed: () {
                              // TODO: Navegar a Deposits
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.error,
                              foregroundColor: Theme.of(context).colorScheme.onError,
                            ),
                            child: const Text('Registrar depósito'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  const SectionTitle(title: 'Resumen rápido del día'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      KpiChip(label: 'Efectivo', value: _formatMoney(totalCash), icon: Icons.payments_outlined),
                      KpiChip(label: 'Transferencia', value: _formatMoney(totalTransfer), icon: Icons.swap_horiz),
                      KpiChip(label: 'Tarjeta', value: _formatMoney(totalCard), icon: Icons.credit_card),
                      KpiChip(
                        label: 'Gastos',
                        value: _formatMoney(totalExpenses),
                        icon: Icons.receipt_long,
                        color: AppTheme.warningColor,
                      ),
                      KpiChip(label: 'Efectivo entregado', value: _formatMoney(totalDelivered), icon: Icons.handshake_outlined),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const SectionTitle(title: 'Cierres'),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 24),
            sliver: SliverToBoxAdapter(
              child: MaxWidthContainer(
                child: Column(
                  children: closes
                      .map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CloseCard(
                            close: c,
                            onOpen: () {
                              // TODO: Abrir/Continuar/Ver según status
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseCard extends StatelessWidget {
  final CloseSummary close;
  final VoidCallback onOpen;

  const _CloseCard({required this.close, required this.onOpen});

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  CloseStatus _mapStatus() {
    if (close.difference.abs() > 0.009) return CloseStatus.diff;
    switch (close.status) {
      case 'closed':
        return CloseStatus.closed;
      case 'draft':
        return CloseStatus.draft;
      case 'pending':
      default:
        return CloseStatus.pending;
    }
  }

  String _primaryActionLabel() {
    switch (close.status) {
      case 'closed':
        return 'Ver';
      case 'draft':
        return 'Continuar';
      case 'pending':
      default:
        return 'Abrir';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diff = close.difference;
    final hasDiff = diff.abs() > 0.009;
    final diffColor = hasDiff ? AppTheme.errorColor : theme.colorScheme.onSurfaceVariant;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  close.type.label,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              StatusBadge(status: _mapStatus()),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              KpiChip(label: 'Efectivo', value: _money(close.cash), icon: Icons.payments_outlined),
              KpiChip(label: 'Transfer.', value: _money(close.transfer), icon: Icons.swap_horiz),
              KpiChip(label: 'Tarjeta', value: _money(close.card), icon: Icons.credit_card),
              KpiChip(label: 'Gastos', value: _money(close.expenses), icon: Icons.receipt_long, color: AppTheme.warningColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Efectivo entregado',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              Text(
                _money(close.cashDelivered),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Diferencia',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              Text(
                '${diff >= 0 ? '+' : ''}${_money(diff)}',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: diffColor),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onOpen,
              child: Text(_primaryActionLabel()),
            ),
          ),
        ],
      ),
    );
  }
}
