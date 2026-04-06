import 'dart:typed_data';

import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/safe_url_launcher.dart';
import '../../core/errors/api_exception.dart';
import 'data/document_flows_repository.dart';
import 'document_flow_models.dart';

class DocumentFlowDetailScreen extends ConsumerStatefulWidget {
  const DocumentFlowDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<DocumentFlowDetailScreen> createState() =>
      _DocumentFlowDetailScreenState();
}

class _DocumentFlowDetailScreenState
    extends ConsumerState<DocumentFlowDetailScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _lastSendPreview;
  OrderDocumentFlowModel? _flow;
  final _currencyController = TextEditingController();
  final _taxController = TextEditingController();
  final _notesController = TextEditingController();
  final _warrantyTitleController = TextEditingController();
  final _warrantySummaryController = TextEditingController();
  final _warrantyTermsController = TextEditingController();
  List<_InvoiceItemEditor> _itemEditors = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _currencyController.dispose();
    _taxController.dispose();
    _notesController.dispose();
    _warrantyTitleController.dispose();
    _warrantySummaryController.dispose();
    _warrantyTermsController.dispose();
    _disposeEditors();
    super.dispose();
  }

  void _disposeEditors() {
    for (final editor in _itemEditors) {
      editor.dispose();
    }
  }

  void _applyFlow(OrderDocumentFlowModel flow) {
    _disposeEditors();
    _flow = flow;
    _currencyController.text = flow.invoiceDraft.currency;
    _taxController.text = flow.invoiceDraft.tax.toStringAsFixed(2);
    _notesController.text = flow.invoiceDraft.notes;
    _warrantyTitleController.text = flow.warrantyDraft.title;
    _warrantySummaryController.text = flow.warrantyDraft.summary;
    _warrantyTermsController.text = flow.warrantyDraft.terms.join('\n');
    _itemEditors = flow.invoiceDraft.items
        .map((item) => _InvoiceItemEditor.fromItem(item))
        .toList(growable: true);
    if (_itemEditors.isEmpty) {
      _itemEditors = <_InvoiceItemEditor>[_InvoiceItemEditor.empty()];
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final flow = await ref
          .read(documentFlowsRepositoryProvider)
          .getByOrderId(widget.orderId);
      if (!mounted) return;
      setState(() {
        _applyFlow(flow);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el detalle documental';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveDraft() async {
    final flow = _flow;
    if (flow == null) return;
    setState(() {
      _saving = true;
    });
    try {
      final invoiceItems = _itemEditors
          .map((editor) => editor.toItem())
          .where((item) => item.description.trim().isNotEmpty)
          .toList(growable: false);
      final subtotal = invoiceItems.fold<double>(
        0,
        (sum, item) => sum + item.lineTotal,
      );
      final tax = double.tryParse(_taxController.text.trim()) ?? 0;
      final updated = await ref
          .read(documentFlowsRepositoryProvider)
          .editDraft(
            id: flow.id,
            invoiceDraftJson: {
              'currency': _currencyController.text.trim().isEmpty
                  ? flow.invoiceDraft.currency
                  : _currencyController.text.trim(),
              'clientName': flow.order.client.nombre,
              'clientPhone': flow.order.client.telefono,
              'items': invoiceItems
                  .map((item) => item.toJson())
                  .toList(growable: false),
              'subtotal': subtotal,
              'tax': tax,
              'total': subtotal + tax,
              'notes': _notesController.text.trim(),
            },
            warrantyDraftJson: {
              'title': _warrantyTitleController.text.trim(),
              'summary': _warrantySummaryController.text.trim(),
              'serviceType': flow.order.serviceType,
              'category': flow.order.category,
              'clientName': flow.order.client.nombre,
              'terms': _warrantyTermsController.text
                  .split('\n')
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toList(growable: false),
            },
          );
      if (!mounted) return;
      setState(() {
        _applyFlow(updated);
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Borrador documental guardado')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _generateDocuments() async {
    final flow = _flow;
    if (flow == null) return;
    setState(() {
      _saving = true;
    });
    try {
      final updated = await ref
          .read(documentFlowsRepositoryProvider)
          .generate(flow.id);
      if (!mounted) return;
      setState(() {
        _applyFlow(updated);
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Documentos finales generados')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _generateAndSend() async {
    final flow = _flow;
    if (flow == null) return;
    setState(() {
      _saving = true;
    });
    try {
      final result = await ref
          .read(documentFlowsRepositoryProvider)
          .send(flow.id);
      if (!mounted) return;
      setState(() {
        _applyFlow(result.flow);
        _lastSendPreview = result.messageText;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Payload listo para WhatsApp: ${result.toNumber}'),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _openPdfPreview(String title, String rawUrl) async {
    setState(() {
      _saving = true;
    });

    try {
      final bytes = await ref
          .read(documentFlowsRepositoryProvider)
          .downloadPdfBytes(rawUrl);
      if (!mounted) return;
      await _showPdfDialog(title, bytes);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _showPdfDialog(String title, Uint8List bytes) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final media = MediaQuery.sizeOf(dialogContext);
        final isCompact = media.width < 520;
        return Dialog(
          insetPadding: EdgeInsets.all(isCompact ? 8 : 16),
          child: SizedBox(
            width: isCompact ? media.width - 16 : 920,
            height: isCompact ? media.height * 0.92 : 760,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(isCompact ? 10 : 14, 10, 8, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: isCompact ? 14 : 16,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PdfPreview(
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    allowPrinting: true,
                    allowSharing: true,
                    build: (_) async => bytes,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPdfExternally(String rawUrl) async {
    final resolvedUrl = ref
        .read(documentFlowsRepositoryProvider)
        .resolveDocumentUrl(rawUrl);
    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('No se pudo resolver la URL del PDF')),
      );
      return;
    }
    await safeOpenUrl(
      context,
      uri,
      copiedMessage: 'No se pudo abrir el PDF. Link copiado',
    );
  }

  @override
  Widget build(BuildContext context) {
    final flow = _flow;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle documental'),
        actions: [
          IconButton(
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : flow == null
          ? const Center(child: Text('No hay datos del flujo documental'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryCard(flow: flow),
                  const SizedBox(height: 16),
                  _buildInvoiceCard(flow),
                  const SizedBox(height: 16),
                  _buildWarrantyCard(flow),
                  const SizedBox(height: 16),
                  _buildGeneratedFilesCard(flow),
                  if (_lastSendPreview != null &&
                      _lastSendPreview!.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Payload WhatsApp',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            SelectableText(_lastSendPreview!),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _saving ? null : _saveDraft,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Guardar borrador'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _generateDocuments,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Generar documentos'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _generateAndSend,
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Generar y preparar envío'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInvoiceCard(OrderDocumentFlowModel flow) {
    final subtotal = _itemEditors
        .map((editor) => editor.toItem())
        .where((item) => item.description.trim().isNotEmpty)
        .fold<double>(0, (sum, item) => sum + item.lineTotal);
    final tax =
        double.tryParse(_taxController.text.trim()) ?? flow.invoiceDraft.tax;
    final total = subtotal + tax;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Factura', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _currencyController,
              decoration: const InputDecoration(labelText: 'Moneda'),
            ),
            const SizedBox(height: 12),
            ..._itemEditors.asMap().entries.map((entry) {
              final index = entry.key;
              final editor = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: editor.descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Descripción',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: editor.qtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Cant.'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: editor.unitPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Precio'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _itemEditors.length == 1
                          ? null
                          : () {
                              setState(() {
                                final removed = _itemEditors.removeAt(index);
                                removed.dispose();
                              });
                            },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _itemEditors = List<_InvoiceItemEditor>.from(_itemEditors)
                      ..add(_InvoiceItemEditor.empty());
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('Agregar línea'),
              ),
            ),
            TextField(
              controller: _taxController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Impuesto'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                Text('Subtotal: ${subtotal.toStringAsFixed(2)}'),
                Text('Total: ${total.toStringAsFixed(2)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarrantyCard(OrderDocumentFlowModel flow) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Garantía', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _warrantyTitleController,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _warrantySummaryController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Resumen de cobertura',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _warrantyTermsController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Términos',
                helperText: 'Un término por línea',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                Text('Servicio: ${flow.order.serviceType}'),
                Text('Categoría: ${flow.order.category}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratedFilesCard(OrderDocumentFlowModel flow) {
    final invoiceUrl = flow.invoiceFinalUrl?.trim() ?? '';
    final warrantyUrl = flow.warrantyFinalUrl?.trim() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Archivos finales',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _buildGeneratedFileRow(
              label: 'Factura',
              rawUrl: invoiceUrl,
              previewTitle: 'Factura final',
            ),
            const SizedBox(height: 12),
            _buildGeneratedFileRow(
              label: 'Garantía',
              rawUrl: warrantyUrl,
              previewTitle: 'Carta de garantía',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratedFileRow({
    required String label,
    required String rawUrl,
    required String previewTitle,
  }) {
    final hasUrl = rawUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (!hasUrl)
          const Text('Pendiente')
        else ...[
          SelectableText(rawUrl),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _saving
                    ? null
                    : () => _openPdfPreview(previewTitle, rawUrl),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Ver PDF'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _openPdfExternally(rawUrl),
                icon: const Icon(Icons.open_in_new_outlined),
                label: const Text('Abrir fuera'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.flow});

  final OrderDocumentFlowModel flow;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              flow.order.client.nombre,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text('Orden: ${flow.order.id}'),
                Text('Estado flujo: ${flow.status.label}'),
                Text('Estado orden: ${flow.order.status}'),
                Text('Teléfono: ${flow.order.client.telefono}'),
              ],
            ),
            if ((flow.order.client.direccion ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Dirección: ${flow.order.client.direccion}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _InvoiceItemEditor {
  _InvoiceItemEditor({
    required this.descriptionController,
    required this.qtyController,
    required this.unitPriceController,
  });

  factory _InvoiceItemEditor.fromItem(DocumentFlowInvoiceItem item) {
    return _InvoiceItemEditor(
      descriptionController: TextEditingController(text: item.description),
      qtyController: TextEditingController(text: item.qty.toStringAsFixed(2)),
      unitPriceController: TextEditingController(
        text: item.unitPrice.toStringAsFixed(2),
      ),
    );
  }

  factory _InvoiceItemEditor.empty() {
    return _InvoiceItemEditor(
      descriptionController: TextEditingController(),
      qtyController: TextEditingController(text: '1'),
      unitPriceController: TextEditingController(text: '0'),
    );
  }

  final TextEditingController descriptionController;
  final TextEditingController qtyController;
  final TextEditingController unitPriceController;

  DocumentFlowInvoiceItem toItem() {
    final qty = double.tryParse(qtyController.text.trim()) ?? 0;
    final unitPrice = double.tryParse(unitPriceController.text.trim()) ?? 0;
    return DocumentFlowInvoiceItem(
      description: descriptionController.text.trim(),
      qty: qty,
      unitPrice: unitPrice,
      lineTotal: qty * unitPrice,
    );
  }

  void dispose() {
    descriptionController.dispose();
    qtyController.dispose();
    unitPriceController.dispose();
  }
}
