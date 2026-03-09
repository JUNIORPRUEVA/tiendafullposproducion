import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_repository.dart';
import '../../../core/models/user_model.dart';
import '../../../modules/nomina/data/nomina_repository.dart';
import '../../../modules/nomina/nomina_models.dart';
import '../application/users_controller.dart';
import '../data/users_repository.dart';
import 'work_contract_pdf_service.dart';

class WorkContractPreviewScreen extends ConsumerStatefulWidget {
  final UserModel employee;

  const WorkContractPreviewScreen({super.key, required this.employee});

  @override
  ConsumerState<WorkContractPreviewScreen> createState() =>
      _WorkContractPreviewScreenState();
}

class _WorkContractPreviewScreenState
    extends ConsumerState<WorkContractPreviewScreen> {
  late UserModel _employee;
  late Future<_ContractPreviewData> _pdfFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _employee = widget.employee;
    _pdfFuture = _buildPdf(_employee);
  }

  Future<_ContractPreviewData> _buildPdf(UserModel employee) async {
    final company = await ref
        .read(companySettingsRepositoryProvider)
        .getSettings();
    final payrollSnapshot = await _resolvePayrollSnapshot(employee);

    final bytes = await buildWorkContractPdf(
      employee: employee,
      company: company,
      salario: payrollSnapshot.salaryFormatted,
      moneda: 'DOP',
      periodicidadPago: payrollSnapshot.paymentFrequency,
      metodoPago: payrollSnapshot.paymentMethod,
      puesto: payrollSnapshot.position,
      fechaInicio: employee.workContractStartDate ?? employee.fechaIngreso,
    );

    final safeName = employee.nombreCompleto.trim().isEmpty
        ? 'empleado'
        : employee.nombreCompleto.trim().replaceAll(RegExp(r'\s+'), '_');
    final fileName =
        'contrato_${safeName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';

    return _ContractPreviewData(bytes: bytes, fileName: fileName);
  }

  Future<_PayrollContractSnapshot> _resolvePayrollSnapshot(
    UserModel user,
  ) async {
    final nominaRepo = ref.read(nominaRepositoryProvider);
    PayrollEmployee? payrollEmployee;
    double? baseSalary;
    String? paymentFrequency;

    try {
      final employees = await nominaRepo.listEmployees(activeOnly: false);
      payrollEmployee = _matchPayrollEmployee(user, employees);

      if (payrollEmployee != null) {
        final periods = await nominaRepo.listPeriods();
        periods.sort((a, b) => b.endDate.compareTo(a.endDate));

        for (final period in periods) {
          final config = await nominaRepo.getEmployeeConfig(
            period.id,
            payrollEmployee.id,
          );
          if (config == null || config.baseSalary <= 0) continue;
          baseSalary = config.baseSalary;
          paymentFrequency = _inferPaymentFrequency(
            period.startDate,
            period.endDate,
          );
          break;
        }
      }
    } catch (_) {
      // Si nómina falla, el contrato puede generarse con valores manuales.
    }

    final currency = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$ ',
      decimalDigits: 2,
    );
    final payrollPosition = payrollEmployee?.puesto?.trim();

    return _PayrollContractSnapshot(
      salaryFormatted: (user.workContractSalary ?? '').trim().isNotEmpty
          ? user.workContractSalary!.trim()
          : baseSalary != null && baseSalary > 0
          ? currency.format(baseSalary)
          : null,
      paymentFrequency:
          (user.workContractPaymentFrequency ?? '').trim().isNotEmpty
          ? user.workContractPaymentFrequency!.trim()
          : paymentFrequency ?? 'Quincenal',
      paymentMethod: (user.workContractPaymentMethod ?? '').trim().isNotEmpty
          ? user.workContractPaymentMethod!.trim()
          : _resolvePaymentMethod(user),
      position: (user.workContractJobTitle ?? '').trim().isNotEmpty
          ? user.workContractJobTitle!.trim()
          : (payrollPosition == null || payrollPosition.isEmpty)
          ? null
          : payrollPosition,
    );
  }

  PayrollEmployee? _matchPayrollEmployee(
    UserModel user,
    List<PayrollEmployee> employees,
  ) {
    final exactId = employees.where((employee) => employee.id == user.id);
    if (exactId.isNotEmpty) return exactId.first;

    final normalizedName = user.nombreCompleto.trim().toLowerCase();
    final normalizedPhone = user.telefono.trim();

    for (final employee in employees) {
      final sameName = employee.nombre.trim().toLowerCase() == normalizedName;
      if (!sameName) continue;
      if (normalizedPhone.isEmpty) return employee;
      if ((employee.telefono ?? '').trim() == normalizedPhone) {
        return employee;
      }
    }

    return null;
  }

  String _inferPaymentFrequency(DateTime start, DateTime end) {
    final days = end.difference(start).inDays.abs() + 1;
    if (days <= 8) return 'Semanal';
    if (days <= 17) return 'Quincenal';
    if (days <= 35) return 'Mensual';
    return 'Periodicidad variable';
  }

  String _resolvePaymentMethod(UserModel user) {
    final account = (user.cuentaNominaPreferencial ?? '').trim();
    if (account.isEmpty) return 'Transferencia bancaria';
    return 'Transferencia bancaria a cuenta $account';
  }

  Future<void> _openEditDialog() async {
    final jobTitleCtrl = TextEditingController(
      text: _employee.workContractJobTitle ?? '',
    );
    final salaryCtrl = TextEditingController(
      text: _employee.workContractSalary ?? '',
    );
    final frequencyCtrl = TextEditingController(
      text: _employee.workContractPaymentFrequency ?? '',
    );
    final paymentMethodCtrl = TextEditingController(
      text: _employee.workContractPaymentMethod ?? '',
    );
    final workScheduleCtrl = TextEditingController(
      text: _employee.workContractWorkSchedule ?? '',
    );
    final workLocationCtrl = TextEditingController(
      text: _employee.workContractWorkLocation ?? '',
    );
    final customClausesCtrl = TextEditingController(
      text: _employee.workContractCustomClauses ?? '',
    );
    DateTime? workContractStartDate = _employee.workContractStartDate;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar contrato'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: jobTitleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Cargo contractual',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: salaryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Salario contractual',
                      hintText: 'Ej: RD\$ 25,000.00',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: frequencyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Periodicidad de pago',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: paymentMethodCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Método de pago',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fecha de inicio contractual'),
                    subtitle: Text(
                      workContractStartDate == null
                          ? 'Usar fecha de ingreso'
                          : DateFormat(
                              'dd/MM/yyyy',
                            ).format(workContractStartDate!),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (workContractStartDate != null)
                          IconButton(
                            tooltip: 'Quitar fecha',
                            onPressed: () => setDialogState(
                              () => workContractStartDate = null,
                            ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        const Icon(Icons.calendar_today_outlined),
                      ],
                    ),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            workContractStartDate ??
                            _employee.fechaIngreso ??
                            now,
                        firstDate: DateTime(1990),
                        lastDate: DateTime(now.year + 5),
                      );
                      if (picked != null) {
                        setDialogState(() => workContractStartDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: workScheduleCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Horario contractual',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: workLocationCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Lugar de trabajo contractual',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: customClausesCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Cláusulas especiales',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _saving = true);
                      try {
                        final payload = <String, dynamic>{
                          'workContractJobTitle': jobTitleCtrl.text.trim(),
                          'workContractSalary': salaryCtrl.text.trim(),
                          'workContractPaymentFrequency': frequencyCtrl.text
                              .trim(),
                          'workContractPaymentMethod': paymentMethodCtrl.text
                              .trim(),
                          'workContractWorkSchedule': workScheduleCtrl.text
                              .trim(),
                          'workContractWorkLocation': workLocationCtrl.text
                              .trim(),
                          'workContractCustomClauses': customClausesCtrl.text
                              .trim(),
                          'workContractStartDate': workContractStartDate
                              ?.toIso8601String(),
                        };

                        final updated = await ref
                            .read(usersRepositoryProvider)
                            .updateUser(_employee.id, payload);
                        await ref
                            .read(usersControllerProvider.notifier)
                            .refresh();

                        if (!mounted) return;
                        setState(() {
                          _employee = updated;
                          _pdfFuture = _buildPdf(updated);
                        });
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Contrato actualizado y regenerado'),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(content: Text('No se pudo guardar: $e')),
                        );
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Contrato · ${_employee.nombreCompleto}'),
        actions: [
          IconButton(
            tooltip: 'Editar contrato',
            onPressed: _saving ? null : _openEditDialog,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Regenerar PDF',
            onPressed: () => setState(() => _pdfFuture = _buildPdf(_employee)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_ContractPreviewData>(
        future: _pdfFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text(
                'No se pudo generar el contrato.\n${snapshot.error ?? ''}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final data = snapshot.data!;
          return PdfPreview(
            pdfFileName: data.fileName,
            canChangeOrientation: false,
            canChangePageFormat: false,
            build: (format) async => data.bytes,
          );
        },
      ),
    );
  }
}

class _ContractPreviewData {
  final Uint8List bytes;
  final String fileName;

  const _ContractPreviewData({required this.bytes, required this.fileName});
}

class _PayrollContractSnapshot {
  final String? salaryFormatted;
  final String paymentFrequency;
  final String paymentMethod;
  final String? position;

  const _PayrollContractSnapshot({
    required this.salaryFormatted,
    required this.paymentFrequency,
    required this.paymentMethod,
    required this.position,
  });
}
