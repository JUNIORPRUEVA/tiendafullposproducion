import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import 'data/admin_locations_repository.dart';
import 'data/administracion_repository.dart';
import 'models/admin_locations_models.dart';
import 'models/admin_panel_models.dart';

class AdministracionScreen extends ConsumerStatefulWidget {
  const AdministracionScreen({super.key});

  @override
  ConsumerState<AdministracionScreen> createState() =>
      _AdministracionScreenState();
}

class _AdministracionScreenState extends ConsumerState<AdministracionScreen> {
  int _index = 0;
  static const _days = 7;

  AdminPanelOverview? _overview;
  AdminAiInsights? _insights;
  Map<String, dynamic>? _attendance;
  Map<String, dynamic>? _sales;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(administracionRepositoryProvider);
      final results = await Future.wait([
        repo.getOverview(days: _days),
        repo.getAiInsights(days: _days),
        repo.getAttendanceSummary(days: _days),
        repo.getSalesSummary(days: _days),
      ]);

      if (!mounted) return;
      setState(() {
        _overview = results[0] as AdminPanelOverview;
        _insights = results[1] as AdminAiInsights;
        _attendance = results[2] as Map<String, dynamic>;
        _sales = results[3] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final isAdmin = (user?.role ?? '').toUpperCase() == 'ADMIN';

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Administración'),
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
        ),
        drawer: AppDrawer(currentUser: user),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Este módulo está disponible solo para ADMIN.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }

    final isDesktop = MediaQuery.sizeOf(context).width >= 980;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar panel',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: AppDrawer(currentUser: user),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loadAll,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : isDesktop
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (next) =>
                      setState(() => _index = next),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.smart_toy_outlined),
                      label: Text('IA'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.fact_check_outlined),
                      label: Text('Ponches'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.point_of_sale_outlined),
                      label: Text('Ventas'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      label: Text('Resumen'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.location_on_outlined),
                      label: Text('Ubicaciones'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildPage()),
              ],
            )
          : Column(
              children: [
                Expanded(child: _buildPage()),
                NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (next) =>
                      setState(() => _index = next),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.smart_toy_outlined),
                      label: 'IA',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.fact_check_outlined),
                      label: 'Ponches',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.point_of_sale_outlined),
                      label: 'Ventas',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      label: 'Resumen',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.location_on_outlined),
                      label: 'Ubicaciones',
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildPage() {
    switch (_index) {
      case 0:
        return _AdminIaPage(
          insights: _insights!,
          fallbackAlerts: _overview!.alerts,
        );
      case 1:
        return _AdminAttendancePage(data: _attendance!);
      case 2:
        return _AdminSalesPage(data: _sales!);
      case 3:
        return _AdminOverviewPage(data: _overview!);
      case 4:
        return const _AdminLocationsPage();
      default:
        return _AdminOverviewPage(data: _overview!);
    }
  }
}

class _AdminLocationsPage extends ConsumerStatefulWidget {
  const _AdminLocationsPage();

  @override
  ConsumerState<_AdminLocationsPage> createState() =>
      _AdminLocationsPageState();
}

class _AdminLocationsPageState extends ConsumerState<_AdminLocationsPage> {
  static const _refreshInterval = Duration(seconds: 15);

  final MapController _mapController = MapController();
  Timer? _timer;
  bool _loading = true;
  String? _error;
  List<AdminUserLocation> _items = const [];
  bool _didMoveToFirst = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshInterval, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final repo = ref.read(adminLocationsRepositoryProvider);
      final next = await repo.latest();
      if (!mounted) return;

      setState(() {
        _items = next;
        _loading = false;
        _error = null;
      });

      if (!_didMoveToFirst && next.isNotEmpty) {
        _didMoveToFirst = true;
        final first = next.first;
        _mapController.move(LatLng(first.latitude, first.longitude), 14);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aún no hay ubicaciones reportadas.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    final markers = _items
        .where((item) => item.blocked != true)
        .map(
          (item) => Marker(
            width: 48,
            height: 48,
            point: LatLng(item.latitude, item.longitude),
            child: Tooltip(
              message: item.nombreCompleto.isNotEmpty
                  ? item.nombreCompleto
                  : item.email,
              child: Icon(
                Icons.location_on,
                color: Theme.of(context).colorScheme.primary,
                size: 42,
              ),
            ),
          ),
        )
        .toList();

    final first = _items.first;
    final initial = LatLng(first.latitude, first.longitude);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: initial, initialZoom: 13),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'fulltech_app',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }
}

class _AdminIaPage extends StatelessWidget {
  final AdminAiInsights insights;
  final List<AdminPanelAlert> fallbackAlerts;

  const _AdminIaPage({required this.insights, required this.fallbackAlerts});

  @override
  Widget build(BuildContext context) {
    final alerts = insights.alerts.isEmpty ? fallbackAlerts : insights.alerts;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Asistente IA de Administración',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Chip(label: Text(insights.source.toUpperCase())),
                  ],
                ),
                const SizedBox(height: 10),
                Text(insights.message),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Novedades detectadas',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ...alerts.map(
          (item) => Card(
            child: ListTile(
              leading: Icon(
                item.severity == 'high'
                    ? Icons.priority_high
                    : item.severity == 'medium'
                    ? Icons.report_problem_outlined
                    : Icons.info_outline,
              ),
              title: Text(item.title),
              subtitle: Text(item.detail),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminOverviewPage extends StatelessWidget {
  final AdminPanelOverview data;

  const _AdminOverviewPage({required this.data});

  @override
  Widget build(BuildContext context) {
    final metrics = data.metrics;
    final cards = <MapEntry<String, dynamic>>[
      MapEntry('Usuarios activos', metrics['activeUsers'] ?? 0),
      MapEntry('Usuarios bloqueados', metrics['blockedUsers'] ?? 0),
      MapEntry('Sin ponche hoy', metrics['missingPunchToday'] ?? 0),
      MapEntry('Sin ventas 7d', metrics['noSalesInWindow'] ?? 0),
      MapEntry('Tardanzas hoy', metrics['lateArrivalsToday'] ?? 0),
      MapEntry('Operaciones abiertas', metrics['openOperations'] ?? 0),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map(
                (entry) => SizedBox(
                  width: 220,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${entry.value}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        const Text('Alertas', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ...data.alerts.map(
          (item) => Card(
            child: ListTile(
              title: Text(item.title),
              subtitle: Text(item.detail),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminAttendancePage extends StatelessWidget {
  final Map<String, dynamic> data;

  const _AdminAttendancePage({required this.data});

  @override
  Widget build(BuildContext context) {
    final totals = (data['totals'] is Map)
        ? (data['totals'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final users = (data['users'] is List) ? (data['users'] as List) : const [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: const Text('Resumen de ponches (7 días)'),
            subtitle: Text(
              'Tardanzas: ${totals['tardyCount'] ?? 0} · Incompletos: ${totals['incompleteCount'] ?? 0} · Salidas tempranas: ${totals['earlyLeaveCount'] ?? 0}',
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...users.map((item) {
          final row = item is Map
              ? item.cast<String, dynamic>()
              : <String, dynamic>{};
          final user = (row['user'] is Map)
              ? (row['user'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};
          final aggregate = (row['aggregate'] is Map)
              ? (row['aggregate'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};
          return Card(
            child: ListTile(
              title: Text(
                '${user['nombreCompleto'] ?? 'Usuario'} (${user['role'] ?? ''})',
              ),
              subtitle: Text(
                'Incidentes: ${aggregate['incidentsCount'] ?? 0} · Tardanza(min): ${aggregate['tardinessMinutes'] ?? 0} · No laborado(min): ${aggregate['notWorkedMinutes'] ?? 0}',
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _AdminSalesPage extends StatelessWidget {
  final Map<String, dynamic> data;

  const _AdminSalesPage({required this.data});

  @override
  Widget build(BuildContext context) {
    final totals = (data['totals'] is Map)
        ? (data['totals'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final items = (data['items'] is List) ? (data['items'] as List) : const [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: const Text('Resumen de ventas (7 días)'),
            subtitle: Text(
              'Ventas: ${totals['totalSales'] ?? 0} · Vendido: RD\$ ${totals['totalSold'] ?? 0} · Comisión: RD\$ ${totals['totalCommission'] ?? 0}',
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) {
          final row = item is Map
              ? item.cast<String, dynamic>()
              : <String, dynamic>{};
          return Card(
            child: ListTile(
              title: Text((row['userName'] ?? 'Usuario').toString()),
              subtitle: Text(
                'Ventas: ${row['totalSales'] ?? 0} · Vendido: RD\$ ${row['totalSold'] ?? 0} · Comisión: RD\$ ${row['totalCommission'] ?? 0}',
              ),
            ),
          );
        }),
      ],
    );
  }
}
