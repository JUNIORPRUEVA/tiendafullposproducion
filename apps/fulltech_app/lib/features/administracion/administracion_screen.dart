import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'data/administracion_repository.dart';
import 'models/admin_panel_models.dart';

class AdministracionScreen extends ConsumerStatefulWidget {
  const AdministracionScreen({super.key});

  @override
  ConsumerState<AdministracionScreen> createState() =>
      _AdministracionScreenState();
}

class _AdministracionScreenState extends ConsumerState<AdministracionScreen> {
  bool _loading = false;
  String? _error;
  AdminPanelOverview? _overview;
  AdminAiInsights? _insights;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

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
    final currentUser = ref.watch(authStateProvider).user;
    final theme = Theme.of(context);
    final overview = _overview;
    final metrics = overview?.metrics ?? const <String, dynamic>{};

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      appBar: CustomAppBar(
        title: 'Administración',
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  _AdminQuickAccessMenu(),
                  const SizedBox(height: 16),
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
                            _insights?.message ?? 'Sin información disponible.',
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
                  if (_error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    )
                  else if ((overview?.alerts ?? const <AdminPanelAlert>[]).isEmpty)
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
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _AdminQuickAccessMenu(),
                  const SizedBox(height: 16),
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
                            _insights?.message ?? 'Sin información disponible.',
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
                  if (_error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    )
                  else if ((overview?.alerts ?? const <AdminPanelAlert>[]).isEmpty)
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

class _AdminQuickAccessMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Menú administrativo',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Consulta registros globales de todo el equipo.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => context.push(Routes.administracionPonches),
                  icon: const Icon(Icons.punch_clock_outlined),
                  label: const Text('Registro de ponches'),
                ),
                FilledButton.icon(
                  onPressed: () => context.push(Routes.ventas),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Registro de ventas'),
                ),
                FilledButton.icon(
                  onPressed: () => context.push('${Routes.cotizacionesHistorial}?pick=0'),
                  icon: const Icon(Icons.request_quote_outlined),
                  label: const Text('Registro de cotizaciones'),
                ),
              ],
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
