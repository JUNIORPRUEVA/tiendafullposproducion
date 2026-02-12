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
        title: const Text('Ventas'),
        bottom: TabBar(
          controller: _controller,
          isScrollable: true,
          tabs: tabs,
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
