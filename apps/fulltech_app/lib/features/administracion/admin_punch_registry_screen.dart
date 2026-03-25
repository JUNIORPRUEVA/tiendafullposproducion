import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/punch_model.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../ponche/data/punch_repository.dart';

class AdminPunchRegistryScreen extends ConsumerStatefulWidget {
  const AdminPunchRegistryScreen({super.key});

  @override
  ConsumerState<AdminPunchRegistryScreen> createState() =>
      _AdminPunchRegistryScreenState();
}

class _AdminPunchRegistryScreenState
    extends ConsumerState<AdminPunchRegistryScreen> {
  bool _loading = false;
  String? _error;
  List<PunchModel> _items = const [];
  final TextEditingController _searchCtrl = TextEditingController();
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final rows = await ref.read(punchRepositoryProvider).listAdmin(
        from: DateTime(_from.year, _from.month, _from.day),
        to: DateTime(_to.year, _to.month, _to.day),
      );
      if (!mounted) return;
      setState(() => _items = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _dateText(DateTime value) {
    return DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(value.toLocal());
  }

  String _dateOnlyText(DateTime value) {
    return DateFormat('dd/MM/yyyy', 'es_DO').format(value);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _load();
  }

  void _openDetail(PunchModel item) {
    final userName = (item.user?.nombreCompleto ?? '').trim().isEmpty
        ? (item.user?.email ?? 'Usuario sin nombre')
        : item.user!.nombreCompleto;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Detalle de ponche'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Usuario: $userName'),
              Text('Correo: ${item.user?.email ?? 'No disponible'}'),
              Text('Rol: ${(item.user?.role ?? 'No disponible').toUpperCase()}'),
              Text('Tipo: ${item.type.label}'),
              Text('Fecha: ${_dateText(item.timestamp)}'),
              Text('ID registro: ${item.id}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  List<PunchModel> get _visibleItems {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items.where((item) {
      final name = (item.user?.nombreCompleto ?? '').toLowerCase();
      final email = (item.user?.email ?? '').toLowerCase();
      final type = item.type.label.toLowerCase();
      return name.contains(query) || email.contains(query) || type.contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authStateProvider).user;
    final visible = _visibleItems;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      appBar: CustomAppBar(
        title: 'Registro global de ponches',
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
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Buscar usuario o tipo de ponche',
                hintText: 'Nombre, correo, entrada, salida...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range_rounded),
                label: Text(
                  'Rango: ${_dateOnlyText(_from)} - ${_dateOnlyText(_to)}',
                ),
              ),
            ),
          ),
          Expanded(
            child: _error != null
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
                : visible.isEmpty
                    ? const Center(
                        child: Text('No hay registros de ponche para mostrar.'),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = visible[index];
                            final userName =
                                (item.user?.nombreCompleto ?? '').trim().isEmpty
                                    ? (item.user?.email ?? 'Usuario sin nombre')
                                    : item.user!.nombreCompleto;

                            return Card(
                              child: ListTile(
                                onTap: () => _openDetail(item),
                                leading: const Icon(Icons.access_time_rounded),
                                title: Text(userName),
                                subtitle: Text(
                                  '${item.type.label} · ${_dateText(item.timestamp)}',
                                ),
                                trailing: Text(
                                  (item.user?.role ?? '').toUpperCase(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
