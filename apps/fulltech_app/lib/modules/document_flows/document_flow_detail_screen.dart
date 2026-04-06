import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/utils/pdf_file_actions.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../clientes/cliente_model.dart';
import '../cotizaciones/cotizacion_models.dart';
import '../cotizaciones/cotizaciones_screen.dart';
import '../cotizaciones/data/cotizaciones_repository.dart';
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
  final _warrantyServiceTypeController = TextEditingController();
  final _serviceWarrantyDurationController = TextEditingController();
  final _productWarrantyDurationController = TextEditingController();
  final _coverageController = TextEditingController();
  final _conditionsController = TextEditingController();
  final _exclusionsController = TextEditingController();
  List<_InvoiceItemEditor> _itemEditors = const [];
  String _warrantyTitle = 'CARTA DE GARANTIA';

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
    _warrantyServiceTypeController.dispose();
    _serviceWarrantyDurationController.dispose();
    _productWarrantyDurationController.dispose();
    _coverageController.dispose();
    _conditionsController.dispose();
    _exclusionsController.dispose();
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
    final warrantyForm = _WarrantyFormData.fromFlow(flow);
    _warrantyTitle = warrantyForm.title;
    _warrantyServiceTypeController.text = warrantyForm.serviceType;
    _serviceWarrantyDurationController.text =
        warrantyForm.serviceWarrantyDuration;
    _productWarrantyDurationController.text =
        warrantyForm.productWarrantyDuration;
    _coverageController.text = warrantyForm.coverage;
    _conditionsController.text = warrantyForm.conditions;
    _exclusionsController.text = warrantyForm.exclusions;
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
      final warrantyForm = _WarrantyFormData(
        title: _warrantyTitle.trim().isEmpty
            ? 'CARTA DE GARANTIA'
            : _warrantyTitle.trim(),
        serviceType: _warrantyServiceTypeController.text.trim(),
        serviceWarrantyDuration: _serviceWarrantyDurationController.text.trim(),
        productWarrantyDuration: _productWarrantyDurationController.text.trim(),
        coverage: _coverageController.text.trim(),
        conditions: _conditionsController.text.trim(),
        exclusions: _exclusionsController.text.trim(),
      );
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
              'title': warrantyForm.title,
              'summary': warrantyForm.coverage,
              'serviceType': warrantyForm.serviceType.isEmpty
                  ? flow.warrantyDraft.serviceType
                  : warrantyForm.serviceType,
              'category': flow.order.category,
              'clientName': flow.order.client.nombre,
              'terms': warrantyForm.toTerms(),
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

  Future<void> _downloadPdf(String title, String rawUrl) async {
    setState(() {
      _saving = true;
    });

    try {
      final bytes = await ref
          .read(documentFlowsRepositoryProvider)
          .downloadPdfBytes(rawUrl);
      if (!mounted) return;
      final orderId = _flow?.order.id.substring(0, 8) ?? 'documento';
      final saved = await savePdfBytes(
        bytes: bytes,
        fileName: '${_slugify(title)}_$orderId.pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(saved ? 'PDF descargado' : 'Descarga cancelada'),
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

  Future<void> _editLinkedQuotation() async {
    final flow = _flow;
    if (flow == null) return;
    final quotationId = (flow.order.quotationId ?? '').trim();
    if (quotationId.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Esta orden no tiene una cotización vinculada'),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final repository = ref.read(cotizacionesRepositoryProvider);
      final quotation = await repository.getByIdAndCache(quotationId);
      if (!mounted) return;
      final client = ClienteModel(
        id: flow.order.client.id,
        ownerId: '',
        nombre: flow.order.client.nombre,
        telefono: flow.order.client.telefono,
        direccion: flow.order.client.direccion,
      );
      final updatedQuotation = await Navigator.of(context)
          .push<CotizacionModel>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => CotizacionesScreen(
                initialClient: client,
                initialQuotation: quotation,
                returnSavedQuotation: true,
              ),
            ),
          );
      if (!mounted || updatedQuotation == null) return;
      setState(() {
        _applyQuotationToInvoice(updatedQuotation);
      });
      await _saveDraft();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Cotización actualizada y factura sincronizada'),
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

  void _applyQuotationToInvoice(CotizacionModel quotation) {
    _itemEditors = quotation.items
        .map(
          (item) => _InvoiceItemEditor(
            descriptionController: TextEditingController(text: item.nombre),
            qtyController: TextEditingController(
              text: item.qty.toStringAsFixed(2),
            ),
            unitPriceController: TextEditingController(
              text: item.unitPrice.toStringAsFixed(2),
            ),
          ),
        )
        .toList(growable: true);
    if (_itemEditors.isEmpty) {
      _itemEditors = <_InvoiceItemEditor>[_InvoiceItemEditor.empty()];
    }
    _taxController.text = quotation.itbisAmount.toStringAsFixed(2);
    _notesController.text = quotation.note;
  }

  String _slugify(String value) {
    final normalized = value.trim().toLowerCase();
    final collapsed = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String get _warrantyPreviewText {
    final serviceDuration =
        _serviceWarrantyDurationController.text.trim().isEmpty
        ? '3 meses'
        : _serviceWarrantyDurationController.text.trim();
    final productDuration =
        _productWarrantyDurationController.text.trim().isEmpty
        ? '6 meses'
        : _productWarrantyDurationController.text.trim();
    return 'The service has a warranty of $serviceDuration and the installed products have a warranty of $productDuration.';
  }

  @override
  Widget build(BuildContext context) {
    final flow = _flow;
    final hasGeneratedDocuments =
        (flow?.invoiceFinalUrl?.trim().isNotEmpty ?? false) ||
        (flow?.warrantyFinalUrl?.trim().isNotEmpty ?? false);
    final companySettings = ref.watch(companySettingsProvider).valueOrNull;

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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryCard(flow: flow),
                  const SizedBox(height: 16),
                  _buildInvoiceCard(flow, companySettings),
                  const SizedBox(height: 16),
                  _buildWarrantyCard(flow),
                  if (hasGeneratedDocuments) ...[
                    const SizedBox(height: 16),
                    _buildGeneratedFilesCard(flow),
                  ],
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
                ],
              ),
            ),
      bottomNavigationBar: flow == null || _loading || _error != null
          ? null
          : _BottomActionBar(
              saving: _saving,
              onSaveDraft: _saveDraft,
              onGenerateDocuments: _generateDocuments,
              onGenerateAndSend: _generateAndSend,
            ),
    );
  }

  Widget _buildInvoiceCard(
    OrderDocumentFlowModel flow,
    CompanySettings? companySettings,
  ) {
    final subtotal = _itemEditors
        .map((editor) => editor.toItem())
        .where((item) => item.description.trim().isNotEmpty)
        .fold<double>(0, (sum, item) => sum + item.lineTotal);
    final tax =
        double.tryParse(_taxController.text.trim()) ?? flow.invoiceDraft.tax;
    final total = subtotal + tax;

    return _SectionCard(
      icon: Icons.receipt_long_outlined,
      title: 'Factura / Cotización',
      subtitle: 'Detalle editable de productos y totales',
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InvoicePreviewHeader(
            companySettings: companySettings,
            flow: flow,
            currency: _currencyController.text.trim().isEmpty
                ? flow.invoiceDraft.currency
                : _currencyController.text.trim(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _currencyController,
                  decoration: const InputDecoration(labelText: 'Moneda'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _taxController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Impuesto'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _editLinkedQuotation,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Editar cotización vinculada'),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: const [
                Expanded(flex: 4, child: Text('Descripción')),
                Expanded(child: Text('Cant.', textAlign: TextAlign.center)),
                Expanded(child: Text('Precio', textAlign: TextAlign.center)),
                Expanded(child: Text('Subtotal', textAlign: TextAlign.center)),
                SizedBox(width: 40),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._itemEditors.asMap().entries.map((entry) {
            final index = entry.key;
            final editor = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _InvoiceItemEditorCard(
                editor: editor,
                canRemove: _itemEditors.length > 1,
                onRemove: () {
                  setState(() {
                    final removed = _itemEditors.removeAt(index);
                    removed.dispose();
                  });
                },
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
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notas',
              hintText: 'Observaciones internas o detalles para la factura',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _InfoChip(
                icon: Icons.summarize_outlined,
                label: 'Subtotal',
                value: subtotal.toStringAsFixed(2),
              ),
              _InfoChip(
                icon: Icons.receipt_outlined,
                label: 'Impuesto',
                value: tax.toStringAsFixed(2),
              ),
              _InfoChip(
                icon: Icons.payments_outlined,
                label: 'Total',
                value: total.toStringAsFixed(2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWarrantyCard(OrderDocumentFlowModel flow) {
    return _SectionCard(
      icon: Icons.verified_user_outlined,
      title: 'Garantía',
      subtitle: 'Cobertura, duraciones y condiciones del documento',
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _warrantyServiceTypeController,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de servicio',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _serviceWarrantyDurationController,
                  decoration: const InputDecoration(
                    labelText: 'Garantía del servicio',
                    hintText: '3 meses',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _productWarrantyDurationController,
                  decoration: const InputDecoration(
                    labelText: 'Garantía de productos',
                    hintText: '6 meses',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Categoría de orden',
                  ),
                  child: Text(flow.order.category),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Texto automático',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(_warrantyPreviewText),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _coverageController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Cobertura',
              hintText: 'Describe el alcance general de la garantía',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _conditionsController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Condiciones',
              hintText: 'Condiciones para aplicar la garantía',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _exclusionsController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Exclusiones',
              hintText: 'Casos no cubiertos por la garantía',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratedFilesCard(OrderDocumentFlowModel flow) {
    final invoiceUrl = flow.invoiceFinalUrl?.trim() ?? '';
    final warrantyUrl = flow.warrantyFinalUrl?.trim() ?? '';

    return _SectionCard(
      icon: Icons.folder_open_outlined,
      title: 'Archivos finales',
      subtitle: 'Documentos aprobados listos para revisar o descargar',
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGeneratedFileRow(
            label: 'Invoice PDF',
            rawUrl: invoiceUrl,
            previewTitle: 'Factura final',
          ),
          const SizedBox(height: 12),
          _buildGeneratedFileRow(
            label: 'Warranty PDF',
            rawUrl: warrantyUrl,
            previewTitle: 'Carta de garantía',
          ),
        ],
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
                label: const Text('Open'),
              ),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () => _downloadPdf(previewTitle, rawUrl),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download'),
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
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    flow.order.client.nombre,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _StatusChip(status: flow.status),
              ],
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

class _InvoicePreviewHeader extends StatelessWidget {
  const _InvoicePreviewHeader({
    required this.companySettings,
    required this.flow,
    required this.currency,
  });

  final CompanySettings? companySettings;
  final OrderDocumentFlowModel flow;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final company = companySettings ?? CompanySettings.empty();
    final invoiceNumber =
        'FACT-${flow.order.id.replaceAll('-', '').substring(0, 8).toUpperCase()}';
    final dateText = _formatDate(
      flow.order.finalizedAt ?? flow.order.updatedAt ?? flow.order.createdAt,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
        color: scheme.surface,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CompanyLogo(companySettings: company),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.companyName.trim().isEmpty
                          ? 'FULLTECH'
                          : company.companyName.trim(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (company.rnc.trim().isNotEmpty)
                      Text('RNC: ${company.rnc.trim()}'),
                    if (company.phone.trim().isNotEmpty)
                      Text('Tel: ${company.phone.trim()}'),
                    if (company.address.trim().isNotEmpty)
                      Text(company.address.trim()),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Datos de factura',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text('No. factura: $invoiceNumber'),
                    Text('Orden: ${flow.order.id}'),
                    Text('Moneda: $currency'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Datos del cliente',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(flow.order.client.nombre),
                    Text(flow.order.client.telefono),
                    if ((flow.order.client.direccion ?? '').trim().isNotEmpty)
                      Text(flow.order.client.direccion!.trim()),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Referencia',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text('Fecha: $dateText'),
                    Text(
                      'Cotización: ${(flow.order.quotationId ?? '').trim().isEmpty ? 'No vinculada' : flow.order.quotationId!.substring(0, flow.order.quotationId!.length >= 8 ? 8 : flow.order.quotationId!.length).toUpperCase()}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'No disponible';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }
}

class _CompanyLogo extends StatelessWidget {
  const _CompanyLogo({required this.companySettings});

  final CompanySettings companySettings;

  @override
  Widget build(BuildContext context) {
    final logo = companySettings.logoBase64?.trim() ?? '';
    final bytes = _decodeLogo(logo);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.contain)
          : Center(
              child: Text(
                _companyInitial(companySettings.companyName),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
    );
  }

  String _companyInitial(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'F';
    return normalized.substring(0, 1).toUpperCase();
  }

  Uint8List? _decodeLogo(String raw) {
    if (raw.isEmpty) return null;
    final normalized = raw.contains(',') ? raw.split(',').last : raw;
    try {
      return Uint8List.fromList(base64Decode(normalized));
    } catch (_) {
      return null;
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Icon(icon),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(subtitle),
          children: [child],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final DocumentFlowStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      DocumentFlowStatus.pendingPreparation => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      DocumentFlowStatus.readyForReview => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      DocumentFlowStatus.readyForFinalization => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      DocumentFlowStatus.approved => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      DocumentFlowStatus.rejected => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      DocumentFlowStatus.sent => (scheme.primary, scheme.onPrimary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text('$label: $value'),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.saving,
    required this.onSaveDraft,
    required this.onGenerateDocuments,
    required this.onGenerateAndSend,
  });

  final bool saving;
  final VoidCallback onSaveDraft;
  final VoidCallback onGenerateDocuments;
  final VoidCallback onGenerateAndSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: saving ? null : onSaveDraft,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Draft'),
            ),
            OutlinedButton.icon(
              onPressed: saving ? null : onGenerateDocuments,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Generate Documents'),
            ),
            FilledButton.tonalIcon(
              onPressed: saving ? null : onGenerateAndSend,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Generate & Send'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceItemEditorCard extends StatelessWidget {
  const _InvoiceItemEditorCard({
    required this.editor,
    required this.canRemove,
    required this.onRemove,
  });

  final _InvoiceItemEditor editor;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final subtotal = editor.toItem().lineTotal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        if (compact) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                TextField(
                  controller: editor.descriptionController,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: editor.qtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Cantidad',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: editor.unitPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Precio'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Subtotal',
                        ),
                        child: Text(subtotal.toStringAsFixed(2)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: canRemove ? onRemove : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  controller: editor.descriptionController,
                  decoration: const InputDecoration(labelText: 'Descripción'),
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
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Subtotal'),
                  child: Text(
                    subtotal.toStringAsFixed(2),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WarrantyFormData {
  const _WarrantyFormData({
    required this.title,
    required this.serviceType,
    required this.serviceWarrantyDuration,
    required this.productWarrantyDuration,
    required this.coverage,
    required this.conditions,
    required this.exclusions,
  });

  final String title;
  final String serviceType;
  final String serviceWarrantyDuration;
  final String productWarrantyDuration;
  final String coverage;
  final String conditions;
  final String exclusions;

  factory _WarrantyFormData.fromFlow(OrderDocumentFlowModel flow) {
    final draft = flow.warrantyDraft;
    String serviceWarrantyDuration = '3 meses';
    String productWarrantyDuration = '6 meses';
    String conditions = '';
    String exclusions = '';
    final extraConditions = <String>[];

    for (final term in draft.terms) {
      final value = term.trim();
      if (value.isEmpty) continue;
      if (value.toLowerCase().startsWith(
            'garantía del servicio:'.toLowerCase(),
          ) ||
          value.toLowerCase().startsWith('garantia del servicio:')) {
        serviceWarrantyDuration = value.split(':').skip(1).join(':').trim();
        continue;
      }
      if (value.toLowerCase().startsWith(
            'garantía de productos instalados:'.toLowerCase(),
          ) ||
          value.toLowerCase().startsWith('garantia de productos instalados:')) {
        productWarrantyDuration = value.split(':').skip(1).join(':').trim();
        continue;
      }
      if (value.toLowerCase().startsWith('condiciones:')) {
        conditions = value.split(':').skip(1).join(':').trim();
        continue;
      }
      if (value.toLowerCase().startsWith('exclusiones:')) {
        exclusions = value.split(':').skip(1).join(':').trim();
        continue;
      }
      extraConditions.add(value);
    }

    final mergedConditions = [
      if (conditions.isNotEmpty) conditions,
      ...extraConditions,
    ].join('\n');

    return _WarrantyFormData(
      title: draft.title.trim().isEmpty
          ? 'CARTA DE GARANTIA'
          : draft.title.trim(),
      serviceType: draft.serviceType.trim().isEmpty
          ? flow.order.serviceType
          : draft.serviceType.trim(),
      serviceWarrantyDuration: serviceWarrantyDuration.isEmpty
          ? '3 meses'
          : serviceWarrantyDuration,
      productWarrantyDuration: productWarrantyDuration.isEmpty
          ? '6 meses'
          : productWarrantyDuration,
      coverage: draft.summary,
      conditions: mergedConditions,
      exclusions: exclusions,
    );
  }

  List<String> toTerms() {
    return [
      if (serviceWarrantyDuration.trim().isNotEmpty)
        'Garantía del servicio: ${serviceWarrantyDuration.trim()}',
      if (productWarrantyDuration.trim().isNotEmpty)
        'Garantía de productos instalados: ${productWarrantyDuration.trim()}',
      ...conditions
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .map((item) => 'Condiciones: $item'),
      ...exclusions
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .map((item) => 'Exclusiones: $item'),
    ];
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
