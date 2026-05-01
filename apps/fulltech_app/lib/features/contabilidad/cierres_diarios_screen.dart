import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/role_permissions.dart';
import '../../core/models/close_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'application/cierres_diarios_controller.dart';
import 'data/contabilidad_repository.dart';
import 'utils/deposit_order_pdf_service.dart';
import 'widgets/app_card.dart';
import 'widgets/section_title.dart';

class CierresDiariosScreen extends ConsumerStatefulWidget {
  const CierresDiariosScreen({super.key});

  @override
  ConsumerState<CierresDiariosScreen> createState() =>
      _CierresDiariosScreenState();
}

class _CierresDiariosScreenState extends ConsumerState<CierresDiariosScreen> {
  static const _bankOptions = <String>['POPULAR', 'BANRESERVAS', 'BHD', 'OTRO'];
  static const _activeCloseTypes = <CloseType>[
    CloseType.tienda,
    CloseType.phytoemagry,
  ];

  static const _categoryAccount = <CloseType, String>{
    CloseType.tienda: '841088008',
    CloseType.phytoemagry: '846100642',
  };
  static const double _cashReserve = 10000;
  static const double _minTotalForDeposit = 25000;

  final _formKey = GlobalKey<FormState>();
  final _cashCtrl = TextEditingController(text: '0');
  final _transferCtrl = TextEditingController(text: '0');
  final _otherBankCtrl = TextEditingController();
  final _cardCtrl = TextEditingController(text: '0');
  final _otherIncomeCtrl = TextEditingController(text: '0');
  final _expensesCtrl = TextEditingController(text: '0');
  final _cashDeliveredCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();

  CloseType _type = CloseType.tienda;
  String? _transferBankOption;
  DateTime _date = DateTime.now();
  String? _editingId;
  bool _depositReadyNotified = false;

  @override
  void dispose() {
    _cashCtrl.dispose();
    _transferCtrl.dispose();
    _otherBankCtrl.dispose();
    _cardCtrl.dispose();
    _otherIncomeCtrl.dispose();
    _expensesCtrl.dispose();
    _cashDeliveredCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    final state = ref.watch(cierresDiariosControllerProvider);
    final controller = ref.read(cierresDiariosControllerProvider.notifier);
    final canUseModule = canAccessContabilidadByRole(user?.role);
    final selectedType = state.typeFilter ?? CloseType.tienda;
    final depositEval = _evaluateDeposit(state.closes);

    if (canUseModule && depositEval.eligible && !_depositReadyNotified) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _depositReadyNotified = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Hay un depósito pendiente: condiciones cumplidas para generar carta bancaria.',
            ),
          ),
        );
      });
    }
    if (!depositEval.eligible && _depositReadyNotified) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _depositReadyNotified = false);
      });
    }

    if (_type != selectedType && _editingId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _type = selectedType);
      });
    }

    ref.listen<CierresDiariosState>(cierresDiariosControllerProvider, (
      previous,
      next,
    ) {
      final prevId = previous?.editingClose?.id;
      final nextEdit = next.editingClose;
      if (nextEdit != null && nextEdit.id != prevId) {
        _applyEdit(nextEdit);
      }
      if (prevId != null && nextEdit == null) {
        _resetForm();
      }
    });

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Cierres diarios',
        showLogo: false,
        showDepartmentLabel: false,
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      floatingActionButton: canUseModule
          ? _buildDepositFab(context, depositEval)
          : null,
      body: !canUseModule
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Este módulo está disponible solo para ADMIN y ASISTENTE.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildCategoryButtons(selectedType, controller),
                  const SizedBox(height: 12),
                  _buildFormCard(context, state, controller),
                  const SizedBox(height: 14),
                  if (state.loading) const LinearProgressIndicator(),
                  if (state.error != null) ...[
                    const SizedBox(height: 8),
                    _ErrorBox(message: state.error!),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _openHistoryDialog(context, state.closes),
                      icon: const Icon(Icons.history),
                      label: Text(
                        'Historial de cierres (${state.closes.length})',
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDepositFab(
    BuildContext context,
    _DepositEvaluation depositEval,
  ) {
    final amountFmt = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
    final label = depositEval.eligible
        ? 'Depósito pendiente ${amountFmt.format(depositEval.depositableAmount)}'
        : 'Orden de depósito';

    return FloatingActionButton.extended(
      onPressed: () => _openDepositPanel(context, depositEval),
      backgroundColor: depositEval.eligible
          ? Theme.of(context).colorScheme.error
          : AppTheme.primaryColor,
      foregroundColor: Colors.white,
      icon: Icon(
        depositEval.eligible
            ? Icons.notifications_active_outlined
            : Icons.account_balance_outlined,
      ),
      label: Text(label),
    );
  }

  Future<void> _openDepositPanel(
    BuildContext context,
    _DepositEvaluation eval,
  ) async {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Orden automática de depósito',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Banco destino: Banco Popular · Ventana: ${_dateOnly(eval.windowFrom)} - ${_dateOnly(eval.windowTo)}',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MoneyPill(
                    label: 'Efectivo disponible',
                    value: money.format(eval.totalAvailableCash),
                  ),
                  _MoneyPill(
                    label: 'Fondo en caja',
                    value: money.format(_cashReserve),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!eval.eligible)
                ...eval.reasons
                    .map(
                      (reason) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $reason',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                    .toList()
              else ...[
                const Text(
                  'Distribución por cuenta:',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                ..._activeCloseTypes.map((type) {
                  final amount = eval.depositByType[type] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${_typeLabel(type)} · Cuenta ${_categoryAccount[type]} · ${money.format(amount)}',
                    ),
                  );
                }),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: eval.eligible
                      ? () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await ref
                                .read(contabilidadRepositoryProvider)
                                .createDepositOrder(
                                  windowFrom: eval.windowFrom,
                                  windowTo: eval.windowTo,
                                  bankName: 'BANCO POPULAR',
                                  reserveAmount: _cashReserve,
                                  totalAvailableCash: eval.totalAvailableCash,
                                  depositTotal: eval.depositableAmount,
                                  closesCountByType: {
                                    for (final type in _activeCloseTypes)
                                      _depositKeyForType(type):
                                          eval.countByType[type] ?? 0,
                                  },
                                  depositByType: {
                                    for (final type in _activeCloseTypes)
                                      _depositKeyForType(type):
                                          eval.depositByType[type] ?? 0,
                                  },
                                  accountByType: {
                                    for (final type in _activeCloseTypes)
                                      _depositKeyForType(type):
                                          _categoryAccount[type] ?? '',
                                  },
                                );
                          } catch (e) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'No se pudo registrar la orden en nube: $e',
                                ),
                              ),
                            );
                            return;
                          }

                          final bytes = await buildDepositOrderPdf(
                            data: DepositOrderPdfData(
                              generatedAt: DateTime.now(),
                              windowFrom: eval.windowFrom,
                              windowTo: eval.windowTo,
                              bankName: 'BANCO POPULAR',
                              reserveInCash: _cashReserve,
                              totalAvailableCash: eval.totalAvailableCash,
                              depositTotal: eval.depositableAmount,
                              closesCountByType: {
                                for (final type in _activeCloseTypes)
                                  _depositKeyForType(type):
                                      eval.countByType[type] ?? 0,
                              },
                              depositByType: {
                                for (final type in _activeCloseTypes)
                                  _depositKeyForType(type):
                                      eval.depositByType[type] ?? 0,
                              },
                              accountByType: {
                                for (final type in _activeCloseTypes)
                                  _depositKeyForType(type):
                                      _categoryAccount[type] ?? '',
                              },
                            ),
                          );

                          if (!context.mounted) return;
                          await _openDepositPdfPreview(context, bytes);
                        }
                      : null,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Generar carta PDF'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDepositPdfPreview(
    BuildContext context,
    Uint8List pdfBytes,
  ) async {
    final filename =
        'carta_deposito_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 960,
          height: 700,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Carta de depósito bancario',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Descargar / compartir',
                      onPressed: () async {
                        await Printing.sharePdf(
                          bytes: pdfBytes,
                          filename: filename,
                        );
                      },
                      icon: const Icon(Icons.download_outlined),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PdfPreview(
                  canChangePageFormat: false,
                  canDebug: false,
                  allowPrinting: true,
                  allowSharing: true,
                  build: (_) async => pdfBytes,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryButtons(
    CloseType selectedType,
    CierresDiariosController controller,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(title: 'Historial por categoría'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CategoryButton(
                  label: 'Tienda',
                  selected: selectedType == CloseType.tienda,
                  onPressed: () => controller.setTypeFilter(CloseType.tienda),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CategoryButton(
                  label: 'PhytoEmagry',
                  selected: selectedType == CloseType.phytoemagry,
                  onPressed: () =>
                      controller.setTypeFilter(CloseType.phytoemagry),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(
    BuildContext context,
    CierresDiariosState state,
    CierresDiariosController controller,
  ) {
    final editing = state.editingClose != null;
    final transfer = _toMoney(_transferCtrl.text);
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
    final cash = _toMoney(_cashCtrl.text);
    final card = _toMoney(_cardCtrl.text);
    final otherIncome = _toMoney(_otherIncomeCtrl.text);
    final expenses = _toMoney(_expensesCtrl.text);
    final delivered = _toMoney(_cashDeliveredCtrl.text);
    final totalIncome = cash + transfer + card + otherIncome;
    final netTotal = totalIncome - expenses;
    final difference = cash - delivered;
    final locked =
        state.editingClose?.isApproved == true ||
        state.editingClose?.isRejected == true;

    return AppCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              title: editing
                  ? 'Editar cierre ${_type.label}'
                  : 'Nuevo cierre ${_type.label}',
              trailing: editing
                  ? TextButton(
                      onPressed: () {
                        controller.cancelEditing();
                        _resetForm();
                      },
                      child: const Text('Cancelar edición'),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Categoría activa'),
              child: Text(
                _type.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: editing
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2100),
                      );
                      if (picked == null) return;
                      setState(() => _date = picked);
                    },
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Fecha del cierre',
                ),
                child: Text(_dateOnly(_date)),
              ),
            ),
            if (locked) ...[
              _StatusNotice(close: state.editingClose!),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            _moneyField(_cashCtrl, 'Efectivo declarado'),
            const SizedBox(height: 10),
            _moneyField(
              _transferCtrl,
              'Transferencia',
              onChanged: (_) => setState(() {}),
            ),
            if (transfer > 0) ...[
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(10),
                          topRight: Radius.circular(10),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Banco',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            'Monto',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _transferBankOption,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                hintText: 'Selecciona banco',
                                isDense: true,
                              ),
                              items: _bankOptions
                                  .map(
                                    (bank) => DropdownMenuItem(
                                      value: bank,
                                      child: Text(
                                        _bankLabel(bank),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _transferBankOption = value;
                                });
                              },
                              validator: (value) {
                                if (transfer > 0 &&
                                    (value == null || value.isEmpty)) {
                                  return 'Requerido';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              money.format(transfer),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_transferBankOption == 'OTRO') ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _otherBankCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Indica otro banco',
                  ),
                  validator: (value) {
                    if (_transferBankOption == 'OTRO' &&
                        (value == null || value.trim().isEmpty)) {
                      return 'Debes indicar el banco';
                    }
                    return null;
                  },
                ),
              ],
            ],
            const SizedBox(height: 10),
            _moneyField(_cardCtrl, 'Pago con tarjeta'),
            const SizedBox(height: 10),
            _moneyField(_otherIncomeCtrl, 'Otros ingresos'),
            const SizedBox(height: 10),
            _moneyField(_expensesCtrl, 'Gastos del día'),
            const SizedBox(height: 10),
            _moneyField(_cashDeliveredCtrl, 'Efectivo entregado'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notas',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _CloseSummaryBlock(
              totalIncome: totalIncome,
              netTotal: netTotal,
              cashDeclared: cash,
              cashDelivered: delivered,
              difference: difference,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: state.saving || locked
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;

                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Confirmar cierre diario'),
                            content: const Text(
                              'Are you sure you want to submit this daily closing?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Confirmar'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;

                        await controller.saveClose(
                          type: _type,
                          date: _date,
                          cash: _toMoney(_cashCtrl.text),
                          transfer: _toMoney(_transferCtrl.text),
                          transferBank: _selectedBankValue(),
                          card: _toMoney(_cardCtrl.text),
                          otherIncome: _toMoney(_otherIncomeCtrl.text),
                          expenses: _toMoney(_expensesCtrl.text),
                          cashDelivered: _toMoney(_cashDeliveredCtrl.text),
                          notes: _notesCtrl.text,
                        );
                      },
                icon: state.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(editing ? Icons.save_outlined : Icons.add_circle),
                label: const Text('Confirmar y enviar cierre'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextFormField _moneyField(
    TextEditingController controller,
    String label, {
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, prefixText: '\$ '),
      onChanged: (value) {
        setState(() {});
        onChanged?.call(value);
      },
      validator: (value) {
        final amount = _toMoney(value);
        if (amount < 0) return 'No puede ser negativo';
        return null;
      },
    );
  }

  void _applyEdit(CloseModel close) {
    setState(() {
      _editingId = close.id;
      _type = close.type;
      _date = close.date;
      _cashCtrl.text = close.cash.toStringAsFixed(2);
      _transferCtrl.text = close.transfer.toStringAsFixed(2);
      final rawBank = (close.transferBank ?? '').trim();
      final normalized = rawBank.toUpperCase();
      if (_bankOptions.contains(normalized)) {
        _transferBankOption = normalized;
        _otherBankCtrl.clear();
      } else if (rawBank.isNotEmpty) {
        _transferBankOption = 'OTRO';
        _otherBankCtrl.text = rawBank;
      } else {
        _transferBankOption = null;
        _otherBankCtrl.clear();
      }
      _cardCtrl.text = close.card.toStringAsFixed(2);
      _otherIncomeCtrl.text = close.otherIncome.toStringAsFixed(2);
      _expensesCtrl.text = close.expenses.toStringAsFixed(2);
      _cashDeliveredCtrl.text = close.cashDelivered.toStringAsFixed(2);
      _notesCtrl.text = close.notes ?? '';
    });
  }

  void _duplicateRejectedClose(CloseModel close) {
    ref.read(cierresDiariosControllerProvider.notifier).cancelEditing();
    setState(() {
      _editingId = null;
      _type = close.type;
      _date = close.date;
      _cashCtrl.text = close.cash.toStringAsFixed(2);
      _transferCtrl.text = close.transfer.toStringAsFixed(2);
      final rawBank = (close.transferBank ?? '').trim();
      final normalized = rawBank.toUpperCase();
      if (_bankOptions.contains(normalized)) {
        _transferBankOption = normalized;
        _otherBankCtrl.clear();
      } else if (rawBank.isNotEmpty) {
        _transferBankOption = 'OTRO';
        _otherBankCtrl.text = rawBank;
      } else {
        _transferBankOption = null;
        _otherBankCtrl.clear();
      }
      _cardCtrl.text = close.card.toStringAsFixed(2);
      _otherIncomeCtrl.text = close.otherIncome.toStringAsFixed(2);
      _expensesCtrl.text = close.expenses.toStringAsFixed(2);
      _cashDeliveredCtrl.text = close.cashDelivered.toStringAsFixed(2);
      _notesCtrl.text = [
        if ((close.notes ?? '').trim().isNotEmpty) close.notes!.trim(),
        'Correccion de cierre rechazado ${DateFormat('dd/MM/yyyy').format(close.date)}',
      ].join('\n');
    });
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _type =
          ref.read(cierresDiariosControllerProvider).typeFilter ??
          CloseType.tienda;
      _date = DateTime.now();
      _cashCtrl.text = '0';
      _transferCtrl.text = '0';
      _transferBankOption = null;
      _otherBankCtrl.clear();
      _cardCtrl.text = '0';
      _otherIncomeCtrl.text = '0';
      _expensesCtrl.text = '0';
      _cashDeliveredCtrl.text = '0';
      _notesCtrl.clear();
    });
  }

  String? _selectedBankValue() {
    final transfer = _toMoney(_transferCtrl.text);
    if (transfer <= 0) return null;
    final option = _transferBankOption;
    if (option == null || option.isEmpty) return null;
    if (option == 'OTRO') {
      final other = _otherBankCtrl.text.trim();
      return other.isEmpty ? null : other;
    }
    return option;
  }

  String _bankLabel(String raw) {
    switch (raw) {
      case 'POPULAR':
        return 'Banco Popular';
      case 'BANRESERVAS':
        return 'Banreservas';
      case 'BHD':
        return 'BHD';
      case 'OTRO':
        return 'Otro';
      default:
        return raw;
    }
  }

  String _dateOnly(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  _DepositEvaluation _evaluateDeposit(List<CloseModel> closes) {
    final now = DateTime.now();
    final windowFrom = DateTime(now.year, now.month, now.day - 1);
    final windowTo = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final byTypeCount = {for (final type in _activeCloseTypes) type: 0};
    final byTypeCash = {for (final type in _activeCloseTypes) type: 0.0};

    for (final close in closes) {
      if (close.date.isBefore(windowFrom) || close.date.isAfter(windowTo)) {
        continue;
      }
      byTypeCount[close.type] = (byTypeCount[close.type] ?? 0) + 1;

      final netCash = (close.cash - close.expenses - close.cashDelivered)
          .clamp(0, double.infinity)
          .toDouble();
      byTypeCash[close.type] = (byTypeCash[close.type] ?? 0) + netCash;
    }

    final totalCash = byTypeCash.values.fold<double>(
      0,
      (sum, item) => sum + item,
    );
    final depositable = (totalCash - _cashReserve)
        .clamp(0, double.infinity)
        .toDouble();

    final reasons = <String>[];
    final countCondition = _activeCloseTypes.every(
      (type) => (byTypeCount[type] ?? 0) >= 2,
    );
    if (!countCondition) {
      reasons.add(
        'Se requieren al menos 2 cierres por categoría en los últimos 2 días.',
      );
    }
    if (totalCash < _minTotalForDeposit) {
      reasons.add(
        'Se requieren RD\$ 25,000 o más en efectivo neto acumulado (actual: ${NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ').format(totalCash)}).',
      );
    }
    if (depositable <= 0) {
      reasons.add(
        'No hay monto disponible para depositar después del fondo en caja.',
      );
    }

    final eligible =
        countCondition && totalCash >= _minTotalForDeposit && depositable > 0;

    final depositByType = {for (final type in _activeCloseTypes) type: 0.0};

    if (eligible) {
      final positive = byTypeCash.entries
          .where((entry) => entry.value > 0)
          .toList();
      if (positive.isNotEmpty) {
        var assigned = 0.0;
        for (final entry in positive) {
          final share = entry.value / totalCash;
          final amount = (depositable * share);
          final rounded = double.parse(amount.toStringAsFixed(2));
          depositByType[entry.key] = rounded;
          assigned += rounded;
        }

        final delta = double.parse((depositable - assigned).toStringAsFixed(2));
        if (delta != 0) {
          final maxType = positive
              .reduce((a, b) => a.value >= b.value ? a : b)
              .key;
          depositByType[maxType] = double.parse(
            ((depositByType[maxType] ?? 0) + delta).toStringAsFixed(2),
          );
        }
      }
    }

    return _DepositEvaluation(
      windowFrom: windowFrom,
      windowTo: windowTo,
      eligible: eligible,
      reasons: reasons,
      totalAvailableCash: totalCash,
      depositableAmount: depositable,
      countByType: byTypeCount,
      depositByType: depositByType,
    );
  }

  double _toMoney(String? raw) {
    if (raw == null) return 0;
    final normalized = raw.replaceAll(',', '.').trim();
    return double.tryParse(normalized) ?? 0;
  }

  Future<void> _openHistoryDialog(
    BuildContext context,
    List<CloseModel> closes,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        CloseType selectedType = _type;
        String selectedBank = 'TODOS';
        DateTime? fromDate;
        DateTime? toDate;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = closes.where((close) {
              if (close.type != selectedType) return false;
              if (fromDate != null) {
                final from = DateTime(
                  fromDate!.year,
                  fromDate!.month,
                  fromDate!.day,
                );
                if (close.date.isBefore(from)) return false;
              }
              if (toDate != null) {
                final to = DateTime(
                  toDate!.year,
                  toDate!.month,
                  toDate!.day,
                  23,
                  59,
                  59,
                );
                if (close.date.isAfter(to)) return false;
              }
              if (selectedBank != 'TODOS') {
                final bank = (close.transferBank ?? '').trim().toUpperCase();
                if (selectedBank == 'SIN_BANCO') {
                  if (bank.isNotEmpty) return false;
                } else if (bank != selectedBank) {
                  return false;
                }
              }
              return true;
            }).toList();

            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 920,
                  maxHeight: 650,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Historial de cierres diarios',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final range = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2100),
                                initialDateRange: DateTimeRange(
                                  start: fromDate ?? DateTime.now(),
                                  end: toDate ?? DateTime.now(),
                                ),
                              );
                              if (range == null) return;
                              setDialogState(() {
                                fromDate = range.start;
                                toDate = range.end;
                              });
                            },
                            icon: const Icon(Icons.date_range_outlined),
                            label: Text(
                              fromDate == null || toDate == null
                                  ? 'Rango'
                                  : '${_dateOnly(fromDate!)} - ${_dateOnly(toDate!)}',
                            ),
                          ),
                          if (fromDate != null || toDate != null)
                            TextButton(
                              onPressed: () {
                                setDialogState(() {
                                  fromDate = null;
                                  toDate = null;
                                });
                              },
                              child: const Text('Limpiar rango'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Tienda'),
                            selected: selectedType == CloseType.tienda,
                            onSelected: (_) => setDialogState(
                              () => selectedType = CloseType.tienda,
                            ),
                          ),
                          FilterChip(
                            label: const Text('PhytoEmagry'),
                            selected: selectedType == CloseType.phytoemagry,
                            onSelected: (_) => setDialogState(
                              () => selectedType = CloseType.phytoemagry,
                            ),
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedBank,
                              items: const [
                                DropdownMenuItem(
                                  value: 'TODOS',
                                  child: Text('Banco: Todos'),
                                ),
                                DropdownMenuItem(
                                  value: 'POPULAR',
                                  child: Text('Banco: Popular'),
                                ),
                                DropdownMenuItem(
                                  value: 'BANRESERVAS',
                                  child: Text('Banco: Banreservas'),
                                ),
                                DropdownMenuItem(
                                  value: 'BHD',
                                  child: Text('Banco: BHD'),
                                ),
                                DropdownMenuItem(
                                  value: 'OTRO',
                                  child: Text('Banco: Otro'),
                                ),
                                DropdownMenuItem(
                                  value: 'SIN_BANCO',
                                  child: Text('Banco: Sin registro'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(() => selectedBank = value);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${filtered.length} resultados',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      if (filtered.isEmpty)
                        const Expanded(
                          child: Center(
                            child: Text(
                              'No hay cierres para el filtro seleccionado.',
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              return _HistoryCloseTile(
                                close: filtered[index],
                                onDuplicate: () {
                                  Navigator.of(context).pop();
                                  _duplicateRejectedClose(filtered[index]);
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DepositEvaluation {
  final DateTime windowFrom;
  final DateTime windowTo;
  final bool eligible;
  final List<String> reasons;
  final double totalAvailableCash;
  final double depositableAmount;
  final Map<CloseType, int> countByType;
  final Map<CloseType, double> depositByType;

  const _DepositEvaluation({
    required this.windowFrom,
    required this.windowTo,
    required this.eligible,
    required this.reasons,
    required this.totalAvailableCash,
    required this.depositableAmount,
    required this.countByType,
    required this.depositByType,
  });
}

String _typeLabel(CloseType type) {
  switch (type) {
    case CloseType.capsulas:
      return 'Pastilla';
    case CloseType.tienda:
      return 'Tienda';
    case CloseType.phytoemagry:
      return 'PhytoEmagry';
    case CloseType.pos:
      return 'Software';
  }
}

String _depositKeyForType(CloseType type) {
  switch (type) {
    case CloseType.capsulas:
      return 'CAPSULAS';
    case CloseType.tienda:
      return 'TIENDA';
    case CloseType.phytoemagry:
      return 'PHYTOEMAGRY';
    case CloseType.pos:
      return 'POS';
  }
}

class _MoneyPill extends StatelessWidget {
  final String label;
  final String value;

  const _MoneyPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _CategoryButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        backgroundColor: selected ? AppTheme.primaryColor : Colors.white,
        foregroundColor: selected ? Colors.white : AppTheme.primaryColor,
        side: BorderSide(color: AppTheme.primaryColor),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, textAlign: TextAlign.center, maxLines: 1),
      ),
    );
  }
}

class _CloseSummaryBlock extends StatelessWidget {
  final double totalIncome;
  final double netTotal;
  final double cashDeclared;
  final double cashDelivered;
  final double difference;

  const _CloseSummaryBlock({
    required this.totalIncome,
    required this.netTotal,
    required this.cashDeclared,
    required this.cashDelivered,
    required this.difference,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MoneyPill(label: 'Total ingresos', value: money.format(totalIncome)),
          _MoneyPill(label: 'Total neto', value: money.format(netTotal)),
          _MoneyPill(
            label: 'Efectivo declarado',
            value: money.format(cashDeclared),
          ),
          _MoneyPill(
            label: 'Efectivo entregado',
            value: money.format(cashDelivered),
          ),
          _MoneyPill(label: 'Diferencia', value: money.format(difference)),
        ],
      ),
    );
  }
}

class _StatusNotice extends StatelessWidget {
  final CloseModel close;

  const _StatusNotice({required this.close});

  @override
  Widget build(BuildContext context) {
    final approved = close.isApproved;
    final scheme = Theme.of(context).colorScheme;
    final text = approved
        ? 'Este cierre ya fue aprobado y no se puede editar.'
        : 'Este cierre fue rechazado. Duplica los datos para registrar una correccion.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: approved ? Colors.green.shade50 : scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: approved ? Colors.green.shade200 : scheme.error,
        ),
      ),
      child: Row(
        children: [
          Icon(
            approved ? Icons.verified_outlined : Icons.block_outlined,
            color: approved ? Colors.green.shade700 : scheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: approved
                    ? Colors.green.shade900
                    : scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _HistoryCloseTile extends ConsumerWidget {
  final CloseModel close;
  final VoidCallback onDuplicate;

  const _HistoryCloseTile({required this.close, required this.onDuplicate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
    final transferBank = (close.transferBank ?? '').trim();
    final currentRole = ref.watch(authStateProvider).user?.role;
    final canReview = currentRole == 'ADMIN' || currentRole == 'ASISTENTE';
    final statusLabel = switch (close.status) {
      'approved' => 'Aprobado',
      'rejected' => 'Rechazado',
      _ => 'Pendiente',
    };

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Text(
          '${close.type.label} · ${DateFormat('dd/MM/yyyy').format(close.date)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          'Total ingresos: ${money.format(close.incomeTotal)} - Neto: ${money.format(close.netTotal)} - $statusLabel',
        ),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MoneyPill(
                label: 'Total ingresos',
                value: money.format(close.incomeTotal),
              ),
              _MoneyPill(
                label: 'Total neto',
                value: money.format(close.netTotal),
              ),
              _MoneyPill(
                label: 'Diferencia',
                value: money.format(close.difference),
              ),
              _MoneyPill(label: 'Efectivo', value: money.format(close.cash)),
              _MoneyPill(
                label: 'Transferencia',
                value: money.format(close.transfer),
              ),
              _MoneyPill(label: 'Tarjeta', value: money.format(close.card)),
              _MoneyPill(
                label: 'Otros ingresos',
                value: money.format(close.otherIncome),
              ),
              _MoneyPill(label: 'Gastos', value: money.format(close.expenses)),
              _MoneyPill(
                label: 'Efectivo entregado',
                value: money.format(close.cashDelivered),
              ),
              _InfoPill(label: 'Estado', value: statusLabel),
              _InfoPill(
                label: 'Creado por',
                value: close.createdByName ?? close.createdById ?? 'N/D',
              ),
            ],
          ),
          if (close.transfer > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Banco: ${_humanBank(transferBank)} · Monto: ${money.format(close.transfer)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Creado por: ${close.createdByName ?? close.createdById ?? 'N/D'} · ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(close.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if ((close.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Notas: ${close.notes!.trim()}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
          if (close.reviewedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Revisado por: ${close.reviewedByName ?? close.reviewedById ?? 'N/D'} - ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(close.reviewedAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (close.isPending && canReview) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(cierresDiariosControllerProvider.notifier)
                        .rejectClose(close.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Rechazar'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () async {
                    await ref
                        .read(cierresDiariosControllerProvider.notifier)
                        .approveClose(close.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Aprobar'),
                ),
              ],
            ),
          ],
          if (close.isRejected) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onDuplicate,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Duplicar para corregir'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _humanBank(String raw) {
  final normalized = raw.trim().toUpperCase();
  switch (normalized) {
    case 'POPULAR':
      return 'Banco Popular';
    case 'BANRESERVAS':
      return 'Banreservas';
    case 'BHD':
      return 'BHD';
    case 'OTRO':
      return 'Otro';
    default:
      return raw.isEmpty ? 'No indicado' : raw;
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: scheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
