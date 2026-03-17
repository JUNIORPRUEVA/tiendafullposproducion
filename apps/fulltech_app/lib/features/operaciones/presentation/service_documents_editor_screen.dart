import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/company/company_settings_model.dart';
import '../../../core/company/company_settings_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/storage/storage_models.dart';
import '../../../core/storage/storage_repository.dart';
import '../../../modules/cotizaciones/cotizacion_models.dart';
import '../../../modules/cotizaciones/data/cotizaciones_repository.dart';
import '../application/operations_controller.dart';
import '../data/operations_repository.dart';
import '../operations_models.dart';
import '../presentation/operations_permissions.dart';
import '../tecnico/application/tech_operations_controller.dart';
import '../tecnico/technical_service_execution_controller.dart';
import '../tecnico/widgets/service_report_pdf_screen.dart';
import 'service_pdf_exporter.dart';

enum ServiceDocumentType { invoice, warranty }

class ServiceDocumentsEditorScreen extends ConsumerStatefulWidget {
  final ServiceModel service;
  final ServiceDocumentType type;

  const ServiceDocumentsEditorScreen({
    super.key,
    required this.service,
    required this.type,
  });

  @override
  ConsumerState<ServiceDocumentsEditorScreen> createState() =>
      _ServiceDocumentsEditorScreenState();
}

class _ServiceDocumentsEditorScreenState
    extends ConsumerState<ServiceDocumentsEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  CompanySettings? _company;
  CotizacionModel? _baseQuote;
  bool _includeItbis = false;

  Uint8List? _signatureBytes;
  String? _signatureFileId;
  String? _signatureFileUrl;
  DateTime? _signedAt;

  final List<_EditableItemRow> _rows = [];

  bool get _isInvoice => widget.type == ServiceDocumentType.invoice;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitial());
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = widget.service;

      // Permissions guard (UI only; API also guards server-side).
      final user = ref.read(authStateProvider).user;
      final perms = OperationsPermissions(user: user, service: service);
      if (!perms.canCritical) {
        throw ApiException(perms.criticalDeniedReason ?? 'No autorizado');
      }

      CotizacionModel? quote;
      final phone = service.customerPhone.trim();
      if (phone.isNotEmpty) {
        try {
          final repo = ref.read(cotizacionesRepositoryProvider);
          final items = await repo.list(customerPhone: phone, take: 40);
          if (items.isNotEmpty) {
            final sorted = [...items];
            sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            quote = sorted.first;
          }
        } catch (_) {
          quote = null;
        }
      }

      CompanySettings? company;
      try {
        company = await ref.read(companySettingsProvider.future);
      } catch (_) {
        company = null;
      }

      await _loadClientSignature(service);

      if (!mounted) return;

      _baseQuote = quote;
      _company = company;
      _includeItbis = quote?.includeItbis ?? false;

      _rows.clear();
      final seedItems = (quote?.items ?? const <CotizacionItem>[]);
      if (seedItems.isNotEmpty) {
        for (final i in seedItems) {
          _rows.add(
            _EditableItemRow(
              name: i.nombre,
              qty: i.qty,
              unitPrice: i.unitPrice,
              showPrice: _isInvoice,
            ),
          );
        }
      } else {
        final fallbackPrice =
            (service.quotedAmount ?? service.depositAmount ?? 0).toDouble();
        _rows.add(
          _EditableItemRow(
            name: service.title.trim().isEmpty ? 'Servicio' : service.title,
            qty: 1.0,
            unitPrice: fallbackPrice,
            showPrice: _isInvoice,
          ),
        );
      }

      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  ServiceFileModel? _findLatestFileByType(ServiceModel service, String type) {
    final t = type.trim().toLowerCase();
    final candidates = service.files
        .where((f) => f.fileType.trim().toLowerCase() == t)
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    return candidates.first;
  }

  Future<void> _loadClientSignature(ServiceModel service) async {
    // Try the technical execution state first (it may contain `signedAt`).
    try {
      final st = ref.read(technicalExecutionControllerProvider(service.id));
      final raw = st.phaseSpecificData['clientSignature'];
      if (raw is Map) {
        final map = raw.cast<String, dynamic>();
        final fileId = (map['fileId'] ?? '').toString().trim();
        final fileUrl = (map['fileUrl'] ?? '').toString().trim();
        final signedAt = map['signedAt'] == null
            ? null
            : DateTime.tryParse(map['signedAt'].toString());

        if (fileUrl.isNotEmpty) {
          _signatureFileId = fileId.isEmpty ? null : fileId;
          _signatureFileUrl = fileUrl;
          _signedAt = signedAt;
          _signatureBytes = await _downloadBytes(fileUrl);
          return;
        }
      }
    } catch (_) {
      // ignore
    }

    final latest = _findLatestFileByType(service, 'client_signature');
    if (latest == null) return;
    final url = latest.fileUrl.trim();
    if (url.isEmpty) return;

    _signatureFileId = latest.id.trim().isEmpty ? null : latest.id.trim();
    _signatureFileUrl = url;
    _signedAt = latest.createdAt;
    try {
      _signatureBytes = await _downloadBytes(url);
    } catch (_) {
      _signatureBytes = null;
    }
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final dio = ref.read(dioProvider);
    try {
      final res = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data != null && data.isNotEmpty) {
        return Uint8List.fromList(data);
      }
    } catch (_) {
      // Retry below using a stream response. Some Windows/desktop flows can
      // return empty bytes for binary content even when the URL is valid.
    }

    final streamRes = await dio.get<ResponseBody>(
      url,
      options: Options(responseType: ResponseType.stream),
    );
    final body = streamRes.data;
    if (body == null) return Uint8List(0);
    final chunks = await body.stream.toList();
    if (chunks.isEmpty) return Uint8List(0);

    final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final bytes = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return bytes;
  }

  ServiceFileModel _serviceFileFromConfirmedUpload(ServiceMediaModel media) {
    return ServiceFileModel(
      id: media.id,
      fileUrl: media.fileUrl,
      fileType: media.fileType,
      mimeType: media.mimeType,
      caption: media.caption,
      createdAt: media.createdAt ?? DateTime.now(),
    );
  }

  ServiceModel _mergeUploadedFileIntoService(
    ServiceModel service,
    ServiceMediaModel media,
  ) {
    final nextFiles = [
      ...service.files.where((file) => file.id != media.id),
      _serviceFileFromConfirmedUpload(media),
    ];
    nextFiles.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return service.copyWith(files: nextFiles);
  }

  void _applyOptimisticRefresh(ServiceModel service) {
    ref
        .read(operationsControllerProvider.notifier)
        .applyRealtimeService(service);
    ref
        .read(techOperationsControllerProvider.notifier)
        .applyRealtimeService(service);
  }

  void _refreshServiceInBackground(ServiceModel fallback) {
    unawaited(() async {
      try {
        final refreshed = await ref
            .read(operationsRepositoryProvider)
            .getService(widget.service.id);
        _applyOptimisticRefresh(refreshed);
      } catch (_) {
        _applyOptimisticRefresh(fallback);
      }

      try {
        await ref
            .read(
              technicalExecutionControllerProvider(widget.service.id).notifier,
            )
            .load();
      } catch (_) {
        // Ignore reload failures: the document has already been confirmed.
      }
    }());
  }

  CotizacionModel _buildQuoteSnapshot() {
    final service = widget.service;

    final cleaned = _rows
        .map((r) => r.toItem(showPrice: _isInvoice))
        .where((i) => i != null)
        .cast<CotizacionItem>()
        .toList(growable: false);

    return CotizacionModel(
      id: 'custom',
      createdAt: DateTime.now(),
      customerId: null,
      customerName: service.customerName.trim().isEmpty
          ? 'Cliente'
          : service.customerName,
      customerPhone: service.customerPhone.trim().isEmpty
          ? null
          : service.customerPhone.trim(),
      note: 'Documento editado',
      includeItbis: _includeItbis,
      itbisRate: _baseQuote?.itbisRate ?? 0.18,
      items: cleaned,
    );
  }

  Future<Uint8List> _buildPdfBytes() async {
    final quote = _buildQuoteSnapshot();

    if (_isInvoice) {
      return ServicePdfExporter.buildInvoicePdfBytes(
        widget.service,
        cotizacion: quote,
        company: _company,
        clientSignaturePngBytes: _signatureBytes,
        clientSignatureFileId: _signatureFileId,
        clientSignatureFileUrl: _signatureFileUrl,
        clientSignedAt: _signedAt,
      );
    }

    return ServicePdfExporter.buildWarrantyLetterBytes(
      widget.service,
      cotizacion: quote,
      company: _company,
      clientSignaturePngBytes: _signatureBytes,
      clientSignatureFileId: _signatureFileId,
      clientSignatureFileUrl: _signatureFileUrl,
      clientSignedAt: _signedAt,
    );
  }

  String _kind() {
    switch (widget.type) {
      case ServiceDocumentType.invoice:
        return 'service_invoice_custom';
      case ServiceDocumentType.warranty:
        return 'service_warranty_custom';
    }
  }

  String _fileName() {
    final order = widget.service.orderLabel.trim().isEmpty
        ? widget.service.id
        : widget.service.orderLabel.trim();
    return widget.type == ServiceDocumentType.invoice
        ? 'Factura-$order.pdf'
        : 'Carta-Garantia-$order.pdf';
  }

  String _caption() {
    return widget.type == ServiceDocumentType.invoice
        ? 'Factura (editada)'
        : 'Carta de garantía (editada)';
  }

  Future<void> _preview() async {
    if (_saving) return;
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServiceReportPdfScreen(
          fileName: _fileName(),
          loadBytes: _buildPdfBytes,
          currentUser: ref.read(authStateProvider).user,
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final bytes = await _buildPdfBytes();

      final storage = ref.read(storageRepositoryProvider);
      final kind = _kind();

      final presign = await storage.presign(
        serviceId: widget.service.id,
        fileName: _fileName(),
        contentType: 'application/pdf',
        fileSize: bytes.length,
        kind: kind,
      );

      await storage.uploadToPresignedUrl(
        uploadUrl: presign.uploadUrl,
        bytes: bytes,
        contentType: 'application/pdf',
        contentLength: bytes.length,
      );

      final confirmed = await storage.confirm(
        serviceId: widget.service.id,
        objectKey: presign.objectKey,
        publicUrl: presign.publicUrl,
        fileName: _fileName(),
        mimeType: 'application/pdf',
        fileSize: bytes.length,
        kind: kind,
        caption: _caption(),
      );

      final optimistic = _mergeUploadedFileIntoService(
        widget.service,
        confirmed,
      );
      _applyOptimisticRefresh(optimistic);
      _refreshServiceInBackground(optimistic);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Documento guardado')));

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isInvoice ? 'Editar Factura' : 'Editar Carta de Garantía';

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(title),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _preview,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Ver'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_isInvoice) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Incluir ITBIS'),
                      value: _includeItbis,
                      onChanged: (v) => setState(() => _includeItbis = v),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    'Items',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final row in _rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ItemEditorRow(
                        row: row,
                        showPrice: _isInvoice,
                        onRemove: _rows.length <= 1
                            ? null
                            : () {
                                setState(() {
                                  _rows.remove(row);
                                  row.dispose();
                                });
                              },
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _rows.add(
                          _EditableItemRow(
                            name: '',
                            qty: 1.0,
                            unitPrice: 0.0,
                            showPrice: _isInvoice,
                          ),
                        );
                      });
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Agregar item'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Guardando…' : 'Guardar PDF'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _EditableItemRow {
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;

  _EditableItemRow({
    required String name,
    required double qty,
    required double unitPrice,
    required bool showPrice,
  }) : nameCtrl = TextEditingController(text: name),
       qtyCtrl = TextEditingController(
         text: qty == 0 ? '' : qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2),
       ),
       priceCtrl = TextEditingController(
         text: showPrice
             ? unitPrice.toStringAsFixed(2)
             : unitPrice.toStringAsFixed(2),
       );

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }

  CotizacionItem? toItem({required bool showPrice}) {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return null;

    final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0.0;
    final unit = showPrice
        ? (double.tryParse(priceCtrl.text.trim()) ?? 0.0)
        : 0.0;

    if (qty <= 0) return null;

    return CotizacionItem(
      productId: '',
      nombre: name,
      imageUrl: null,
      unitPrice: unit,
      qty: qty,
    );
  }
}

class _ItemEditorRow extends StatelessWidget {
  final _EditableItemRow row;
  final bool showPrice;
  final VoidCallback? onRemove;

  const _ItemEditorRow({
    required this.row,
    required this.showPrice,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: row.nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) return 'Requerido';
                      return null;
                    },
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: row.qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final raw = (v ?? '').trim();
                      final parsed = double.tryParse(raw);
                      if (parsed == null || parsed <= 0) return 'Requerido';
                      return null;
                    },
                  ),
                ),
                if (showPrice) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: row.priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Precio unit.',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final raw = (v ?? '').trim();
                        final parsed = double.tryParse(raw);
                        if (parsed == null || parsed < 0) return 'Inválido';
                        return null;
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
