import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/close_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'application/cierres_diarios_controller.dart';
import 'data/contabilidad_repository.dart';
import 'widgets/app_card.dart';
import 'widgets/section_title.dart';
import 'deposit_bank_catalog.dart';

DepositBankOption? _resolveDepositBank(String? bankName) {
  final normalized = (bankName ?? '').trim().toLowerCase();
  for (final bank in depositBankCatalog) {
    if (bank.id == normalized || bank.label.toLowerCase() == normalized) {
      return bank;
    }
  }
  return null;
}

class CierresDiariosScreen extends ConsumerStatefulWidget {
  const CierresDiariosScreen({super.key});

  @override
  ConsumerState<CierresDiariosScreen> createState() =>
      _CierresDiariosScreenState();
}

class _CierresDiariosScreenState extends ConsumerState<CierresDiariosScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cashCtrl = TextEditingController(text: '0');
  final _cardCtrl = TextEditingController(text: '0');
  final _otherIncomeCtrl = TextEditingController(text: '0');
  final _expensesCtrl = TextEditingController(text: '0');
  final _cashDeliveredCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();

  CloseType _type = CloseType.tienda;
  DateTime _date = DateTime.now();
  String? _editingId;
  final List<_TransferDraft> _transferEntries = [];
  final List<_ExpenseDraft> _expenseEntries = [];
  CloseTransferVoucherModel? _posVoucher;
  bool _uploadingPosVoucher = false;

  @override
  void dispose() {
    _cashCtrl.dispose();
    for (final entry in _transferEntries) {
      entry.dispose();
    }
    for (final expense in _expenseEntries) {
      expense.dispose();
    }
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
    final canUseModule = user != null;
    final selectedType = state.typeFilter ?? CloseType.tienda;

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
      floatingActionButton: null,
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
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: _buildFormCard(context, state, controller),
                    ),
                  ),
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
                      onPressed: () => _openHistoryScreen(context),
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

  Widget _buildFormCard(
    BuildContext context,
    CierresDiariosState state,
    CierresDiariosController controller,
  ) {
    final editing = state.editingClose != null;
    final transfer = _transferEntries.fold<double>(
      0,
      (sum, entry) => sum + _toMoney(entry.amountCtrl.text),
    );
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
    final cash = _toMoney(_cashCtrl.text);
    final card = _toMoney(_cardCtrl.text);
    final otherIncome = _toMoney(_otherIncomeCtrl.text);
    final expenses = _expenseEntries.isEmpty
        ? _toMoney(_expensesCtrl.text)
        : _expenseEntries.fold<double>(
            0,
            (sum, expense) => sum + _toMoney(expense.amountCtrl.text),
          );
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
              title: editing ? 'Editar cierre ${_type.label}' : 'Nuevo cierre',
              trailing: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _UnitChipButton(
                    label: 'Tienda',
                    selected: _type == CloseType.tienda,
                    onPressed: editing
                        ? null
                        : () =>
                            _trySelectType(CloseType.tienda, state, controller),
                  ),
                  _UnitChipButton(
                    label: 'PhytoEmagry',
                    selected: _type == CloseType.phytoemagry,
                    onPressed: editing
                        ? null
                        : () => _trySelectType(
                            CloseType.phytoemagry,
                            state,
                            controller,
                          ),
                  ),
                  if (editing)
                    TextButton(
                      onPressed: () {
                        controller.cancelEditing();
                        _resetForm();
                      },
                      child: const Text('Cancelar edición'),
                    ),
                ],
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
                      if (_hasActiveCloseFor(
                        picked,
                        _type,
                        state,
                        excludingId: _editingId,
                      )) {
                        _showDuplicateDateMessage();
                        return;
                      }
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
            _buildTransferSection(money),
            const SizedBox(height: 10),
            _moneyField(_cardCtrl, 'Pago con tarjeta'),
            const SizedBox(height: 10),
            _moneyField(_otherIncomeCtrl, 'Otros ingresos'),
            const SizedBox(height: 10),
            _buildExpensesSection(money),
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
            _buildPosVoucherSection(),
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
                        for (final entry in _transferEntries) {
                          if (entry.bankCtrl.text.trim().isEmpty ||
                              _toMoney(entry.amountCtrl.text) <= 0 ||
                              entry.vouchers.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Cada transferencia requiere banco, monto mayor a cero y al menos un voucher.',
                                ),
                              ),
                            );
                            return;
                          }
                        }

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

                        if (!editing &&
                            _hasActiveCloseFor(
                              _date,
                              _type,
                              state,
                              excludingId: _editingId,
                            )) {
                          _showDuplicateDateMessage();
                          return;
                        }

                        await controller.saveClose(
                          type: _type,
                          date: _date,
                          cash: _toMoney(_cashCtrl.text),
                          transfer: transfer,
                          transfers: _transferPayload(),
                          card: _toMoney(_cardCtrl.text),
                          otherIncome: _toMoney(_otherIncomeCtrl.text),
                          expenses: expenses,
                          cashDelivered: _toMoney(_cashDeliveredCtrl.text),
                          notes: _notesCtrl.text,
                          posVoucher: _posVoucher,
                          expenseDetails: _expensePayload(),
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

  Widget _buildTransferSection(NumberFormat money) {
    final total = _transferEntries.fold<double>(
      0,
      (sum, entry) => sum + _toMoney(entry.amountCtrl.text),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Transferencias ${money.format(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Agregar transferencia',
                onPressed: () {
                  setState(() => _transferEntries.add(_TransferDraft()));
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (_transferEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Sin transferencias',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ..._transferEntries.asMap().entries.map((entry) {
              final index = entry.key;
              final draft = entry.value;
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _TransferEntryEditor(
                  index: index,
                  draft: draft,
                  onChanged: () => setState(() {}),
                  onRemove: () {
                    setState(() {
                      _transferEntries.removeAt(index).dispose();
                    });
                  },
                  onPickVoucher: () => _pickVoucher(draft),
                  onOpenVoucher: (voucher) => _openVoucherPreview(voucher),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildExpensesSection(NumberFormat money) {
    final total = _expenseEntries.fold<double>(
      0,
      (sum, entry) => sum + _toMoney(entry.amountCtrl.text),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Gastos del día ${money.format(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Agregar gasto',
                onPressed: () {
                  setState(() => _expenseEntries.add(_ExpenseDraft()));
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (_expenseEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Sin gastos registrados. Agrega concepto y monto.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else ...[
            const SizedBox(height: 10),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1),
                2: IntrinsicColumnWidth(),
              },
              border: TableBorder.symmetric(
                inside: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                  ),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Concepto', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Monto', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Acciones', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                for (var index = 0; index < _expenseEntries.length; index++)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextFormField(
                          controller: _expenseEntries[index].conceptCtrl,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Nombre del gasto',
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Concepto requerido';
                            }
                            return null;
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextFormField(
                          controller: _expenseEntries[index].amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: '0.00',
                            prefixText: '\$ ',
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (value) {
                            final amount = _toMoney(value);
                            if (amount <= 0) {
                              return 'Mayor a 0';
                            }
                            return null;
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Eliminar gasto',
                          onPressed: () {
                            setState(() {
                              _expenseEntries.removeAt(index).dispose();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickVoucher(_TransferDraft draft) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => draft.uploading = true);
    final repo = ref.read(contabilidadRepositoryProvider);
    try {
      for (final file in result.files) {
        final uploaded = await repo.uploadCloseVoucher(file);
        draft.vouchers.add(uploaded);
      }
    } finally {
      if (mounted) setState(() => draft.uploading = false);
    }
  }

  void _openVoucherPreview(CloseTransferVoucherModel voucher) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(voucher.fileName),
                trailing: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: voucher.mimeType.startsWith('image/')
                    ? InteractiveViewer(child: Image.network(voucher.fileUrl))
                    : Center(
                        child: Text(
                          voucher.fileUrl,
                          textAlign: TextAlign.center,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _transferPayload() {
    return _transferEntries.map((entry) {
      return {
        'bankName': entry.bankCtrl.text.trim(),
        'amount': _toMoney(entry.amountCtrl.text),
        if (entry.referenceCtrl.text.trim().isNotEmpty)
          'referenceNumber': entry.referenceCtrl.text.trim(),
        if (entry.noteCtrl.text.trim().isNotEmpty)
          'note': entry.noteCtrl.text.trim(),
        'vouchers': entry.vouchers.map((item) => item.toJson()).toList(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _expensePayload() {
    return _expenseEntries
        .where((e) => e.conceptCtrl.text.trim().isNotEmpty)
        .map(
          (e) => {
            'concept': e.conceptCtrl.text.trim(),
            'amount': _toMoney(e.amountCtrl.text),
          },
        )
        .toList();
  }

  Widget _buildPosVoucherSection() {
    final voucher = _posVoucher;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Boucher cierre POS (opcional)'),
        if (voucher != null) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: voucher.mimeType.startsWith('image/')
                ? const Icon(Icons.image_outlined, size: 32)
                : const Icon(Icons.picture_as_pdf_outlined, size: 32),
            title: Text(voucher.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text('Toca para previsualizar'),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Quitar voucher POS',
              onPressed: () => setState(() => _posVoucher = null),
            ),
            onTap: () => _openVoucherPreview(voucher),
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: _uploadingPosVoucher ? null : _pickPosVoucher,
            icon: _uploadingPosVoucher
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
            label: const Text('Subir boucher del POS'),
          ),
        ],
      ],
    );
  }

  Future<void> _pickPosVoucher() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _uploadingPosVoucher = true);
    try {
      final uploaded = await ref
          .read(contabilidadRepositoryProvider)
          .uploadPosVoucher(result.files.first);
      if (mounted) setState(() => _posVoucher = uploaded);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir voucher POS: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPosVoucher = false);
    }
  }

  void _applyEdit(CloseModel close) {
    setState(() {
      _editingId = close.id;
      _type = close.type;
      _date = close.date;
      _cashCtrl.text = close.cash.toStringAsFixed(2);
      for (final entry in _transferEntries) {
        entry.dispose();
      }
      _transferEntries
        ..clear()
        ..addAll(close.transfers.map(_TransferDraft.fromModel));
      _cardCtrl.text = close.card.toStringAsFixed(2);
      _otherIncomeCtrl.text = close.otherIncome.toStringAsFixed(2);
      _expensesCtrl.text = close.expenses.toStringAsFixed(2);
      _expenseEntries.clear();
      if (close.expenses > 0) {
        _expenseEntries.add(_ExpenseDraft(amount: close.expenses.toStringAsFixed(2)));
      }
      _cashDeliveredCtrl.text = close.cashDelivered.toStringAsFixed(2);
      _notesCtrl.text = close.notes ?? '';
      _posVoucher = close.evidenceUrl != null && close.evidenceFileName != null
          ? CloseTransferVoucherModel(
              fileUrl: close.evidenceUrl!,
              fileName: close.evidenceFileName!,
              mimeType: close.evidenceMimeType ?? 'image/jpeg',
              storageKey: close.evidenceStorageKey ?? '',
            )
          : null;
    });
  }

  void _duplicateRejectedClose(CloseModel close) {
    ref.read(cierresDiariosControllerProvider.notifier).cancelEditing();
    setState(() {
      _editingId = null;
      _type = close.type;
      _date = close.date;
      _cashCtrl.text = close.cash.toStringAsFixed(2);
      for (final entry in _transferEntries) {
        entry.dispose();
      }
      _transferEntries
        ..clear()
        ..addAll(close.transfers.map(_TransferDraft.fromModel));
      _cardCtrl.text = close.card.toStringAsFixed(2);
      _otherIncomeCtrl.text = close.otherIncome.toStringAsFixed(2);
      _expensesCtrl.text = close.expenses.toStringAsFixed(2);
      _expenseEntries.clear();
      if (close.expenseDetails.isNotEmpty) {
        _expenseEntries.addAll(
          close.expenseDetails.map(
            (e) => _ExpenseDraft(
              concept: (e['concept'] as String?) ?? '',
              amount: ((e['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
            ),
          ),
        );
      } else if (close.expenses > 0) {
        _expenseEntries.add(_ExpenseDraft(amount: close.expenses.toStringAsFixed(2)));
      }
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
      for (final entry in _transferEntries) {
        entry.dispose();
      }
      _transferEntries.clear();
      for (final expense in _expenseEntries) {
        expense.dispose();
      }
      _expenseEntries.clear();
      _cardCtrl.text = '0';
      _otherIncomeCtrl.text = '0';
      _expensesCtrl.text = '0';
      _cashDeliveredCtrl.text = '0';
      _notesCtrl.clear();
      _posVoucher = null;
      _uploadingPosVoucher = false;
    });
  }

  String _dateOnly(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  double _toMoney(String? raw) {
    if (raw == null) return 0;
    final normalized = raw.replaceAll(',', '.').trim();
    return double.tryParse(normalized) ?? 0;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _hasActiveCloseFor(
    DateTime date,
    CloseType type,
    CierresDiariosState state, {
    String? excludingId,
  }) {
    return state.closes.any((close) {
      if (excludingId != null && close.id == excludingId) return false;
      if (close.type != type) return false;
      if (close.isRejected) return false;
      return _sameDay(close.date, date);
    });
  }

  void _showDuplicateDateMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Ya existe un cierre activo para esta categoria y fecha. Selecciona otra fecha o categoria.',
        ),
      ),
    );
  }

  void _trySelectType(
    CloseType type,
    CierresDiariosState state,
    CierresDiariosController controller,
  ) {
    if (
        _hasActiveCloseFor(_date, type, state, excludingId: _editingId)) {
      _showDuplicateDateMessage();
      return;
    }
    controller.setTypeFilter(type);
  }

  Future<void> _openHistoryScreen(BuildContext context) async {
    final closeToDuplicate = await Navigator.of(context).push<CloseModel>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _HistoryFullScreenPage(initialType: _type),
      ),
    );
    if (closeToDuplicate != null) {
      _duplicateRejectedClose(closeToDuplicate);
    }
  }
}

class _HistoryFullScreenPage extends ConsumerStatefulWidget {
  final CloseType initialType;

  const _HistoryFullScreenPage({required this.initialType});

  @override
  ConsumerState<_HistoryFullScreenPage> createState() =>
      _HistoryFullScreenPageState();
}

class _HistoryFullScreenPageState
    extends ConsumerState<_HistoryFullScreenPage> {
  late CloseType _selectedType = widget.initialType;
  String _selectedStatus = 'TODOS';
  DateTime? _fromDate;
  DateTime? _toDate;

  String _dateOnly(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  bool _isWithinRange(CloseModel close) {
    if (_fromDate != null) {
      final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      if (close.date.isBefore(from)) return false;
    }
    if (_toDate != null) {
      final to = DateTime(
        _toDate!.year,
        _toDate!.month,
        _toDate!.day,
        23,
        59,
        59,
      );
      if (close.date.isAfter(to)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cierresDiariosControllerProvider);
    final filtered = state.closes.where((close) {
      if (close.type != _selectedType) return false;
      if (_selectedStatus != 'TODOS' && close.status != _selectedStatus) {
        return false;
      }
      return _isWithinRange(close);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de cierres diarios'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () =>
                ref.read(cierresDiariosControllerProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.loading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2100),
                            initialDateRange: DateTimeRange(
                              start: _fromDate ?? DateTime.now(),
                              end: _toDate ?? DateTime.now(),
                            ),
                          );
                          if (range == null) return;
                          setState(() {
                            _fromDate = range.start;
                            _toDate = range.end;
                          });
                        },
                        icon: const Icon(Icons.date_range_outlined),
                        label: Text(
                          _fromDate == null || _toDate == null
                              ? 'Elegir rango'
                              : '${_dateOnly(_fromDate!)} - ${_dateOnly(_toDate!)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_fromDate != null || _toDate != null)
                      TextButton(
                        onPressed: () =>
                            setState(() {
                              _fromDate = null;
                              _toDate = null;
                            }),
                        child: const Text('Limpiar'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Tienda'),
                      selected: _selectedType == CloseType.tienda,
                      onSelected: (_) =>
                          setState(() => _selectedType = CloseType.tienda),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('PhytoEmagry'),
                      selected: _selectedType == CloseType.phytoemagry,
                      onSelected: (_) => setState(
                        () => _selectedType = CloseType.phytoemagry,
                      ),
                    ),
                    const Spacer(),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedStatus,
                        items: const [
                          DropdownMenuItem(
                            value: 'TODOS',
                            child: Text('Estado: Todos'),
                          ),
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('Pendiente'),
                          ),
                          DropdownMenuItem(
                            value: 'approved',
                            child: Text('Aprobado'),
                          ),
                          DropdownMenuItem(
                            value: 'rejected',
                            child: Text('Rechazado'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _selectedStatus = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${filtered.length} registros',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'No hay cierres para el filtro seleccionado.',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final close = filtered[index];
                      final statusLabel = switch (close.status) {
                        'approved' => 'Aprobado',
                        'rejected' => 'Rechazado',
                        _ => 'Pendiente',
                      };
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            final duplicate = await Navigator.of(context).push<
                                CloseModel>(
                              MaterialPageRoute(
                                builder: (_) => _CloseDetailFullScreenPage(
                                  closeId: close.id,
                                ),
                              ),
                            );
                            if (duplicate != null && context.mounted) {
                              Navigator.of(context).pop(duplicate);
                            }
                          },
                          child: Ink(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${close.type.label} · ${DateFormat('dd/MM/yyyy').format(close.date)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Creado por ${close.createdByName ?? close.createdById ?? 'N/D'}',
                                        style:
                                            Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CloseDetailFullScreenPage extends ConsumerStatefulWidget {
  final String closeId;

  const _CloseDetailFullScreenPage({required this.closeId});

  @override
  ConsumerState<_CloseDetailFullScreenPage> createState() =>
      _CloseDetailFullScreenPageState();
}

class _CloseDetailFullScreenPageState
    extends ConsumerState<_CloseDetailFullScreenPage> {
  bool _runningAi = false;
  String _aiStep = '';
  bool _autoAiRequested = false;

  String _money(double value) =>
      NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ').format(value);

  List<String> _asStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final asText = value?.toString().trim() ?? '';
    return asText.isEmpty ? const [] : [asText];
  }

  bool _isImageVoucher(CloseTransferVoucherModel voucher) {
    final mime = voucher.mimeType.toLowerCase();
    final name = voucher.fileName.toLowerCase();
    final url = voucher.fileUrl.toLowerCase();
    final byMime = mime.startsWith('image/');
    final byName =
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp');
    final byUrl =
        url.contains('.jpg') ||
        url.contains('.jpeg') ||
        url.contains('.png') ||
        url.contains('.webp');
    return byMime || byName || byUrl;
  }

  void _ensureAiGeneratedOnOpen(CloseModel close) {
    if (_autoAiRequested) return;
    _autoAiRequested = true;
    final summary = (close.aiReportSummary ?? '').trim();
    final missing = summary.isEmpty || close.aiGeneratedAt == null;
    final stale = close.aiGeneratedAt != null &&
        close.aiGeneratedAt!.isBefore(close.updatedAt);
    if (!missing && !stale) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runAiReport(close);
    });
  }

  Future<void> _openPdf(CloseModel close) async {
    final url = (close.pdfUrl ?? '').trim();
    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este cierre aún no tiene PDF disponible. Verifica si el backend pudo generarlo.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ClosePdfViewerScreen(
          url: url,
          title: (close.pdfFileName ?? '').trim().isNotEmpty
              ? close.pdfFileName!
              : 'PDF de cierre',
        ),
      ),
    );
  }

  Future<void> _runAiReport(CloseModel close) async {
    if (_runningAi) return;
    setState(() {
      _runningAi = true;
      _aiStep = 'Preparando contexto contable...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _aiStep =
          'Analizando diferencia contra gastos, ingresos y comprobantes...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _aiStep = 'Generando reporte IA y guardando resultado...';
    });
    try {
      await ref
          .read(cierresDiariosControllerProvider.notifier)
          .generateAiReport(close.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe IA generado correctamente.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _runningAi = false;
          _aiStep = '';
        });
      }
    }
  }

  Future<void> _askApproveReject({
    required CloseModel close,
    required bool approve,
  }) async {
    final ctrl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Aprobar cierre' : 'Rechazar cierre'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Nota de revisión'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (note == null) return;
    final controller = ref.read(cierresDiariosControllerProvider.notifier);
    if (approve) {
      await controller.approveClose(close.id, reviewNote: note);
    } else {
      await controller.rejectClose(close.id, reviewNote: note);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cierresDiariosControllerProvider);
    CloseModel? close;
    for (final item in state.closes) {
      if (item.id == widget.closeId) {
        close = item;
        break;
      }
    }
    final role = ref.watch(authStateProvider).user?.role;
    final canReview = role == 'ADMIN' || role == 'ASISTENTE';

    if (close == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle de cierre')),
        body: const Center(
          child: Text('No se encontró el cierre seleccionado.'),
        ),
      );
    }
    final currentClose = close;
    _ensureAiGeneratedOnOpen(currentClose);
    final posVoucher = CloseTransferVoucherModel(
      storageKey: currentClose.evidenceStorageKey ?? '',
      fileUrl: currentClose.evidenceUrl ?? '',
      fileName: currentClose.evidenceFileName ?? '',
      mimeType: currentClose.evidenceMimeType ?? '',
    );

    final statusLabel = switch (currentClose.status) {
      'approved' => 'Aprobado',
      'rejected' => 'Rechazado',
      _ => 'Pendiente',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Detalle · ${currentClose.type.label} · ${DateFormat('dd/MM/yyyy').format(currentClose.date)}',
        ),
        actions: [
          if (currentClose.isRejected)
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(currentClose),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Duplicar'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoPill(label: 'Estado', value: statusLabel),
              _InfoPill(
                label: 'Creado por',
                value:
                    currentClose.createdByName ?? currentClose.createdById ?? 'N/D',
              ),
              _InfoPill(
                label: 'Creado en',
                value: DateFormat('dd/MM/yyyy h:mm a', 'es_DO')
                    .format(currentClose.createdAt),
              ),
              if (currentClose.reviewedAt != null)
                _InfoPill(
                  label: 'Revisado en',
                  value: DateFormat('dd/MM/yyyy h:mm a', 'es_DO')
                      .format(currentClose.reviewedAt!),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MoneyPill(label: 'Total ingresos', value: _money(currentClose.incomeTotal)),
              _MoneyPill(label: 'Total neto', value: _money(currentClose.netTotal)),
              _MoneyPill(label: 'Diferencia', value: _money(currentClose.difference)),
              _MoneyPill(label: 'Efectivo', value: _money(currentClose.cash)),
              _MoneyPill(label: 'Transferencia', value: _money(currentClose.transfer)),
              _MoneyPill(label: 'Tarjeta', value: _money(currentClose.card)),
              _MoneyPill(label: 'Otros ingresos', value: _money(currentClose.otherIncome)),
              _MoneyPill(label: 'Gastos', value: _money(currentClose.expenses)),
              _MoneyPill(
                label: 'Efectivo entregado',
                value: _money(currentClose.cashDelivered),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Movimientos del registro',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add_task_outlined),
            title: const Text('Creación del cierre'),
            subtitle: Text(
              '${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(currentClose.createdAt)} · ${currentClose.createdByName ?? currentClose.createdById ?? 'N/D'}',
            ),
          ),
          if (currentClose.aiGeneratedAt != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Informe IA generado'),
              subtitle: Text(
                DateFormat('dd/MM/yyyy h:mm a', 'es_DO')
                    .format(currentClose.aiGeneratedAt!),
              ),
            ),
          if (currentClose.reviewedAt != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.verified_outlined),
              title: Text('Revisión: $statusLabel'),
              subtitle: Text(
                '${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(currentClose.reviewedAt!)} · ${currentClose.reviewedByName ?? currentClose.reviewedById ?? 'N/D'}',
              ),
            ),
          if ((currentClose.notificationStatus ?? '').trim().isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Envío de notificación a administradores'),
              subtitle: Text(
                'Estado: ${currentClose.notificationStatus} ${((currentClose.notificationError ?? '').trim().isNotEmpty) ? '· ${currentClose.notificationError}' : ''}',
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'PDF del cierre enviado a administración',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(
              (currentClose.pdfFileName ?? '').trim().isNotEmpty
                  ? currentClose.pdfFileName!
                  : 'PDF de cierre',
            ),
            subtitle: Text(
              (currentClose.pdfUrl ?? '').trim().isNotEmpty
                  ? currentClose.pdfUrl!
                  : 'Aún no disponible',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: FilledButton.icon(
              onPressed: () => _openPdf(currentClose),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Ver PDF'),
            ),
          ),
          if (currentClose.expenseDetails.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Detalle de gastos',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...currentClose.expenseDetails.map(
              (row) {
                final concept = (row['concept'] as String?)?.trim();
                final amount = (row['amount'] as num?)?.toDouble() ?? 0;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(concept?.isNotEmpty == true ? concept! : 'Sin concepto'),
                  trailing: Text(
                    _money(amount),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Transferencias y vouchers',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (currentClose.transfers.isEmpty)
            const Text('Sin transferencias registradas.')
          else
            ...currentClose.transfers.asMap().entries.map((entry) {
              final transfer = entry.value;
              return ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  '${entry.key + 1}. ${transfer.bankName} · ${_money(transfer.amount)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    if ((transfer.referenceNumber ?? '').trim().isNotEmpty)
                      'Ref: ${transfer.referenceNumber}',
                    if ((transfer.note ?? '').trim().isNotEmpty)
                      transfer.note!.trim(),
                  ].join(' · '),
                ),
                children: [
                  ...transfer.vouchers.map(
                    (voucher) => ListTile(
                      contentPadding: const EdgeInsets.only(left: 4, right: 4),
                      leading: Icon(
                        voucher.mimeType.startsWith('image/')
                            ? Icons.image_outlined
                            : Icons.picture_as_pdf_outlined,
                      ),
                      title: Text(
                        voucher.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(voucher.mimeType),
                      trailing: OutlinedButton(
                        onPressed: () =>
                            _showVoucherPreviewDialog(context, voucher),
                        child: const Text('Expandir'),
                      ),
                    ),
                  ),
                  if (transfer.vouchers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: transfer.vouchers
                            .where(_isImageVoucher)
                            .map(
                              (voucher) => InkWell(
                                onTap: () =>
                                    _showVoucherPreviewDialog(context, voucher),
                                borderRadius: BorderRadius.circular(10),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 84,
                                    height: 84,
                                    child: Image.network(
                                      voucher.fileUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Container(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  if (transfer.vouchers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Sin vouchers en esta transferencia.'),
                      ),
                    ),
                ],
              );
            }),
            if (currentClose.evidenceUrl != null &&
              currentClose.evidenceFileName != null) ...[
            const SizedBox(height: 18),
            Text(
              'Voucher de cierre POS',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                (currentClose.evidenceMimeType ?? '').startsWith('image/')
                    ? Icons.image_outlined
                    : Icons.picture_as_pdf_outlined,
              ),
              title: Text(currentClose.evidenceFileName!),
              subtitle: Text(currentClose.evidenceMimeType ?? 'archivo'),
              trailing: OutlinedButton(
                onPressed: () => _showVoucherPreviewDialog(
                  context,
                  posVoucher,
                ),
                child: const Text('Expandir'),
              ),
            ),
            if (_isImageVoucher(posVoucher))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InkWell(
                  onTap: () => _showVoucherPreviewDialog(context, posVoucher),
                  borderRadius: BorderRadius.circular(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: Image.network(
                        currentClose.evidenceUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
          if ((currentClose.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Notas',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(currentClose.notes!.trim()),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _runningAi ? null : () => _runAiReport(currentClose),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Regenerar reporte IA'),
                ),
              ),
            ],
          ),
          if (_runningAi) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              color: AppTheme.primaryColor,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 8),
            Text(
              _aiStep,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          if ((currentClose.aiReportSummary ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Resultado IA',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _InfoPill(
              label: 'Riesgo',
              value: (currentClose.aiRiskLevel ?? 'N/D').toUpperCase(),
            ),
            const SizedBox(height: 8),
            Text(currentClose.aiReportSummary!.trim()),
            if ((currentClose.aiReportJson ?? const {}).isNotEmpty) ...[
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final report = currentClose.aiReportJson ?? const {};
                  final detectedIssues = _asStringList(
                    report['detectedIssues'] ?? report['detected_issues'],
                  );
                  final suggestedActions = _asStringList(
                    report['suggestedAdminActions'] ??
                        report['suggested_admin_actions'],
                  );
                  final fraudSignals = _asStringList(
                    report['fraudSignals'] ?? report['fraud_signals'],
                  );
                  final auditorNotes = _asStringList(
                    report['auditorNotes'] ?? report['auditor_notes'],
                  );
                  final evidenceReviewed = _asStringList(
                    report['evidenceReviewed'] ?? report['evidence_reviewed'],
                  );
                  final financialBreakdown =
                      report['financialBreakdown'] as Map<String, dynamic>?;

                  Widget sectionTitle(String title) => Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 6),
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      );

                  Widget bulletList(List<String> rows, {String empty = 'N/D'}) {
                    if (rows.isEmpty) return Text(empty);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: rows
                          .map(
                            (row) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('• $row'),
                            ),
                          )
                          .toList(),
                    );
                  }

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        sectionTitle('Evaluación financiera'),
                        if (financialBreakdown != null) ...[
                          Text(
                            'Diferencia: ${financialBreakdown['difference'] ?? currentClose.difference} · Gastos: ${financialBreakdown['expenses'] ?? currentClose.expenses}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Análisis: ${financialBreakdown['reasoning'] ?? 'Sin razonamiento explícito.'}',
                          ),
                        ] else
                          Text(
                            'Diferencia actual: ${currentClose.difference} · Gastos declarados: ${currentClose.expenses}',
                          ),
                        sectionTitle('Problemas detectados'),
                        bulletList(detectedIssues, empty: 'Sin alertas críticas.'),
                        sectionTitle('Posibles señales de fraude'),
                        bulletList(fraudSignals, empty: 'No se detectaron señales claras.'),
                        sectionTitle('Acciones sugeridas'),
                        bulletList(suggestedActions, empty: 'Sin acciones sugeridas.'),
                        sectionTitle('Notas del auditor IA'),
                        bulletList(auditorNotes, empty: 'Sin notas adicionales.'),
                        sectionTitle('Evidencias revisadas'),
                        bulletList(evidenceReviewed, empty: 'No se registraron evidencias en el análisis.'),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Ver JSON técnico completo'),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(currentClose.aiReportJson),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (currentClose.isPending && canReview) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _askApproveReject(close: currentClose, approve: false),
                    icon: const Icon(Icons.close),
                    label: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        _askApproveReject(close: currentClose, approve: true),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Aprobar'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ClosePdfViewerScreen extends StatelessWidget {
  final String url;
  final String title;

  const _ClosePdfViewerScreen({required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SfPdfViewer.network(url),
    );
  }
}

void _showVoucherPreviewDialog(
  BuildContext context,
  CloseTransferVoucherModel voucher,
) {
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 700),
        child: Column(
          children: [
            ListTile(
              title: Text(voucher.fileName),
              subtitle: Text(voucher.mimeType),
              trailing: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: voucher.mimeType.startsWith('image/')
                  ? InteractiveViewer(child: Image.network(voucher.fileUrl))
                  : Padding(
                      padding: const EdgeInsets.all(18),
                      child: SelectableText(voucher.fileUrl),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
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

class _UnitChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  const _UnitChipButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        backgroundColor: selected ? AppTheme.primaryColor : Colors.white,
        foregroundColor: selected ? Colors.white : AppTheme.primaryColor,
        disabledForegroundColor: selected
            ? Colors.white
            : AppTheme.primaryColor.withValues(alpha: 0.55),
        side: BorderSide(
          color: selected
              ? AppTheme.primaryColor
              : AppTheme.primaryColor.withValues(alpha: 0.45),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      ),
      child: Text(label, textAlign: TextAlign.center, maxLines: 1),
    );
  }
}

class _TransferDraft {
  final bankCtrl = TextEditingController();
  final amountCtrl = TextEditingController(text: '0');
  final referenceCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final List<CloseTransferVoucherModel> vouchers = [];
  bool uploading = false;

  _TransferDraft();

  factory _TransferDraft.fromModel(CloseTransferModel model) {
    final draft = _TransferDraft();
    draft.bankCtrl.text = model.bankName;
    draft.amountCtrl.text = model.amount.toStringAsFixed(2);
    draft.referenceCtrl.text = model.referenceNumber ?? '';
    draft.noteCtrl.text = model.note ?? '';
    draft.vouchers.addAll(model.vouchers);
    return draft;
  }

  void dispose() {
    bankCtrl.dispose();
    amountCtrl.dispose();
    referenceCtrl.dispose();
    noteCtrl.dispose();
  }
}

class _ExpenseDraft {
  final conceptCtrl = TextEditingController();
  final amountCtrl = TextEditingController(text: '0');

  _ExpenseDraft({String concept = '', String amount = '0'}) {
    conceptCtrl.text = concept;
    amountCtrl.text = amount;
  }

  void dispose() {
    conceptCtrl.dispose();
    amountCtrl.dispose();
  }
}

class _TransferEntryEditor extends StatelessWidget {
  final int index;
  final _TransferDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final Future<void> Function() onPickVoucher;
  final void Function(CloseTransferVoucherModel voucher) onOpenVoucher;

  const _TransferEntryEditor({
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
    required this.onPickVoucher,
    required this.onOpenVoucher,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Transferencia ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Eliminar transferencia',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _resolveDepositBank(draft.bankCtrl.text)?.id,
                    items: depositBankCatalog
                        .map(
                          (bank) => DropdownMenuItem(
                            value: bank.id,
                            child: Text(bank.label),
                          ),
                        )
                        .toList(),
                    decoration: const InputDecoration(labelText: 'Banco'),
                    onChanged: (value) {
                      if (value == null) return;
                      final bank = depositBankCatalog.firstWhere(
                        (item) => item.id == value,
                        orElse: () => depositBankCatalog.first,
                      );
                      draft.bankCtrl.text = bank.label;
                      onChanged();
                    },
                    validator: (value) =>
                        value == null ? 'Banco requerido' : null,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    controller: draft.amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Monto'),
                    onChanged: (_) => onChanged(),
                    validator: (value) {
                      final amount =
                          double.tryParse((value ?? '').replaceAll(',', '.')) ??
                          0;
                      return amount <= 0 ? 'Mayor a 0' : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: draft.referenceCtrl,
                    decoration: const InputDecoration(labelText: 'Referencia'),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: draft.noteCtrl,
                    decoration: const InputDecoration(labelText: 'Nota'),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: draft.uploading ? null : onPickVoucher,
                  icon: draft.uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  label: const Text('Voucher'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: draft.vouchers
                        .map(
                          (voucher) => InputChip(
                            label: Text(voucher.fileName),
                            avatar: Icon(
                              voucher.mimeType.startsWith('image/')
                                  ? Icons.image_outlined
                                  : Icons.picture_as_pdf_outlined,
                              size: 18,
                            ),
                            onPressed: () => onOpenVoucher(voucher),
                            onDeleted: () {
                              draft.vouchers.remove(voucher);
                              onChanged();
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
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
