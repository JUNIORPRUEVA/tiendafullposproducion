import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/close_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'application/cierres_diarios_controller.dart';
import 'data/contabilidad_repository.dart';
import 'widgets/app_card.dart';
import 'widgets/section_title.dart';

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

  @override
  void dispose() {
    _cashCtrl.dispose();
    for (final entry in _transferEntries) {
      entry.dispose();
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
                  _buildCategoryButtons(selectedType, controller),
                  const SizedBox(height: 12),
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
    final transfer = _transferEntries.fold<double>(
      0,
      (sum, entry) => sum + _toMoney(entry.amountCtrl.text),
    );
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
            _buildTransferSection(money),
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

                        await controller.saveClose(
                          type: _type,
                          date: _date,
                          cash: _toMoney(_cashCtrl.text),
                          transfer: transfer,
                          transfers: _transferPayload(),
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

  Future<void> _pickVoucher(_TransferDraft draft) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
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
      for (final entry in _transferEntries) {
        entry.dispose();
      }
      _transferEntries
        ..clear()
        ..addAll(close.transfers.map(_TransferDraft.fromModel));
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
      for (final entry in _transferEntries) {
        entry.dispose();
      }
      _transferEntries.clear();
      _cardCtrl.text = '0';
      _otherIncomeCtrl.text = '0';
      _expensesCtrl.text = '0';
      _cashDeliveredCtrl.text = '0';
      _notesCtrl.clear();
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

  Future<void> _openHistoryDialog(
    BuildContext context,
    List<CloseModel> closes,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        CloseType selectedType = _type;
        String selectedStatus = 'TODOS';
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
              if (selectedStatus != 'TODOS' && close.status != selectedStatus) {
                return false;
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
                              value: selectedStatus,
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
                                setDialogState(() => selectedStatus = value);
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
                  child: TextFormField(
                    controller: draft.bankCtrl,
                    decoration: const InputDecoration(labelText: 'Banco'),
                    onChanged: (_) => onChanged(),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Banco requerido' : null,
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
          if (canReview) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await ref
                      .read(cierresDiariosControllerProvider.notifier)
                      .generateAiReport(close.id);
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Informe IA'),
              ),
            ),
          ],
          if ((close.aiReportSummary ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'IA ${close.aiRiskLevel ?? 'N/D'}: ${close.aiReportSummary}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
          if (close.isPending && canReview) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final note = await _askReviewNote(
                      context,
                      'Rechazar cierre',
                    );
                    if (note == null) return;
                    await ref
                        .read(cierresDiariosControllerProvider.notifier)
                        .rejectClose(close.id, reviewNote: note);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Rechazar'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () async {
                    final note = await _askReviewNote(
                      context,
                      'Aprobar cierre',
                    );
                    if (note == null) return;
                    await ref
                        .read(cierresDiariosControllerProvider.notifier)
                        .approveClose(close.id, reviewNote: note);
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

  Future<String?> _askReviewNote(BuildContext context, String title) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Nota de revision'),
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
