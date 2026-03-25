import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../modules/cotizaciones/cotizacion_models.dart';
import '../../modules/cotizaciones/data/cotizaciones_repository.dart';

class AdminQuotesRegistryScreen extends ConsumerStatefulWidget {
  const AdminQuotesRegistryScreen({super.key});

  @override
  ConsumerState<AdminQuotesRegistryScreen> createState() =>
      _AdminQuotesRegistryScreenState();
}

class _AdminQuotesRegistryScreenState
    extends ConsumerState<AdminQuotesRegistryScreen> {
  bool _loading = false;
  bool _refreshing = false;
  String? _error;
  List<CotizacionModel> _items = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _refreshing = false;
        _error = null;
      });
    }

    final repo = ref.read(cotizacionesRepositoryProvider);
    try {
      final cached = await repo.getCachedList();
      if (!mounted) return;
      if (cached.isNotEmpty) {
        setState(() {
          _items = cached;
          _loading = false;
          _refreshing = true;
        });
      }

      final rows = await repo.listAndCache();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  String _money(double value) =>
      NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value);

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authStateProvider).user;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      appBar: CustomAppBar(
        title: 'Registro global de cotizaciones',
        fallbackRoute: Routes.administracion,
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
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
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
              : _items.isEmpty
                  ? const Center(
                      child: Text('No hay cotizaciones globales para mostrar.'),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        itemCount: _items.length + (_refreshing ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          if (_refreshing && index == 0) {
                            return const LinearProgressIndicator();
                          }
                          final item = _items[_refreshing ? index - 1 : index];

                          return Card(
                            child: ListTile(
                              title: Text(
                                item.customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(item.createdAt)} '
                                '· Líneas: ${item.items.length}',
                              ),
                              trailing: Text(
                                _money(item.total),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
