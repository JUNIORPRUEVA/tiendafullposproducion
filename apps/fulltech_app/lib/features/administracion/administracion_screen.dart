import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_drawer.dart';
import 'data/administracion_repository.dart';
import 'models/admin_panel_models.dart';

class AdministracionScreen extends ConsumerStatefulWidget {
  const AdministracionScreen({super.key});

  @override
  ConsumerState<AdministracionScreen> createState() =>
      _AdministracionScreenState();
}

class _AdministracionScreenState extends ConsumerState<AdministracionScreen> {
  bool _loading = true;
  String? _error;
  AdminPanelOverview? _overview;
  AdminAiInsights? _insights;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repository = ref.read(administracionRepositoryProvider);
      final results = await Future.wait([
        repository.getOverview(),
        repository.getAiInsights(),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = results[0] as AdminPanelOverview;
        _insights = results[1] as AdminAiInsights;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overview = _overview;
    final metrics = overview?.metrics ?? const <String, dynamic>{};

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Administración'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _AdminMetricCard(
                            label: 'Usuarios activos',
                            value: '${metrics['activeUsers'] ?? 0}',
                          ),
                          _AdminMetricCard(
                            label: 'Usuarios bloqueados',
                            value: '${metrics['blockedUsers'] ?? 0}',
                          ),
                          _AdminMetricCard(
                            label: 'Sin ponche hoy',
                            value: '${metrics['missingPunchToday'] ?? 0}',
                          ),
                          _AdminMetricCard(
                            label: 'Sin ventas 7d',
                            value: '${metrics['noSalesInWindow'] ?? 0}',
                          ),
                          _AdminMetricCard(
                            label: 'Tardanzas hoy',
                            value: '${metrics['lateArrivalsToday'] ?? 0}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Resumen IA',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _insights?.message ??
                                    'Sin información disponible.',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Alertas',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if ((overview?.alerts ?? const <AdminPanelAlert>[]).isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No hay alertas activas.'),
                          ),
                        )
                      else
                        ...overview!.alerts.map(
                          (alert) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Card(
                              child: ListTile(
                                leading: const Icon(Icons.warning_amber_rounded),
                                title: Text(alert.title),
                                subtitle: Text(alert.detail),
                                trailing: Text(alert.severity.toUpperCase()),
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

class _AdminMetricCard extends StatelessWidget {
  const _AdminMetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
