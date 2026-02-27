import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/role_permissions.dart';
import '../../core/errors/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import 'data/contabilidad_repository.dart';
import 'models/fiscal_invoice_model.dart';
import 'utils/fiscal_invoices_pdf_service.dart';
import 'widgets/app_card.dart';
import 'widgets/section_title.dart';

class FacturaFiscalScreen extends ConsumerStatefulWidget {
  const FacturaFiscalScreen({super.key});

  @override
  ConsumerState<FacturaFiscalScreen> createState() => _FacturaFiscalScreenState();
}

class _FacturaFiscalScreenState extends ConsumerState<FacturaFiscalScreen> {
  final _noteCtrl = TextEditingController();
  DateTime _invoiceDate = DateTime.now();
  FiscalInvoiceKind _kind = FiscalInvoiceKind.purchase;
  PlatformFile? _selectedFile;

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  FiscalInvoiceKind? _kindFilter;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<FiscalInvoiceModel> _invoices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(contabilidadRepositoryProvider).listFiscalInvoices(
            from: _from,
            to: _to,
        kind: _kindFilter,
          );
      if (!mounted) return;
      setState(() {
        _invoices = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'No se pudieron cargar facturas';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canUseModule = canAccessContabilidadByRole(user?.role);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Factura fiscal'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      drawer: AppDrawer(currentUser: user),
      body: !canUseModule
          ? const Center(
              child: Text(
                'Solo ADMIN y ASISTENTE tienen acceso completo a este módulo.',
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildFiltersCard(context),
                  const SizedBox(height: 12),
                  _buildUploadCard(context),
                  const SizedBox(height: 12),
                  _buildHeaderActions(context),
                  const SizedBox(height: 8),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _ErrorBox(message: _error!),
                    ),
                  const SizedBox(height: 8),
                  ..._invoices
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _InvoiceCard(item: item),
                        ),
                      )
                      .toList(),
                  if (!_loading && _invoices.isEmpty)
                    const AppCard(
                      child: Text(
                        'No hay facturas fiscales en el rango seleccionado.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildFiltersCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(title: 'Filtro por fecha'),
          const SizedBox(height: 10),
          Text(
            '${DateFormat('dd/MM/yyyy').format(_from)} - ${DateFormat('dd/MM/yyyy').format(_to)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
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
                    initialDateRange: DateTimeRange(start: _from, end: _to),
                  );
                  if (range == null) return;
                  setState(() {
                    _from = range.start;
                    _to = range.end;
                  });
                  await _load();
                },
                icon: const Icon(Icons.date_range_outlined),
                label: const Text('Intervalo de fecha'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Tipo de factura',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Todas'),
                selected: _kindFilter == null,
                onSelected: (_) async {
                  setState(() => _kindFilter = null);
                  await _load();
                },
              ),
              ChoiceChip(
                label: const Text('Compras'),
                selected: _kindFilter == FiscalInvoiceKind.purchase,
                onSelected: (_) async {
                  setState(() => _kindFilter = FiscalInvoiceKind.purchase);
                  await _load();
                },
              ),
              ChoiceChip(
                label: const Text('Ventas'),
                selected: _kindFilter == FiscalInvoiceKind.sale,
                onSelected: (_) async {
                  setState(() => _kindFilter = FiscalInvoiceKind.sale);
                  await _load();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUploadCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(title: 'Nueva factura fiscal'),
          const SizedBox(height: 10),
          SegmentedButton<FiscalInvoiceKind>(
            segments: const [
              ButtonSegment(value: FiscalInvoiceKind.purchase, label: Text('Compra')),
              ButtonSegment(value: FiscalInvoiceKind.sale, label: Text('Venta')),
            ],
            selected: {_kind},
            onSelectionChanged: (next) {
              setState(() => _kind = next.first);
            },
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _invoiceDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked == null) return;
              setState(() => _invoiceDate = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Fecha factura'),
              child: Text(DateFormat('dd/MM/yyyy').format(_invoiceDate)),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _noteCtrl,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Anote / observación',
              hintText: 'Ej: NCF válido, proveedor, detalle importante...',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
                      withData: true,
                    );
                    if (result == null || result.files.isEmpty) return;
                    setState(() => _selectedFile = result.files.first);
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Subir imagen factura'),
                ),
              ),
            ],
          ),
          if (_selectedFile != null) ...[
            const SizedBox(height: 8),
            Text(
              'Archivo: ${_selectedFile!.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      if (_selectedFile == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Debes seleccionar una imagen de factura.'),
                          ),
                        );
                        return;
                      }

                      setState(() {
                        _saving = true;
                        _error = null;
                      });
                      try {
                        final repo = ref.read(contabilidadRepositoryProvider);
                        // La imagen se sube primero a la nube por API y luego
                        // se guarda el registro con la URL cloud resultante.
                        final imageUrl = await repo.uploadFiscalInvoiceImage(_selectedFile!);
                        await repo.createFiscalInvoice(
                          kind: _kind,
                          invoiceDate: _invoiceDate,
                          imageUrl: imageUrl,
                          note: _noteCtrl.text,
                        );

                        if (!mounted) return;
                        setState(() {
                          _saving = false;
                          _selectedFile = null;
                          _noteCtrl.clear();
                        });
                        await _load();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Factura fiscal guardada en la nube.'),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        setState(() {
                          _saving = false;
                          _error = e is ApiException
                              ? e.message
                              : 'No se pudo guardar la factura fiscal';
                        });
                      }
                    },
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: const Text('Guardar factura fiscal en nube'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SectionTitle(
            title: 'Facturas fiscales (${_invoices.length})',
            trailing: TextButton.icon(
              onPressed: _invoices.isEmpty
                  ? null
                  : () async {
                      final bytes = await buildFiscalInvoicesPdf(
                        from: _from,
                        to: _to,
                        invoices: _invoices,
                      );
                      if (!mounted) return;
                      await _openPdfDialog(context, bytes);
                    },
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF contable'),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openPdfDialog(BuildContext context, Uint8List bytes) async {
    final filename =
        'facturas_fiscales_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

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
                        'PDF facturas fiscales',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Descargar / compartir',
                      onPressed: () => Printing.sharePdf(bytes: bytes, filename: filename),
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
                  build: (_) async => bytes,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final FiscalInvoiceModel item;

  const _InvoiceCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.kind.label} · ${dateFmt.format(item.invoiceDate)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                dateFmt.format(item.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                item.imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const Text('No se pudo cargar imagen'),
                ),
              ),
            ),
          ),
          if ((item.note ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Nota: ${item.note!.trim()}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Registrado por: ${item.createdByName ?? item.createdById ?? 'N/D'}',
            style: Theme.of(context).textTheme.bodySmall,
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
