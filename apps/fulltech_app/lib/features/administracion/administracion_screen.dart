import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/models/user_model.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import '../salidas_tecnicas/data/salidas_tecnicas_repository.dart';
import '../salidas_tecnicas/salidas_tecnicas_models.dart';
import '../user/data/users_repository.dart';
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
                    NavigationRailDestination(
                      icon: Icon(Icons.local_gas_station_outlined),
                      label: Text('Combustible'),
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
                    NavigationDestination(
                      icon: Icon(Icons.local_gas_station_outlined),
                      label: 'Combustible',
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
      case 5:
        return const _AdminTechFuelPage();
      default:
        return _AdminOverviewPage(data: _overview!);
    }
  }
}

class _AdminTechFuelPage extends ConsumerStatefulWidget {
  const _AdminTechFuelPage();

  @override
  ConsumerState<_AdminTechFuelPage> createState() => _AdminTechFuelPageState();
}

class _AdminTechFuelPageState extends ConsumerState<_AdminTechFuelPage> {
  static const List<String> _statusOptions = [
    'TODOS',
    'FINALIZADA',
    'APROBADA',
    'PAGADA',
    'RECHAZADA',
  ];

  List<UserModel> _technicians = const [];
  List<TechnicalDeparture> _departures = const [];
  List<TechFuelPayment> _payments = const [];
  bool _loading = true;
  bool _acting = false;
  String? _error;
  String? _selectedTechnicianId;
  String _selectedStatus = 'TODOS';

  SalidasTecnicasRepository get _repo =>
      ref.read(salidasTecnicasRepositoryProvider);

  UsersRepository get _usersRepo => ref.read(usersRepositoryProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final selectedTechnicianId = _selectedTechnicianId;
      final selectedStatus = _selectedStatus == 'TODOS'
          ? null
          : _selectedStatus;

      final results = await Future.wait([
        _usersRepo.getAllUsers(forceRefresh: silent),
        _repo.listAdminDepartures(
          tecnicoId: selectedTechnicianId,
          estado: selectedStatus,
        ),
        _repo.listAdminFuelPayments(tecnicoId: selectedTechnicianId),
      ]);

      if (!mounted) return;

      final users = (results[0] as List<UserModel>)
          .where((user) => user.appRole.isTechnician && !user.blocked)
          .toList(growable: false);

      setState(() {
        _technicians = users;
        _departures = results[1] as List<TechnicalDeparture>;
        _payments = results[2] as List<TechFuelPayment>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await action();
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      await AppFeedback.showError(context, e.toString());
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  Future<void> _approveDeparture(TechnicalDeparture departure) async {
    await _runAction(() async {
      await _repo.approveDeparture(departure.id);
      if (!mounted) return;
      await AppFeedback.showInfo(context, 'Salida aprobada correctamente.');
    });
  }

  Future<void> _rejectDeparture(TechnicalDeparture departure) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rechazar salida'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Motivo',
            hintText: 'Explica por qué se rechaza esta salida',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (reason == null || reason.trim().isEmpty) {
      return;
    }

    await _runAction(() async {
      await _repo.rejectDeparture(departure.id, observacion: reason);
      if (!mounted) return;
      await AppFeedback.showInfo(context, 'Salida rechazada.');
    });
  }

  Future<void> _createPaymentPeriod() async {
    final technicians = _technicians;
    if (technicians.isEmpty) {
      await AppFeedback.showError(
        context,
        'No hay técnicos disponibles para generar el pago.',
      );
      return;
    }

    final result = await showDialog<_PaymentPeriodFormValue>(
      context: context,
      builder: (dialogContext) => _CreateFuelPaymentDialog(
        technicians: technicians,
        initialTechnicianId: _selectedTechnicianId,
      ),
    );

    if (result == null) return;

    await _runAction(() async {
      final payment = await _repo.createFuelPaymentPeriod(
        tecnicoId: result.technicianId,
        fechaInicio: result.start,
        fechaFin: result.end,
      );
      if (!mounted) return;
      await AppFeedback.showInfo(
        context,
        'Pago generado por RD\$${payment.totalMonto.toStringAsFixed(2)}.',
      );
    });
  }

  Future<void> _markPaymentPaid(TechFuelPayment payment) async {
    await _runAction(() async {
      final result = await _repo.markFuelPaymentPaid(payment.id);
      if (!mounted) return;

      final imported = result['payrollImported'] == true;
      final periodId = result['payrollPeriodId']?.toString();
      final message = imported
          ? 'Pago marcado como pagado e importado a nómina.'
          : periodId != null && periodId.isNotEmpty
          ? 'Pago marcado como pagado. La importación a nómina quedó pendiente.'
          : 'Pago marcado como pagado. No había quincena abierta coincidente.';
      await AppFeedback.showInfo(context, message);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final pendingApprovals = _departures
        .where((item) => item.estado.toUpperCase() == 'FINALIZADA')
        .length;
    final approvedAwaitingPayment = _departures
        .where((item) => item.estado.toUpperCase() == 'APROBADA')
        .length;
    final pendingPayments = _payments.where((item) => item.isPending).length;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _AdminMetricCard(
                label: 'Salidas por aprobar',
                value: '$pendingApprovals',
                icon: Icons.fact_check_outlined,
              ),
              _AdminMetricCard(
                label: 'Aprobadas sin pago',
                value: '$approvedAwaitingPayment',
                icon: Icons.hourglass_top_outlined,
              ),
              _AdminMetricCard(
                label: 'Pagos pendientes',
                value: '$pendingPayments',
                icon: Icons.local_gas_station_outlined,
              ),
              _AdminMetricCard(
                label: 'Monto visible',
                value: currency.format(
                  _payments.fold<double>(
                    0,
                    (sum, item) => sum + item.totalMonto,
                  ),
                ),
                icon: Icons.payments_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String?>(
                      initialValue: _selectedTechnicianId,
                      decoration: const InputDecoration(
                        labelText: 'Filtrar por técnico',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Todos los técnicos'),
                        ),
                        ..._technicians.map(
                          (technician) => DropdownMenuItem<String?>(
                            value: technician.id,
                            child: Text(technician.nombreCompleto),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedTechnicianId = value);
                        _load(silent: true);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Estado de salida',
                      ),
                      items: _statusOptions
                          .map(
                            (status) => DropdownMenuItem<String>(
                              value: status,
                              child: Text(status),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedStatus = value);
                        _load(silent: true);
                      },
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _acting ? null : _createPaymentPeriod,
                    icon: const Icon(Icons.add_card_outlined),
                    label: const Text('Generar pago'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _acting ? null : () => _load(silent: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Recargar'),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Salidas técnicas',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_departures.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No hay salidas para los filtros actuales.'),
              ),
            )
          else
            ..._departures
                .take(50)
                .map(
                  (departure) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  departure.servicio?.title ??
                                      'Servicio sin título',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              _AdminStatusBadge(label: departure.estado),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              _AdminInfoPill(
                                label:
                                    'Técnico: ${departure.tecnico?.nombreCompleto ?? 'Sin técnico'}',
                              ),
                              _AdminInfoPill(
                                label:
                                    'Vehículo: ${departure.vehiculo?.displayName ?? 'Sin vehículo'}',
                              ),
                              _AdminInfoPill(
                                label:
                                    'Monto: ${currency.format(departure.montoCombustible)}',
                              ),
                              if (departure.fecha != null)
                                _AdminInfoPill(
                                  label:
                                      'Fecha: ${DateFormat('dd/MM/yyyy').format(departure.fecha!.toLocal())}',
                                ),
                            ],
                          ),
                          if ((departure.observacion ?? '')
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(departure.observacion!.trim()),
                          ],
                          if (departure.estado.toUpperCase() ==
                              'FINALIZADA') ...[
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed: _acting
                                      ? null
                                      : () => _approveDeparture(departure),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Aprobar'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _acting
                                      ? null
                                      : () => _rejectDeparture(departure),
                                  icon: const Icon(Icons.cancel_outlined),
                                  label: const Text('Rechazar'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 16),
          Text(
            'Pagos de combustible',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_payments.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No hay pagos de combustible generados todavía.'),
              ),
            )
          else
            ..._payments
                .take(50)
                .map(
                  (payment) => Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(
                        payment.tecnico?.nombreCompleto ?? 'Técnico sin nombre',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rango: ${_formatDate(payment.fechaInicio)} - ${_formatDate(payment.fechaFin)}',
                            ),
                            Text(
                              'Monto: ${currency.format(payment.totalMonto)}',
                            ),
                            if (payment.fechaPago != null)
                              Text(
                                'Fecha de pago: ${_formatDate(payment.fechaPago)}',
                              ),
                            if (payment.payrollEntryId != null)
                              Text(
                                'Importado a nómina: sí (${payment.payrollPeriodId ?? 'sin quincena'})',
                              ),
                          ],
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _AdminStatusBadge(label: payment.estado),
                          const SizedBox(height: 8),
                          if (payment.isPending)
                            FilledButton(
                              onPressed: _acting
                                  ? null
                                  : () => _markPaymentPaid(payment),
                              child: const Text('Marcar pagado'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Sin fecha';
    return DateFormat('dd/MM/yyyy').format(value.toLocal());
  }
}

class _AdminMetricCard extends StatelessWidget {
  const _AdminMetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.12),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
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

class _AdminInfoPill extends StatelessWidget {
  const _AdminInfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}

class _AdminStatusBadge extends StatelessWidget {
  const _AdminStatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final upper = label.toUpperCase();
    final color = switch (upper) {
      'FINALIZADA' => Colors.orange,
      'APROBADA' => Colors.green,
      'PAGADA' => Colors.teal,
      'PENDIENTE' => Colors.deepOrange,
      'RECHAZADA' => Colors.red,
      _ => Theme.of(context).colorScheme.primary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        upper,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PaymentPeriodFormValue {
  const _PaymentPeriodFormValue({
    required this.technicianId,
    required this.start,
    required this.end,
  });

  final String technicianId;
  final DateTime start;
  final DateTime end;
}

class _CreateFuelPaymentDialog extends StatefulWidget {
  const _CreateFuelPaymentDialog({
    required this.technicians,
    this.initialTechnicianId,
  });

  final List<UserModel> technicians;
  final String? initialTechnicianId;

  @override
  State<_CreateFuelPaymentDialog> createState() =>
      _CreateFuelPaymentDialogState();
}

class _CreateFuelPaymentDialogState extends State<_CreateFuelPaymentDialog> {
  late String _technicianId;
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    _technicianId = widget.initialTechnicianId ?? widget.technicians.first.id;
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');

    return AlertDialog(
      title: const Text('Generar pago de combustible'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _technicianId,
              decoration: const InputDecoration(labelText: 'Técnico'),
              items: widget.technicians
                  .map(
                    (technician) => DropdownMenuItem<String>(
                      value: technician.id,
                      child: Text(technician.nombreCompleto),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _technicianId = value);
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha inicial'),
              subtitle: Text(dateFormat.format(_start)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _start,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2100),
                );
                if (picked == null) return;
                setState(
                  () =>
                      _start = DateTime(picked.year, picked.month, picked.day),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha final'),
              subtitle: Text(dateFormat.format(_end)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _end,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2100),
                );
                if (picked == null) return;
                setState(
                  () => _end = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    23,
                    59,
                    59,
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_end.isBefore(_start)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'La fecha final no puede ser menor que la inicial.',
                  ),
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              _PaymentPeriodFormValue(
                technicianId: _technicianId,
                start: _start,
                end: _end,
              ),
            );
          },
          child: const Text('Generar'),
        ),
      ],
    );
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

  String _formatMinutes(dynamic raw) {
    final minutes = raw is num ? raw.toInt() : 0;
    final sign = minutes < 0 ? '-' : '';
    final absolute = minutes.abs();
    final hours = absolute ~/ 60;
    final remainingMinutes = absolute % 60;
    return '$sign${hours}h ${remainingMinutes.toString().padLeft(2, '0')}m';
  }

  Color _balanceColor(BuildContext context, dynamic raw) {
    final minutes = raw is num ? raw.toInt() : 0;
    if (minutes > 0) return Colors.green.shade700;
    if (minutes < 0) return Theme.of(context).colorScheme.error;
    return Colors.blueGrey;
  }

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
        Row(
          children: [
            Expanded(
              child: _AdminAttendanceMetricCard(
                label: 'Horas a favor',
                value: _formatMinutes(totals['favorableMinutes']),
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AdminAttendanceMetricCard(
                label: 'Horas en contra',
                value: _formatMinutes(totals['unfavorableMinutes']),
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _AdminAttendanceMetricCard(
                label: 'Balance neto',
                value: _formatMinutes(totals['balanceMinutes']),
                color: _balanceColor(context, totals['balanceMinutes']),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AdminAttendanceMetricCard(
                label: 'Horas laboradas',
                value: _formatMinutes(totals['workedMinutes']),
                color: AppTheme.primaryColor,
              ),
            ),
          ],
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
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Incidentes: ${aggregate['incidentsCount'] ?? 0} · Tardanza: ${_formatMinutes(aggregate['tardinessMinutes'])} · No laborado: ${_formatMinutes(aggregate['unfavorableMinutes'])}',
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AdminAttendanceBadge(
                        label: 'A favor',
                        value: _formatMinutes(aggregate['favorableMinutes']),
                        color: Colors.green.shade700,
                      ),
                      _AdminAttendanceBadge(
                        label: 'En contra',
                        value: _formatMinutes(aggregate['unfavorableMinutes']),
                        color: Theme.of(context).colorScheme.error,
                      ),
                      _AdminAttendanceBadge(
                        label: 'Balance',
                        value: _formatMinutes(aggregate['balanceMinutes']),
                        color: _balanceColor(context, aggregate['balanceMinutes']),
                      ),
                    ],
                  ),
                ],
              ),
              isThreeLine: true,
            ),
          );
        }),
      ],
    );
  }
}

class _AdminAttendanceMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AdminAttendanceMetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _AdminAttendanceBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AdminAttendanceBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
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
