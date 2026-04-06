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
  _DocumentEditorSection _selectedSection = _DocumentEditorSection.warranty;
  bool? _approvalDecision;

  @override
  void initState() {
    super.initState();
    _taxController.addListener(_handleDraftValueChanged);
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
    _detachEditorListeners(_itemEditors);
    for (final editor in _itemEditors) {
      editor.dispose();
    }
  }

  void _handleDraftValueChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _attachEditorListeners(Iterable<_InvoiceItemEditor> editors) {
    for (final editor in editors) {
      editor.addListener(_handleDraftValueChanged);
    }
  }

  void _detachEditorListeners(Iterable<_InvoiceItemEditor> editors) {
    for (final editor in editors) {
      editor.removeListener(_handleDraftValueChanged);
    }
  }

  List<DocumentFlowInvoiceItem> get _draftItems => _itemEditors
      .map((editor) => editor.toItem())
      .where((item) => item.description.trim().isNotEmpty)
      .toList(growable: false);

  double get _draftSubtotal => _draftItems.fold<double>(
    0,
    (sum, item) => sum + item.lineTotal,
  );

  double get _draftTax => double.tryParse(_taxController.text.trim()) ?? 0;

  double get _draftTotal => _draftSubtotal + _draftTax;

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
    _attachEditorListeners(_itemEditors);
    _approvalDecision = switch (flow.status) {
      DocumentFlowStatus.approved || DocumentFlowStatus.sent => true,
      DocumentFlowStatus.rejected => false,
      _ => null,
    };
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
      final invoiceItems = _draftItems;
      final subtotal = _draftSubtotal;
      final tax = _draftTax;
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
    _disposeEditors();
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
    _attachEditorListeners(_itemEditors);
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
    return 'El servicio tiene una garantía de $serviceDuration y los productos instalados tienen una garantía de $productDuration.';
  }

  @override
  Widget build(BuildContext context) {
    final flow = _flow;
    final subtotal = _draftSubtotal;
    final tax = _taxController.text.trim().isEmpty
        ? flow?.invoiceDraft.tax ?? 0
        : _draftTax;
    final total = subtotal + tax;
    final currency = _currencyController.text.trim().isEmpty
      ? flow?.invoiceDraft.currency ?? 'RD$'
      : _currencyController.text.trim();
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 136),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryCard(flow: flow),
                  const SizedBox(height: 16),
                  _buildApprovalCard(flow),
                  const SizedBox(height: 16),
                  _buildSectionSelector(),
                  const SizedBox(height: 16),
                  if (_selectedSection == _DocumentEditorSection.warranty)
                    _buildWarrantyCard(flow)
                  else
                    _buildInvoiceCard(flow, companySettings),
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
              selectedSection: _selectedSection,
              currency: currency,
              subtotal: subtotal,
              tax: tax,
              total: total,
              onSaveDraft: _saveDraft,
              onGenerateDocuments: _generateDocuments,
              onGenerateAndSend: _generateAndSend,
            ),
    );
  }

  Widget _buildApprovalCard(OrderDocumentFlowModel flow) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Aprobar o no?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Estado actual: ${flow.status.label}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Aprobar'),
                  selected: _approvalDecision == true,
                  onSelected: (_) {
                    setState(() {
                      _approvalDecision = true;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('No aprobar'),
                  selected: _approvalDecision == false,
                  onSelected: (_) {
                    setState(() {
                      _approvalDecision = false;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionSelector() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selecciona qué quieres editar',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SectionOptionCard(
                    title: 'Carta',
                    subtitle: 'Garantía final',
                    icon: Icons.verified_user_outlined,
                    selected:
                        _selectedSection == _DocumentEditorSection.warranty,
                    onTap: () {
                      setState(() {
                        _selectedSection = _DocumentEditorSection.warranty;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SectionOptionCard(
                    title: 'Factura',
                    subtitle: 'Detalle comercial',
                    icon: Icons.receipt_long_outlined,
                    selected:
                        _selectedSection == _DocumentEditorSection.invoice,
                    onTap: () {
                      setState(() {
                        _selectedSection = _DocumentEditorSection.invoice;
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceCard(
    OrderDocumentFlowModel flow,
    CompanySettings? companySettings,
  ) {
    final subtotal = _draftSubtotal;
    final tax = _taxController.text.trim().isEmpty
        ? flow.invoiceDraft.tax
        : _draftTax;
    final total = subtotal + tax;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Factura', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Diseño compacto para editar más líneas sin perder visibilidad.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            _InvoicePreviewHeader(
              companySettings: companySettings,
              flow: flow,
              currency: _currencyController.text.trim().isEmpty
                  ? flow.invoiceDraft.currency
                  : _currencyController.text.trim(),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                if (compact) {
                  return Column(
                    children: [
                      TextField(
                        controller: _currencyController,
                        decoration: _compactFieldDecoration(label: 'Moneda'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _taxController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _compactFieldDecoration(label: 'Impuesto'),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _editLinkedQuotation,
                          icon: const Icon(Icons.edit_note_outlined),
                          label: const Text('Editar cotización vinculada'),
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _currencyController,
                        decoration: _compactFieldDecoration(label: 'Moneda'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _taxController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _compactFieldDecoration(label: 'Impuesto'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _editLinkedQuotation,
                      icon: const Icon(Icons.edit_note_outlined),
                      label: const Text('Editar cotización'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: const [
                  Expanded(flex: 5, child: Text('Descripción')),
                  SizedBox(
                    width: 72,
                    child: Text('Cant.', textAlign: TextAlign.center),
                  ),
                  SizedBox(
                    width: 92,
                    child: Text('Precio', textAlign: TextAlign.center),
                  ),
                  SizedBox(
                    width: 108,
                    child: Text('Importe', textAlign: TextAlign.center),
                  ),
                  SizedBox(width: 36),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ..._itemEditors.asMap().entries.map((entry) {
              final index = entry.key;
              final editor = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _InvoiceItemEditorCard(
                  editor: editor,
                  canRemove: _itemEditors.length > 1,
                  onRemove: () {
                    setState(() {
                      final removed = _itemEditors.removeAt(index);
                      removed.removeListener(_handleDraftValueChanged);
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
                    final newEditor = _InvoiceItemEditor.empty();
                    newEditor.addListener(_handleDraftValueChanged);
                    _itemEditors = List<_InvoiceItemEditor>.from(_itemEditors)
                      ..add(newEditor);
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('Agregar línea'),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: _compactFieldDecoration(
                label: 'Notas',
                hintText: 'Observaciones internas o detalles para la factura',
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: scheme.surfaceContainerLow,
              ),
              child: Text(
                'Resumen actual: subtotal ${subtotal.toStringAsFixed(2)} • impuesto ${tax.toStringAsFixed(2)} • total ${total.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarrantyCard(OrderDocumentFlowModel flow) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Carta', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _warrantyServiceTypeController,
                    decoration: _compactFieldDecoration(
                      label: 'Tipo de servicio',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _serviceWarrantyDurationController,
                    decoration: _compactFieldDecoration(
                      label: 'Garantía del servicio',
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
                    decoration: _compactFieldDecoration(
                      label: 'Garantía de productos',
                      hintText: '6 meses',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InputDecorator(
                    decoration: _compactFieldDecoration(
                      label: 'Categoría de orden',
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
              decoration: _compactFieldDecoration(
                label: 'Cobertura',
                hintText: 'Describe el alcance general de la garantía',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _conditionsController,
              maxLines: 4,
              decoration: _compactFieldDecoration(
                label: 'Condiciones',
                hintText: 'Condiciones para aplicar la garantía',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _exclusionsController,
              maxLines: 4,
              decoration: _compactFieldDecoration(
                label: 'Exclusiones',
                hintText: 'Casos no cubiertos por la garantía',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratedFilesCard(OrderDocumentFlowModel flow) {
    final invoiceUrl = flow.invoiceFinalUrl?.trim() ?? '';
    final warrantyUrl = flow.warrantyFinalUrl?.trim() ?? '';
    final isInvoiceSelected =
        _selectedSection == _DocumentEditorSection.invoice;
    final selectedLabel = isInvoiceSelected ? 'Factura PDF' : 'Carta PDF';
    final selectedUrl = isInvoiceSelected ? invoiceUrl : warrantyUrl;
    final selectedPreviewTitle = isInvoiceSelected
        ? 'Factura final'
        : 'Carta de garantía';
    final selectedSubtitle = isInvoiceSelected
        ? 'Se muestra el PDF de la factura porque esa es la sección seleccionada'
        : 'Se muestra el PDF de la carta porque esa es la sección seleccionada';

    return _SectionCard(
      icon: Icons.folder_open_outlined,
      title: 'PDF seleccionado',
      subtitle: selectedSubtitle,
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGeneratedFileRow(
            label: selectedLabel,
            rawUrl: selectedUrl,
            previewTitle: selectedPreviewTitle,
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
                label: const Text('Abrir'),
              ),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () => _downloadPdf(previewTitle, rawUrl),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Descargar'),
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
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
              spacing: 8,
              runSpacing: 8,
              children: [
                _SummaryInfoTag(
                  icon: Icons.tag_outlined,
                  label: 'Orden',
                  value: flow.order.id,
                  color: scheme.surfaceContainerHighest,
                ),
                _SummaryInfoTag(
                  icon: Icons.pending_actions_outlined,
                  label: 'Flujo',
                  value: flow.status.label,
                  color: scheme.surfaceContainerHighest,
                ),
                _SummaryInfoTag(
                  icon: Icons.build_circle_outlined,
                  label: 'Estado',
                  value: flow.order.status,
                  color: scheme.surfaceContainerHighest,
                ),
                _SummaryInfoTag(
                  icon: Icons.phone_outlined,
                  label: 'Teléfono',
                  value: flow.order.client.telefono,
                  color: scheme.surfaceContainerHighest,
                ),
              ],
            ),
            if ((flow.order.client.direccion ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Dirección: ${flow.order.client.direccion}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
                    Text('Factura No.: $invoiceNumber'),
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

enum _DocumentEditorSection { warranty, invoice }

class _SectionOptionCard extends StatelessWidget {
  const _SectionOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.saving,
    required this.selectedSection,
    required this.currency,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.onSaveDraft,
    required this.onGenerateDocuments,
    required this.onGenerateAndSend,
  });

  final bool saving;
  final _DocumentEditorSection selectedSection;
  final String currency;
  final double subtotal;
  final double tax;
  final double total;
  final VoidCallback onSaveDraft;
  final VoidCallback onGenerateDocuments;
  final VoidCallback onGenerateAndSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showTotals = selectedSection == _DocumentEditorSection.invoice;
            final compact = constraints.maxWidth < 980;
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: saving ? null : onSaveDraft,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar'),
                ),
                OutlinedButton.icon(
                  onPressed: saving ? null : onGenerateDocuments,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Generar'),
                ),
                FilledButton.tonalIcon(
                  onPressed: saving ? null : onGenerateAndSend,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Enviar'),
                ),
              ],
            );
            final totalsPanel = showTotals
                ? _FooterTotalsPanel(
                    currency: currency,
                    subtotal: subtotal,
                    tax: tax,
                    total: total,
                  )
                : null;

            if (compact || totalsPanel == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (totalsPanel != null) ...[
                    totalsPanel,
                    const SizedBox(height: 10),
                  ],
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: totalsPanel),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
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
    final outline = Theme.of(context).colorScheme.outlineVariant;
    final descriptionDecoration = _compactFieldDecoration(label: 'Descripción');
    final qtyDecoration = _compactFieldDecoration(label: 'Cant.');
    final priceDecoration = _compactFieldDecoration(label: 'Precio');
    final amountDecoration = _compactFieldDecoration(label: 'Importe');

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        if (compact) {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: outline),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                TextField(
                  controller: editor.descriptionController,
                  decoration: descriptionDecoration,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: editor.qtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.center,
                        decoration: qtyDecoration,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: editor.unitPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.right,
                        decoration: priceDecoration,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: amountDecoration,
                        child: Text(
                          subtotal.toStringAsFixed(2),
                          textAlign: TextAlign.right,
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
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: outline),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: editor.descriptionController,
                  decoration: descriptionDecoration,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: editor.qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  decoration: qtyDecoration,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: TextField(
                  controller: editor.unitPriceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.right,
                  decoration: priceDecoration,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 108,
                child: InputDecorator(
                  decoration: amountDecoration,
                  child: Text(
                    subtotal.toStringAsFixed(2),
                    textAlign: TextAlign.right,
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

  void addListener(VoidCallback listener) {
    descriptionController.addListener(listener);
    qtyController.addListener(listener);
    unitPriceController.addListener(listener);
  }

  void removeListener(VoidCallback listener) {
    descriptionController.removeListener(listener);
    qtyController.removeListener(listener);
    unitPriceController.removeListener(listener);
  }
}

class _SummaryInfoTag extends StatelessWidget {
  const _SummaryInfoTag({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _FooterTotalsPanel extends StatelessWidget {
  const _FooterTotalsPanel({
    required this.currency,
    required this.subtotal,
    required this.tax,
    required this.total,
  });

  final String currency;
  final double subtotal;
  final double tax;
  final double total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _InfoChip(
            icon: Icons.summarize_outlined,
            label: 'Subtotal',
            value: '$currency ${subtotal.toStringAsFixed(2)}',
          ),
          _InfoChip(
            icon: Icons.receipt_outlined,
            label: 'Impuesto',
            value: '$currency ${tax.toStringAsFixed(2)}',
          ),
          _InfoChip(
            icon: Icons.payments_outlined,
            label: 'Total',
            value: '$currency ${total.toStringAsFixed(2)}',
          ),
        ],
      ),
    );
  }
}

InputDecoration _compactFieldDecoration({
  required String label,
  String? hintText,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
}
