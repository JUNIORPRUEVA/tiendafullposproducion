import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/role_permissions.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/models/close_model.dart';
import 'data/contabilidad_repository.dart';
import 'models/fiscal_invoice_model.dart';
import 'models/payable_models.dart';

final accountingDesktopOverviewProvider =
    FutureProvider<_AccountingDesktopOverview>((ref) async {
      final repo = ref.watch(contabilidadRepositoryProvider);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monthStart = DateTime(now.year, now.month, 1);
      final nextWeek = today.add(const Duration(days: 7));

      final results = await Future.wait<dynamic>([
        repo.listCloses(from: monthStart, to: today),
        repo.listFiscalInvoices(from: monthStart, to: today),
        repo.listPayableServices(active: true),
        repo.listPayablePayments(from: today, to: today),
      ]);

      final closes = results[0] as List<CloseModel>;
      final invoices = results[1] as List<FiscalInvoiceModel>;
      final payables = results[2] as List<PayableService>;
      final paymentsToday = results[3] as List<PayablePayment>;

      final pendingCloses = closes
          .where((close) => close.status != 'closed')
          .length;
      final saleInvoices = invoices
          .where((invoice) => invoice.kind == FiscalInvoiceKind.sale)
          .length;
      final purchaseInvoices = invoices.length - saleInvoices;
      final dueSoon = payables
          .where(
            (service) =>
                !service.nextDueDate.isBefore(today) &&
                !service.nextDueDate.isAfter(nextWeek),
          )
          .length;
      final overdue = payables
          .where((service) => service.nextDueDate.isBefore(today))
          .length;
      final todayMovements =
          closes.where((close) => _isSameDate(close.date, today)).length +
          invoices
              .where((invoice) => _isSameDate(invoice.invoiceDate, today))
              .length +
          paymentsToday.length;
      final paidTodayAmount = paymentsToday.fold<double>(
        0,
        (sum, payment) => sum + payment.amount,
      );

      return _AccountingDesktopOverview(
        monthLabel: DateFormat('MMMM yyyy', 'es_DO').format(today),
        closesCount: closes.length,
        pendingClosesCount: pendingCloses,
        saleInvoicesCount: saleInvoices,
        purchaseInvoicesCount: purchaseInvoices,
        activePayablesCount: payables.length,
        dueSoonCount: dueSoon,
        overdueCount: overdue,
        todayMovementsCount: todayMovements,
        paidTodayAmount: paidTodayAmount,
      );
    });

bool _isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

class ContabilidadScreen extends ConsumerWidget {
  const ContabilidadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final canUseModule = canAccessContabilidadByRole(user?.role);
    final isDesktop = MediaQuery.sizeOf(context).width >= 1000;

    if (!canUseModule) {
      return Scaffold(
        appBar: const CustomAppBar(
          title: 'Contabilidad',
          showLogo: false,
          showDepartmentLabel: false,
        ),
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Este módulo está disponible solo para usuarios autorizados.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Contabilidad',
        showLogo: false,
        showDepartmentLabel: false,
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      backgroundColor: isDesktop
          ? const Color(0xFFF3F6FB)
          : AppTheme.primaryColor,
      body: isDesktop
          ? const _AccountingDesktopPage()
          : const _AccountingMobilePage(),
    );
  }
}

class _AccountingMobilePage extends StatelessWidget {
  const _AccountingMobilePage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionButton(
                label: 'Cierres diarios',
                onPressed: () => context.go(Routes.contabilidadCierresDiarios),
              ),
              const SizedBox(height: 14),
              _SectionButton(
                label: 'Factura fiscal',
                onPressed: () => context.go(Routes.contabilidadFacturaFiscal),
              ),
              const SizedBox(height: 14),
              _SectionButton(
                label: 'Pagos pendientes',
                onPressed: () => context.go(Routes.contabilidadPagosPendientes),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountingDesktopPage extends ConsumerWidget {
  const _AccountingDesktopPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(accountingDesktopOverviewProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = DateTime.now();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.primaryColor.withValues(alpha: 0.09),
            const Color(0xFFF3F6FB),
            const Color(0xFFF8FAFC),
          ],
        ),
      ),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AccountingHeaderSection(
                  currentDateLabel: DateFormat(
                    'EEE, dd MMM yyyy',
                    'es_DO',
                  ).format(today),
                  overviewAsync: overviewAsync,
                ),
                const SizedBox(height: 22),
                _AccountingSummaryCards(overviewAsync: overviewAsync),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1220;
                    if (!wide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AccountingModulesGrid(overviewAsync: overviewAsync),
                          const SizedBox(height: 20),
                          _AccountingQuickOverview(
                            overviewAsync: overviewAsync,
                            panelColor: scheme.surface,
                          ),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 9,
                          child: _AccountingModulesGrid(
                            overviewAsync: overviewAsync,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 4,
                          child: _AccountingQuickOverview(
                            overviewAsync: overviewAsync,
                            panelColor: scheme.surface,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountingHeaderSection extends StatelessWidget {
  const _AccountingHeaderSection({
    required this.currentDateLabel,
    required this.overviewAsync,
  });

  final String currentDateLabel;
  final AsyncValue<_AccountingDesktopOverview> overviewAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = overviewAsync.value;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10316B), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 32,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 1040;
          final monthLabel =
              overviewAsync.value?.monthLabel ?? 'Periodo actual';
          final statusLabel = overviewAsync.maybeWhen(
            data: (data) => data.overdueCount > 0
                ? 'Requiere atencion'
                : data.pendingClosesCount > 0
                ? 'Seguimiento activo'
                : 'Operacion estable',
            orElse: () => 'Sincronizando',
          );

          Widget chip({required String text}) {
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.90),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          }

          final modulesText = 'Módulos: 3';
          final movementsText =
              'Movimientos hoy: ${summary?.todayMovementsCount.toString() ?? '--'}';

          final chips = Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              chip(text: 'Estado: $statusLabel'),
              chip(text: 'Período: $monthLabel'),
              chip(text: modulesText),
              chip(text: movementsText),
            ],
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                chip(text: currentDateLabel),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: chips),
              ],
            );
          }

          return Row(
            children: [
              chip(text: currentDateLabel),
              const SizedBox(width: 14),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: chips),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AccountingSummaryCards extends StatelessWidget {
  const _AccountingSummaryCards({required this.overviewAsync});

  final AsyncValue<_AccountingDesktopOverview> overviewAsync;

  @override
  Widget build(BuildContext context) {
    final summary = overviewAsync.value;
    final cards = [
      _SummaryCardData(
        title: 'Cierres pendientes',
        value: summary?.pendingClosesCount.toString() ?? '--',
        icon: Icons.point_of_sale_outlined,
        accent: const Color(0xFF0F766E),
      ),
      _SummaryCardData(
        title: 'Facturas fiscales',
        value: summary?.saleInvoicesCount.toString() ?? '--',
        icon: Icons.receipt_long_outlined,
        accent: const Color(0xFF7C3AED),
      ),
      _SummaryCardData(
        title: 'Pagos pendientes',
        value: summary?.activePayablesCount.toString() ?? '--',
        icon: Icons.pending_actions_outlined,
        accent: const Color(0xFFEA580C),
      ),
      _SummaryCardData(
        title: 'Movimientos del día',
        value: summary?.todayMovementsCount.toString() ?? '--',
        icon: Icons.auto_graph_outlined,
        accent: const Color(0xFF1D4ED8),
      ),
      _SummaryCardData(
        title: 'Estado del período',
        value: summary == null
            ? 'Sincronizando'
            : summary.overdueCount > 0
            ? 'Alertas'
            : 'Estable',
        icon: Icons.shield_outlined,
        accent: const Color(0xFF2563EB),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 1380
            ? 5
            : width > 1120
            ? 3
            : width > 760
            ? 2
            : 1;
        final aspectRatio = crossAxisCount == 1
            ? 4.6
            : crossAxisCount == 2
            ? 3.2
            : crossAxisCount == 3
            ? 2.6
            : 2.35;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) {
            return _AccountingSummaryCard(data: cards[index]);
          },
        );
      },
    );
  }
}

class _AccountingModulesGrid extends StatelessWidget {
  const _AccountingModulesGrid({required this.overviewAsync});

  final AsyncValue<_AccountingDesktopOverview> overviewAsync;

  @override
  Widget build(BuildContext context) {
    final summary = overviewAsync.value;
    final modules = [
      _AccountingModuleData(
        title: 'Cierres diarios',
        description:
            'Gestiona cierres de caja, revisa estados y controla el movimiento diario con estructura operativa clara.',
        status: summary == null
            ? 'Panel listo'
            : '${summary.pendingClosesCount} pendientes por revisar',
        icon: Icons.inventory_2_outlined,
        accent: const Color(0xFF0F766E),
        route: Routes.contabilidadCierresDiarios,
      ),
      _AccountingModuleData(
        title: 'Factura fiscal',
        description:
            'Administra comprobantes y procesos relacionados con la facturación fiscal con una vista preparada para auditoría.',
        status: summary == null
            ? 'Sincronización preparada'
            : '${summary.saleInvoicesCount} de venta emitidas este periodo',
        icon: Icons.request_quote_outlined,
        accent: const Color(0xFF7C3AED),
        route: Routes.contabilidadFacturaFiscal,
      ),
      _AccountingModuleData(
        title: 'Pagos pendientes',
        description:
            'Consulta y da seguimiento a cobros, compromisos y balances pendientes con foco en vencimientos.',
        status: summary == null
            ? 'Monitoreo habilitable'
            : '${summary.activePayablesCount} servicios activos y ${summary.dueSoonCount} próximos a vencer',
        icon: Icons.account_balance_wallet_outlined,
        accent: const Color(0xFFEA580C),
        route: Routes.contabilidadPagosPendientes,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final inline = constraints.maxWidth >= 820;
              final title = Text(
                'Módulos contables',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              );
              final description = Text(
                'Accesos administrativos preparados para crecer hacia reportes, cuentas por cobrar, impuestos y más procesos contables.',
                maxLines: inline ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              );

              if (!inline) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 4), description],
                );
              }

              return Row(
                children: [
                  title,
                  const SizedBox(width: 14),
                  Expanded(child: description),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width > 1180
                  ? 3
                  : width > 760
                  ? 2
                  : 1;
              final aspectRatio = crossAxisCount == 1
                  ? 4.6
                  : crossAxisCount == 2
                  ? 2.35
                  : 1.85;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: modules.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: aspectRatio,
                ),
                itemBuilder: (context, index) {
                  return _AccountingModuleCard(data: modules[index]);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AccountingQuickOverview extends StatelessWidget {
  const _AccountingQuickOverview({
    required this.overviewAsync,
    required this.panelColor,
  });

  final AsyncValue<_AccountingDesktopOverview> overviewAsync;
  final Color panelColor;

  @override
  Widget build(BuildContext context) {
    final summary = overviewAsync.value;
    final nextModules = [
      'Gastos',
      'Ingresos',
      'Reportes',
      'Impuestos',
      'Arqueos',
      'Resumen mensual',
      'Exportaciones',
      'Historial contable',
    ];

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.8),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x100F172A),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Panorama rápido',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Sección lateral para seguimiento ejecutivo del periodo y próximos focos administrativos.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _QuickOverviewItem(
                label: 'Cierres del mes',
                value: summary?.closesCount.toString() ?? '--',
              ),
              _QuickOverviewItem(
                label: 'Servicios vencidos',
                value: summary?.overdueCount.toString() ?? '--',
              ),
              _QuickOverviewItem(
                label: 'Por vencer esta semana',
                value: summary?.dueSoonCount.toString() ?? '--',
              ),
              _QuickOverviewItem(
                label: 'Pagado hoy',
                value: summary == null ? '--' : _money(summary.paidTodayAmount),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE8F0FF), Color(0xFFF8FBFF)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFCFE0FF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Base lista para crecer',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Esta vista ya queda estructurada para sumar más módulos contables sin rehacer la experiencia desktop.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF334155),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: nextModules
                    .map((item) => _FutureModuleChip(label: item))
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionButton extends StatelessWidget {
  const _SectionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.primaryColor,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _AccountingSummaryCard extends StatelessWidget {
  const _AccountingSummaryCard({required this.data});

  final _SummaryCardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: data.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(data.icon, color: data.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        data.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.7,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
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

class _AccountingModuleCard extends StatefulWidget {
  const _AccountingModuleCard({required this.data});

  final _AccountingModuleData data;

  @override
  State<_AccountingModuleCard> createState() => _AccountingModuleCardState();
}

class _AccountingModuleCardState extends State<_AccountingModuleCard> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hovered == value) return;
      setState(() => _hovered = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -4.0 : 0.0, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.go(data.route),
            borderRadius: BorderRadius.circular(26),
            child: Ink(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    data.accent.withValues(alpha: _hovered ? 0.16 : 0.10),
                    Colors.white,
                  ],
                ),
                border: Border.all(
                  color: data.accent.withValues(alpha: _hovered ? 0.26 : 0.18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: data.accent.withValues(
                      alpha: _hovered ? 0.18 : 0.08,
                    ),
                    blurRadius: _hovered ? 22 : 14,
                    offset: Offset(0, _hovered ? 14 : 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: data.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(data.icon, color: data.accent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                data.status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: data.accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF334155),
                      height: 1.4,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Abrir módulo',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: data.accent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _hovered ? Icons.arrow_outward : Icons.arrow_forward,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickOverviewItem extends StatelessWidget {
  const _QuickOverviewItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _FutureModuleChip extends StatelessWidget {
  const _FutureModuleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD7E3FF)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: const Color(0xFF1D4ED8),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SummaryCardData {
  const _SummaryCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
}

class _AccountingModuleData {
  const _AccountingModuleData({
    required this.title,
    required this.description,
    required this.status,
    required this.icon,
    required this.accent,
    required this.route,
  });

  final String title;
  final String description;
  final String status;
  final IconData icon;
  final Color accent;
  final String route;
}

class _AccountingDesktopOverview {
  const _AccountingDesktopOverview({
    required this.monthLabel,
    required this.closesCount,
    required this.pendingClosesCount,
    required this.saleInvoicesCount,
    required this.purchaseInvoicesCount,
    required this.activePayablesCount,
    required this.dueSoonCount,
    required this.overdueCount,
    required this.todayMovementsCount,
    required this.paidTodayAmount,
  });

  final String monthLabel;
  final int closesCount;
  final int pendingClosesCount;
  final int saleInvoicesCount;
  final int purchaseInvoicesCount;
  final int activePayablesCount;
  final int dueSoonCount;
  final int overdueCount;
  final int todayMovementsCount;
  final double paidTodayAmount;
}

String _money(double value) {
  return NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value);
}
