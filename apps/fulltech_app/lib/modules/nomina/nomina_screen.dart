import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'application/nomina_controller.dart';
import 'nomina_models.dart';

class NominaScreen extends ConsumerWidget {
  const NominaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;
    final isAdmin = currentUser?.role == 'ADMIN';

    if (!isAdmin) {
      return Scaffold(
        appBar: CustomAppBar(title: 'Nómina', showLogo: false),
        drawer: AppDrawer(currentUser: currentUser),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 46,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Este módulo es solo para administración',
                  style: TextStyle(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => context.go(Routes.misPagos),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Ir a Mis Pagos'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final state = ref.watch(nominaHomeControllerProvider);
    final controller = ref.read(nominaHomeControllerProvider.notifier);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Nómina',
        showLogo: false,
        actions: [
          IconButton(
            tooltip: 'Agregar empleado',
            onPressed: () => _showEmployeeDialog(context, ref),
            icon: const Icon(Icons.person_add_alt_1),
          ),
          IconButton(
            tooltip: 'Recargar',
            onPressed: state.loading ? null : controller.load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Nueva quincena',
            onPressed: () => _showCreatePeriodDialog(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      drawer: AppDrawer(currentUser: currentUser),
      body: RefreshIndicator(
        onRefresh: controller.load,
        child: state.loading && state.periods.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _NominaSummaryCard(state: state),
                  const SizedBox(height: 12),
                  if (state.error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          state.error!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  if (state.periods.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            Icon(
                              Icons.event_note_outlined,
                              size: 40,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Aún no hay quincenas creadas',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Crea la primera quincena para comenzar la gestión de nómina.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () =>
                                  _showCreatePeriodDialog(context, ref),
                              icon: const Icon(Icons.add),
                              label: const Text('Crear quincena'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      'Quincenas',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...state.periods.map(
                      (period) => _PeriodCard(
                        period: period,
                        onClose: period.isOpen
                            ? () => _confirmClosePeriod(context, ref, period)
                            : null,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Equipo de ventas (nómina)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _showEmployeeDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (state.employees.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('No hay empleados de nómina registrados.'),
                      ),
                    )
                  else
                    ...state.employees.map(
                      (employee) => _EmployeeCard(
                        employee: employee,
                        onEdit: () => _showEmployeeDialog(
                          context,
                          ref,
                          employee: employee,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _showEmployeeDialog(
    BuildContext context,
    WidgetRef ref, {
    PayrollEmployee? employee,
  }) async {
    final nameCtrl = TextEditingController(text: employee?.nombre ?? '');
    final phoneCtrl = TextEditingController(text: employee?.telefono ?? '');
    final roleCtrl = TextEditingController(text: employee?.puesto ?? '');
    final cuotaCtrl = TextEditingController(
      text: (employee?.cuotaMinima ?? 0).toStringAsFixed(2),
    );

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(employee == null ? 'Agregar empleado' : 'Editar empleado'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: roleCtrl,
                decoration: const InputDecoration(labelText: 'Puesto'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cuotaCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cuota mínima (meta quincenal)',
                  helperText: 'Meta de ventas quincenal del empleado',
                ),
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
            onPressed: () async {
              final cuota = double.tryParse(cuotaCtrl.text.trim()) ?? -1;
              if (cuota < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('La cuota mínima debe ser un número >= 0'),
                  ),
                );
                return;
              }

              try {
                await ref
                    .read(nominaHomeControllerProvider.notifier)
                    .saveEmployee(
                      id: employee?.id,
                      nombre: nameCtrl.text,
                      telefono: phoneCtrl.text,
                      puesto: roleCtrl.text,
                      cuotaMinima: cuota,
                      activo: employee?.activo ?? true,
                    );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      employee == null
                          ? 'Empleado agregado'
                          : 'Empleado actualizado',
                    ),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No se pudo guardar: $e')),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreatePeriodDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final titleCtrl = TextEditingController();
    DateTime start = DateTime.now();
    DateTime end = DateTime.now().add(const Duration(days: 14));

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Nueva quincena'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Inicio'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(start)),
                trailing: const Icon(Icons.date_range),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: start,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setStateDialog(() => start = picked);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fin'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(end)),
                trailing: const Icon(Icons.date_range),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: end,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setStateDialog(() => end = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Debes indicar un título')),
                  );
                  return;
                }
                try {
                  await ref
                      .read(nominaHomeControllerProvider.notifier)
                      .createPeriod(start: start, end: end, title: title);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Quincena creada correctamente'),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('No se pudo crear: $e')),
                  );
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClosePeriod(
    BuildContext context,
    WidgetRef ref,
    PayrollPeriod period,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar quincena'),
        content: Text('¿Deseas cerrar "${period.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      await ref
          .read(nominaHomeControllerProvider.notifier)
          .closePeriod(period.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Quincena cerrada')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cerrar: $e')));
    }
  }
}

class _NominaSummaryCard extends StatelessWidget {
  const _NominaSummaryCard({required this.state});

  final NominaHomeState state;

  @override
  Widget build(BuildContext context) {
    final open = state.openPeriod;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.payments_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resumen de nómina',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text('Quincenas: ${state.periods.length}'),
                  Text(
                    open != null
                        ? 'Abierta: ${open.title}'
                        : 'No hay quincena abierta',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.period, required this.onClose});

  final PayrollPeriod period;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final dateRange =
        '${DateFormat('dd/MM/yyyy').format(period.startDate)} - ${DateFormat('dd/MM/yyyy').format(period.endDate)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(
          period.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(dateRange),
        trailing: period.isOpen
            ? FilledButton.tonal(
                onPressed: onClose,
                child: const Text('Cerrar'),
              )
            : const Chip(label: Text('Cerrada')),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee, required this.onEdit});

  final PayrollEmployee employee;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(
          employee.nombre,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Puesto: ${employee.puesto ?? 'N/A'}\n'
          'Cuota mínima (quincenal): ${money.format(employee.cuotaMinima)}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Editar',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
    );
  }
}
