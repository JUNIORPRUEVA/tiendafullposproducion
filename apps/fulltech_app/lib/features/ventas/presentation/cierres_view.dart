import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/close_model.dart';
import '../application/contabilidad_controller.dart';
import '../../contabilidad/widgets/app_card.dart';

class CierresView extends ConsumerStatefulWidget {
  const CierresView({super.key});

  @override
  ConsumerState<CierresView> createState() => _CierresViewState();
}

class _CierresViewState extends ConsumerState<CierresView> {
  DateTimeRange? _selectedRange;

  String _formatDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(contabilidadProvider);
    final ctrl = ref.read(contabilidadProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cierres'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateDialog(context, ctrl),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ctrl.load(from: state.from, to: state.to),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _selectedRange != null
                                ? '${_formatDate(_selectedRange!.start)} - ${_formatDate(_selectedRange!.end)}'
                                : 'Seleccionar rango',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: () => _pickRange(context, ctrl),
                          child: const Text('Cambiar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SummaryBar(summary: state.summary),
            const SizedBox(height: 16),
            if (state.loading)
              const Center(child: CircularProgressIndicator())
            else if (state.error != null)
              Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
            else
              ...state.closes.map((close) => _CloseCard(close: close, onUpdate: (c) => _showUpdateDialog(context, ctrl, c), onDelete: () => _deleteClose(ctrl, close.id))),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRange(BuildContext context, ContabilidadController ctrl) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _selectedRange,
    );
    if (picked != null) {
      setState(() => _selectedRange = picked);
      await ctrl.load(from: picked.start, to: picked.end);
    }
  }

  Future<void> _showCreateDialog(BuildContext context, ContabilidadController ctrl) async {
    // Implementar diálogo de creación
    // Por simplicidad, usar un diálogo básico
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _CreateCloseDialog(),
    );
    if (result != null) {
      await ctrl.createClose(
        type: result['type'] as CloseType,
        status: result['status'] as String,
        cash: result['cash'] as double,
        transfer: result['transfer'] as double,
        card: result['card'] as double,
        expenses: result['expenses'] as double,
        cashDelivered: result['cashDelivered'] as double,
        date: result['date'] as DateTime?,
      );
    }
  }

  Future<void> _showUpdateDialog(BuildContext context, ContabilidadController ctrl, CloseModel close) async {
    // Implementar diálogo de actualización similar al de creación
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _UpdateCloseDialog(close: close),
    );
    if (result != null) {
      await ctrl.updateClose(close.id,
        status: result['status'],
        cash: result['cash'],
        transfer: result['transfer'],
        card: result['card'],
        expenses: result['expenses'],
        cashDelivered: result['cashDelivered'],
      );
    }
  }

  Future<void> _deleteClose(ContabilidadController ctrl, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cierre'),
        content: const Text('¿Estás seguro de eliminar este cierre?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm == true) {
      await ctrl.deleteClose(id);
    }
  }
}

class _SummaryBar extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _SummaryBar({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _KpiTile(label: 'Cierres', value: '${summary['count']}'),
        _KpiTile(label: 'Efectivo', value: summary['totalCash']),
        _KpiTile(label: 'Transfer', value: summary['totalTransfer']),
        _KpiTile(label: 'Tarjeta', value: summary['totalCard']),
        _KpiTile(label: 'Ingresos', value: summary['totalIncome']),
        _KpiTile(label: 'Gastos', value: summary['totalExpenses']),
        _KpiTile(label: 'Entregado', value: summary['totalDelivered']),
        _KpiTile(label: 'En caja', value: summary['cashOnHand']),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  const _KpiTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseCard extends StatelessWidget {
  final CloseModel close;
  final void Function(CloseModel) onUpdate;
  final VoidCallback onDelete;

  const _CloseCard({required this.close, required this.onUpdate, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text('${close.type.label} - ${DateFormat('dd/MM/yyyy').format(close.date)}'),
        subtitle: Text('Efectivo: ${close.cash.toStringAsFixed(2)} · Gastos: ${close.expenses.toStringAsFixed(2)} · Diferencia: ${close.difference.toStringAsFixed(2)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(close.status),
            IconButton(icon: const Icon(Icons.edit), onPressed: () => onUpdate(close)),
            IconButton(icon: const Icon(Icons.delete), onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

class _UpdateCloseDialog extends StatefulWidget {
  final CloseModel close;
  const _UpdateCloseDialog({required this.close});

  @override
  State<_UpdateCloseDialog> createState() => _UpdateCloseDialogState();
}

class _UpdateCloseDialogState extends State<_UpdateCloseDialog> {
  final _formKey = GlobalKey<FormState>();
  late CloseType _type;
  late String _status;
  late final TextEditingController _cashCtrl;
  late final TextEditingController _transferCtrl;
  late final TextEditingController _cardCtrl;
  late final TextEditingController _expensesCtrl;
  late final TextEditingController _deliveredCtrl;

  @override
  void initState() {
    super.initState();
    _type = widget.close.type;
    _status = widget.close.status;
    _cashCtrl = TextEditingController(text: widget.close.cash.toString());
    _transferCtrl = TextEditingController(text: widget.close.transfer.toString());
    _cardCtrl = TextEditingController(text: widget.close.card.toString());
    _expensesCtrl = TextEditingController(text: widget.close.expenses.toString());
    _deliveredCtrl = TextEditingController(text: widget.close.cashDelivered.toString());
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _transferCtrl.dispose();
    _cardCtrl.dispose();
    _expensesCtrl.dispose();
    _deliveredCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Actualizar cierre'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<CloseType>(
                initialValue: _type,
                items: CloseType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
                onChanged: (v) => setState(() => _type = v!),
                decoration: const InputDecoration(labelText: 'Tipo'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _status,
                items: const [
                  DropdownMenuItem(value: 'draft', child: Text('Borrador')),
                  DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
                  DropdownMenuItem(value: 'closed', child: Text('Cerrado')),
                ],
                onChanged: (v) => setState(() => _status = v!),
                decoration: const InputDecoration(labelText: 'Estado'),
              ),
              TextFormField(controller: _cashCtrl, decoration: const InputDecoration(labelText: 'Efectivo'), keyboardType: TextInputType.number),
              TextFormField(controller: _transferCtrl, decoration: const InputDecoration(labelText: 'Transferencias'), keyboardType: TextInputType.number),
              TextFormField(controller: _cardCtrl, decoration: const InputDecoration(labelText: 'Tarjetas'), keyboardType: TextInputType.number),
              TextFormField(controller: _expensesCtrl, decoration: const InputDecoration(labelText: 'Gastos'), keyboardType: TextInputType.number),
              TextFormField(controller: _deliveredCtrl, decoration: const InputDecoration(labelText: 'Efectivo entregado'), keyboardType: TextInputType.number),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final result = {
                'status': _status,
                'cash': double.tryParse(_cashCtrl.text) ?? 0,
                'transfer': double.tryParse(_transferCtrl.text) ?? 0,
                'card': double.tryParse(_cardCtrl.text) ?? 0,
                'expenses': double.tryParse(_expensesCtrl.text) ?? 0,
                'cashDelivered': double.tryParse(_deliveredCtrl.text) ?? 0,
              };
              Navigator.pop(context, result);
            }
          },
          child: const Text('Actualizar'),
        ),
      ],
    );
  }
}

class _CreateCloseDialog extends StatefulWidget {
  const _CreateCloseDialog();

  @override
  State<_CreateCloseDialog> createState() => _CreateCloseDialogState();
}

class _CreateCloseDialogState extends State<_CreateCloseDialog> {
  final _formKey = GlobalKey<FormState>();
  CloseType _type = CloseType.capsulas;
  String _status = 'draft';
  final _cashCtrl = TextEditingController();
  final _transferCtrl = TextEditingController();
  final _cardCtrl = TextEditingController();
  final _expensesCtrl = TextEditingController();
  final _deliveredCtrl = TextEditingController();
  DateTime? _date;

  @override
  void dispose() {
    _cashCtrl.dispose();
    _transferCtrl.dispose();
    _cardCtrl.dispose();
    _expensesCtrl.dispose();
    _deliveredCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo cierre'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<CloseType>(
                initialValue: _type,
                items: CloseType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
                onChanged: (v) => setState(() => _type = v!),
                decoration: const InputDecoration(labelText: 'Tipo'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _status,
                items: const [
                  DropdownMenuItem(value: 'draft', child: Text('Borrador')),
                  DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
                  DropdownMenuItem(value: 'closed', child: Text('Cerrado')),
                ],
                onChanged: (v) => setState(() => _status = v!),
                decoration: const InputDecoration(labelText: 'Estado'),
              ),
              TextFormField(controller: _cashCtrl, decoration: const InputDecoration(labelText: 'Efectivo'), keyboardType: TextInputType.number),
              TextFormField(controller: _transferCtrl, decoration: const InputDecoration(labelText: 'Transferencias'), keyboardType: TextInputType.number),
              TextFormField(controller: _cardCtrl, decoration: const InputDecoration(labelText: 'Tarjetas'), keyboardType: TextInputType.number),
              TextFormField(controller: _expensesCtrl, decoration: const InputDecoration(labelText: 'Gastos'), keyboardType: TextInputType.number),
              TextFormField(controller: _deliveredCtrl, decoration: const InputDecoration(labelText: 'Efectivo entregado'), keyboardType: TextInputType.number),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final result = {
                'type': _type,
                'status': _status,
                'cash': double.tryParse(_cashCtrl.text) ?? 0,
                'transfer': double.tryParse(_transferCtrl.text) ?? 0,
                'card': double.tryParse(_cardCtrl.text) ?? 0,
                'expenses': double.tryParse(_expensesCtrl.text) ?? 0,
                'cashDelivered': double.tryParse(_deliveredCtrl.text) ?? 0,
                'date': _date,
              };
              Navigator.pop(context, result);
            }
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}