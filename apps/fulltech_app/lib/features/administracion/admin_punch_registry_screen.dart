import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/models/punch_model.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/professional_recovery_card.dart';
import '../ponche/data/punch_repository.dart';

class AdminPunchRegistryScreen extends ConsumerStatefulWidget {
  const AdminPunchRegistryScreen({super.key});

  @override
  ConsumerState<AdminPunchRegistryScreen> createState() =>
      _AdminPunchRegistryScreenState();
}

class _AdminPunchRegistryScreenState
    extends ConsumerState<AdminPunchRegistryScreen> {
  static const List<int> _autoRetrySecondsByAttempt = <int>[3, 6, 12];

  bool _loading = false;
  UserFacingError? _error;
  List<PunchModel> _items = const [];
  final TextEditingController _searchCtrl = TextEditingController();
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  Timer? _autoRetryTimer;
  int _autoRetryAttempt = 0;
  int _autoRetryCountdown = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _autoRetryTimer?.cancel();

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _autoRetryCountdown = 0;
      });
    }

    try {
      final rows = await ref.read(punchRepositoryProvider).listAdmin(
        from: DateTime(_from.year, _from.month, _from.day),
        to: DateTime(_to.year, _to.month, _to.day),
      );
      if (!mounted) return;
      setState(() {
        _items = rows;
        _autoRetryAttempt = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = UserFacingError.from(e));
      _scheduleAutoRetryIfNeeded();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleAutoRetryIfNeeded() {
    final error = _error;
    if (error == null || !error.autoRetry) return;
    if (_autoRetryAttempt >= _autoRetrySecondsByAttempt.length) return;

    _autoRetryTimer?.cancel();
    final seconds = _autoRetrySecondsByAttempt[_autoRetryAttempt];
    setState(() => _autoRetryCountdown = seconds);

    _autoRetryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_autoRetryCountdown <= 1) {
        timer.cancel();
        _autoRetryAttempt += 1;
        unawaited(_load());
        return;
      }
      setState(() => _autoRetryCountdown -= 1);
    });
  }

  Future<void> _retryNow() async {
    _autoRetryTimer?.cancel();
    if (mounted) setState(() => _autoRetryCountdown = 0);
    await _load();
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
                ? ProfessionalRecoveryCard(
                    error: _error!,
                    autoRetryCountdown: _autoRetryCountdown > 0
                        ? _autoRetryCountdown
                        : null,
                    isRetrying: _loading,
                    onRetryNow: _retryNow,
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
