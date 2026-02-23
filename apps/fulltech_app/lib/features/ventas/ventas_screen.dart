import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';
import 'presentation/admin_sales_dashboard_view.dart';
import 'presentation/clients_view.dart';
import 'presentation/sale_builder_view.dart';
import 'presentation/sales_history_view.dart';

class VentasScreen extends ConsumerStatefulWidget {
  const VentasScreen({super.key});

  @override
  ConsumerState<VentasScreen> createState() => _VentasScreenState();
}

class _VentasScreenState extends ConsumerState<VentasScreen> with SingleTickerProviderStateMixin {
  late TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final user = ref.watch(authStateProvider).user;
    final isAdmin = user?.role == 'ADMIN';

    final tabs = <Tab>[
      const Tab(text: 'Nueva venta'),
      const Tab(text: 'Historial'),
      const Tab(text: 'Clientes'),
    ];
    final views = <Widget>[
      const SaleBuilderView(),
      const SalesHistoryView(),
      const ClientsView(),
    ];

    if (isAdmin) {
      tabs.add(const Tab(text: 'Admin'));
      views.add(const AdminSalesDashboardView());
    }

    if (_controller.length != tabs.length) {
      final previousIndex = _controller.index.clamp(0, tabs.length - 1);
      _controller.dispose();
      _controller = TabController(length: tabs.length, vsync: this, initialIndex: previousIndex);
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors.primary,
                colors.primaryContainer.withOpacity(0.85),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ventas',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tickets, historial y clientes',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onPrimary.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.onPrimary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _controller,
                isScrollable: true,
                tabs: tabs,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                labelColor: colors.onPrimary,
                unselectedLabelColor: colors.onPrimary.withOpacity(0.75),
                indicator: BoxDecoration(
                  color: colors.onPrimary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
              ),
            ),
          ),
        ),
      ),
      drawer: AppDrawer(currentUser: user),
      body: TabBarView(
        controller: _controller,
        children: views,
      ),
    );
  }
}
