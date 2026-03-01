import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'cotizacion_models.dart';
import 'data/cotizaciones_repository.dart';

class CotizacionesHistorialScreen extends ConsumerStatefulWidget {
  final String? customerPhone;
  final bool pickForEditor;

  const CotizacionesHistorialScreen({
    super.key,
    this.customerPhone,
    this.pickForEditor = true,
  });

  @override
  ConsumerState<CotizacionesHistorialScreen> createState() =>
      _CotizacionesHistorialScreenState();
}

class _CotizacionesHistorialScreenState
    extends ConsumerState<CotizacionesHistorialScreen> {
  bool _loading = true;
  String? _error;
  List<CotizacionModel> _items = const [];

  String _money(double value) =>
      NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(cotizacionesRepositoryProvider).list(
            customerPhone: widget.customerPhone,
          );
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _delete(CotizacionModel item) async {
    if (!widget.pickForEditor) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cotización'),
        content: Text('¿Eliminar la cotización de ${item.customerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(cotizacionesRepositoryProvider).deleteById(item.id);
    await _load();
  }

  void _viewDetail(CotizacionModel item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalle de cotización'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cliente: ${item.customerName}'),
                if ((item.customerPhone ?? '').trim().isNotEmpty)
                  Text('Teléfono: ${item.customerPhone}'),
                Text(
                  'Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(item.createdAt)}',
                ),
                if (item.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Nota: ${item.note}'),
                ],
                const Divider(height: 18),
                ...item.items.map(
                  (line) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${line.nombre} x${line.qty.toStringAsFixed(line.qty % 1 == 0 ? 0 : 2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(_money(line.total)),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 18),
                Row(
                  children: [
                    const Expanded(child: Text('Subtotal')),
                    Text(_money(item.subtotal)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ITBIS ${item.includeItbis ? '(18%)' : '(no aplicado)'}',
                      ),
                    ),
                    Text(_money(item.itbisAmount)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      _money(item.total),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = (widget.customerPhone ?? '').trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          phone.isEmpty
              ? 'Historial cotizaciones'
              : 'Cotizaciones · $phone',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            )
          : _items.isEmpty
          ? Center(
              child: Text(
                phone.isEmpty
                    ? 'No hay cotizaciones guardadas'
                    : 'Este cliente no tiene cotizaciones',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.customerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              DateFormat('dd/MM HH:mm').format(item.createdAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Líneas: ${item.items.length} · Total: ${_money(item.total)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _viewDetail(item),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Ver'),
                            ),
                            if (widget.pickForEditor) ...[
                              OutlinedButton.icon(
                                onPressed: () => Navigator.pop(
                                  context,
                                  CotizacionEditorPayload(
                                    source: item,
                                    duplicate: false,
                                  ),
                                ),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Editar'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => Navigator.pop(
                                  context,
                                  CotizacionEditorPayload(
                                    source: item,
                                    duplicate: true,
                                  ),
                                ),
                                icon: const Icon(Icons.copy_all_outlined),
                                label: const Text('Duplicar'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _delete(item),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Eliminar'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
