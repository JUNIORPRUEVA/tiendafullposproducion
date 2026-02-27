import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import 'data/contabilidad_repository.dart';
import 'models/payable_models.dart';
import 'utils/payable_payment_pdf_service.dart';

class PagosPendientesScreen extends ConsumerStatefulWidget {
  const PagosPendientesScreen({super.key});

  @override
  ConsumerState<PagosPendientesScreen> createState() =>
      _PagosPendientesScreenState();
}

class _PagosPendientesScreenState extends ConsumerState<PagosPendientesScreen> {
  final _money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
  final _dateFmt = DateFormat('dd/MM/yyyy');

  bool _loading = true;
  String? _error;
  List<PayableService> _services = const [];
  List<PayablePayment> _payments = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(contabilidadRepositoryProvider);
      final services = await repo.listPayableServices();
      final payments = await repo.listPayablePayments();
      if (!mounted) return;
      setState(() {
        _services = services;
        _payments = payments;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar pagos pendientes: $e';
        _loading = false;
      });
    }
  }

  List<PayableService> get _activeServices =>
      _services.where((item) => item.active).toList();

  PayableService? _findService(String serviceId) {
    for (final item in _services) {
      if (item.id == serviceId) return item;
    }
    return null;
  }

  Future<void> _showSnack(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openCreateFixedDialog() async {
    final titleCtrl = TextEditingController();
    final providerCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var providerKind = PayableProviderKind.person;
    var frequency = PayableFrequency.monthly;
    var dueDate = DateTime.now();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Nuevo servicio fijo'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Servicio / concepto',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<PayableProviderKind>(
                      initialValue: providerKind,
                      items: PayableProviderKind.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setLocalState(() => providerKind = value);
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Tipo'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: providerCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre persona / empresa',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<PayableFrequency>(
                      initialValue: frequency,
                      items: const [
                        DropdownMenuItem(
                          value: PayableFrequency.monthly,
                          child: Text('Mensual'),
                        ),
                        DropdownMenuItem(
                          value: PayableFrequency.biweekly,
                          child: Text('Quincenal'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setLocalState(() => frequency = value);
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Frecuencia'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Monto estimado (opcional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Próximo pago'),
                      subtitle: Text(_dateFmt.format(dueDate)),
                      trailing: const Icon(Icons.calendar_month_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: dueDate,
                        );
                        if (picked != null) {
                          setLocalState(() => dueDate = picked);
                        }
                      },
                    ),
                    TextField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Detalle (opcional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    final providerName = providerCtrl.text.trim();
                    if (title.isEmpty || providerName.isEmpty) {
                      await _showSnack('Completa servicio y beneficiario');
                      return;
                    }
                    final amount = double.tryParse(amountCtrl.text.trim());
                    try {
                      await ref
                          .read(contabilidadRepositoryProvider)
                          .createPayableService(
                            title: title,
                            providerKind: providerKind,
                            providerName: providerName,
                            description: noteCtrl.text,
                            frequency: frequency,
                            defaultAmount: amount,
                            nextDueDate: dueDate,
                          );
                      if (!context.mounted) return;
                      Navigator.of(dialogContext).pop(true);
                    } catch (e) {
                      await _showSnack('No se pudo guardar: $e');
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == true) {
      await _load();
      await _showSnack('Servicio fijo guardado');
    }
  }

  Future<void> _openDirectPaymentDialog() async {
    final titleCtrl = TextEditingController();
    final providerCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var providerKind = PayableProviderKind.person;
    var paidAt = DateTime.now();

    final done = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Registrar pago directo'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Concepto (ej: Renta local)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<PayableProviderKind>(
                      initialValue: providerKind,
                      items: PayableProviderKind.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setLocalState(() => providerKind = value);
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Tipo'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: providerCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Persona / empresa',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Monto pagado'),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Fecha de pago'),
                      subtitle: Text(_dateFmt.format(paidAt)),
                      trailing: const Icon(Icons.calendar_month_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: paidAt,
                        );
                        if (picked != null) {
                          setLocalState(() => paidAt = picked);
                        }
                      },
                    ),
                    TextField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Detalle (opcional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    final providerName = providerCtrl.text.trim();
                    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                    if (title.isEmpty || providerName.isEmpty || amount <= 0) {
                      await _showSnack('Completa los campos y el monto');
                      return;
                    }

                    try {
                      final repo = ref.read(contabilidadRepositoryProvider);
                      final service = await repo.createPayableService(
                        title: title,
                        providerKind: providerKind,
                        providerName: providerName,
                        description: noteCtrl.text,
                        frequency: PayableFrequency.oneTime,
                        defaultAmount: amount,
                        nextDueDate: paidAt,
                        active: true,
                      );
                      await repo.registerPayablePayment(
                        serviceId: service.id,
                        amount: amount,
                        paidAt: paidAt,
                        note: noteCtrl.text,
                      );
                      if (!context.mounted) return;
                      Navigator.of(dialogContext).pop(true);
                    } catch (e) {
                      await _showSnack('No se pudo registrar: $e');
                    }
                  },
                  child: const Text('Registrar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (done == true) {
      await _load();
      await _showSnack('Pago directo registrado');
    }
  }

  Future<void> _openRegisterPaymentDialog(PayableService service) async {
    final amountCtrl = TextEditingController(
      text: service.defaultAmount?.toStringAsFixed(2) ?? '',
    );
    final noteCtrl = TextEditingController();
    var paidAt = DateTime.now();

    final done = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Marcar pago como pagado'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(service.providerName),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Monto pagado'),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Fecha de pago'),
                      subtitle: Text(_dateFmt.format(paidAt)),
                      trailing: const Icon(Icons.calendar_month_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: paidAt,
                        );
                        if (picked != null) {
                          setLocalState(() => paidAt = picked);
                        }
                      },
                    ),
                    TextField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Nota (opcional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                    if (amount <= 0) {
                      await _showSnack('Ingresa un monto válido');
                      return;
                    }
                    try {
                      await ref
                          .read(contabilidadRepositoryProvider)
                          .registerPayablePayment(
                            serviceId: service.id,
                            amount: amount,
                            paidAt: paidAt,
                            note: noteCtrl.text,
                          );
                      if (!context.mounted) return;
                      Navigator.of(dialogContext).pop(true);
                    } catch (e) {
                      await _showSnack('No se pudo registrar el pago: $e');
                    }
                  },
                  child: const Text('Marcar pagado'),
                ),
              ],
            );
          },
        );
      },
    );

    if (done == true) {
      await _load();
      await _showSnack('Pago registrado correctamente');
    }
  }

  Future<void> _openReceiptPreview({
    required PayableService service,
    required List<PayablePayment> payments,
    required DateTime from,
    required DateTime to,
  }) async {
    if (payments.isEmpty) {
      await _showSnack('No hay pagos en ese período');
      return;
    }

    final bytes = await buildPayableReceiptPdf(
      data: PayableReceiptPdfData(
        companyName: 'FULLTECH',
        serviceTitle: service.title,
        providerName: service.providerName,
        providerKind: service.providerKind,
        periodFrom: from,
        periodTo: to,
        payments: payments,
      ),
    );

    if (!mounted) return;

    final fileName =
        'comprobante_${service.providerName.replaceAll(' ', '_')}_${DateFormat('yyyyMM').format(from)}.pdf';

    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 900,
          height: 700,
          child: Column(
            children: [
              ListTile(
                title: Text('Comprobante mensual · ${service.providerName}'),
                trailing: IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Compartir PDF',
                  onPressed: () async {
                    await sharePayableReceiptPdf(bytes: bytes, filename: fileName);
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: PdfPreview(
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  build: (_) async => bytes,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMonthlyReceiptForService(PayableService service) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: DateTime.now(),
      helpText: 'Selecciona un día del mes a reportar',
    );
    if (selected == null) return;

    final from = DateTime(selected.year, selected.month, 1);
    final to = DateTime(selected.year, selected.month + 1, 0, 23, 59, 59);
    final monthly = service.payments
        .where((item) => !item.paidAt.isBefore(from) && !item.paidAt.isAfter(to))
        .toList();

    await _openReceiptPreview(
      service: service,
      payments: monthly,
      from: from,
      to: to,
    );
  }

  Future<void> _toggleActive(PayableService service) async {
    try {
      await ref.read(contabilidadRepositoryProvider).updatePayableService(
            id: service.id,
            active: !service.active,
          );
      await _load();
    } catch (e) {
      await _showSnack('No se pudo actualizar estado: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final active = _activeServices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagos pendientes'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      drawer: AppDrawer(currentUser: user),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _openCreateFixedDialog,
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('Agregar servicio fijo'),
                ),
                OutlinedButton.icon(
                  onPressed: _openDirectPaymentDialog,
                  icon: const Icon(Icons.attach_money_outlined),
                  label: const Text('Pago directo'),
                ),
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Servicios pendientes (${active.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (active.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('No hay servicios pendientes registrados'),
                ),
              )
            else
              ...active.map(
                (service) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${service.providerKind.label}: ${service.providerName}',
                        ),
                        Text('Frecuencia: ${service.frequency.label}'),
                        Text('Próximo pago: ${_dateFmt.format(service.nextDueDate)}'),
                        if (service.defaultAmount != null)
                          Text(
                            'Monto estimado: ${_money.format(service.defaultAmount)}',
                          ),
                        if (service.lastPaidAt != null)
                          Text(
                            'Último pago: ${_dateFmt.format(service.lastPaidAt!)}',
                          ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _openRegisterPaymentDialog(service),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Marcar pagado'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _openMonthlyReceiptForService(service),
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Comprobante mensual'),
                            ),
                            TextButton(
                              onPressed: () => _toggleActive(service),
                              child: const Text('Desactivar'),
                            ),
                          ],
                        ),
                        if (service.payments.isNotEmpty) ...[
                          const Divider(height: 18),
                          Text(
                            'Historial (${service.payments.length})',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          ...service.payments.take(3).map(
                                (payment) => ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(_money.format(payment.amount)),
                                  subtitle: Text(_dateFmt.format(payment.paidAt)),
                                ),
                              ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Historial global (${_payments.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (_payments.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Aún no hay pagos registrados'),
                ),
              )
            else
              ..._payments.take(20).map((payment) {
                final service = _findService(payment.serviceId);
                return ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(_money.format(payment.amount)),
                  subtitle: Text(
                    '${service?.providerName ?? '-'} · ${_dateFmt.format(payment.paidAt)}',
                  ),
                  trailing: IconButton(
                    tooltip: 'PDF',
                    onPressed: service == null
                        ? null
                        : () async {
                            final from = DateTime(
                              payment.paidAt.year,
                              payment.paidAt.month,
                              1,
                            );
                            final to = DateTime(
                              payment.paidAt.year,
                              payment.paidAt.month + 1,
                              0,
                              23,
                              59,
                              59,
                            );
                            final monthly = service.payments
                                .where(
                                  (item) =>
                                      !item.paidAt.isBefore(from) &&
                                      !item.paidAt.isAfter(to),
                                )
                                .toList();
                            await _openReceiptPreview(
                              service: service,
                              payments: monthly,
                              from: from,
                              to: to,
                            );
                          },
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
