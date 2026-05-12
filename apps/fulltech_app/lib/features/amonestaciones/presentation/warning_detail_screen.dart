import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/env.dart';
import '../application/warnings_controller.dart';
import '../data/employee_warning_model.dart';
import '../data/employee_warnings_repository.dart';
import 'warning_create_screen.dart';
import 'warning_labels.dart';

class WarningDetailScreen extends ConsumerStatefulWidget {
  final String warningId;
  const WarningDetailScreen({super.key, required this.warningId});

  @override
  ConsumerState<WarningDetailScreen> createState() => _WarningDetailScreenState();
}

class _WarningDetailScreenState extends ConsumerState<WarningDetailScreen> {
  bool _actionLoading = false;

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(canAccessAmonestacionesProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle amonestacion')),
        body: const Center(child: Text('Acceso no permitido para este usuario')),
      );
    }

    final async = ref.watch(warningDetailProvider(widget.warningId));
    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Detalle amonestacion')),
        body: Center(child: Text('Error: $e')),
      ),
      data: (w) => _buildBody(context, w),
    );
  }

  Widget _buildBody(BuildContext context, EmployeeWarning w) {
    final statusColor = WarningLabels.statusColor(w.status);
    final reason = (w.reason ?? w.title).trim();
    final details = (w.details ?? w.description).trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: Text(w.warningNumber),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        actions: [
          if (w.status == 'DRAFT')
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
              onPressed: () => _openEdit(context, w),
            ),
          if (w.status == 'DRAFT')
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar',
              onPressed: _actionLoading ? null : () => _deleteWarning(context, w),
            ),
          if (w.status != 'ANNULLED')
            IconButton(
              icon: const Icon(Icons.block_rounded),
              tooltip: 'Anular',
              onPressed: _actionLoading ? null : () => _annul(context, w),
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Regenerar PDF',
            onPressed: _actionLoading ? null : () => _regeneratePdf(context, w),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    reason.isEmpty ? 'Sin motivo' : reason,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                _Pill(
                  label: WarningLabels.status[w.status] ?? w.status,
                  color: statusColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _InfoPanel(title: 'Empleado', rows: [
            ('Nombre', _v(w.employeeNameSnapshot ?? w.employeeUser?.nombreCompleto)),
            ('Cedula', _v(w.employeeCedulaSnapshot ?? w.employeeUser?.cedula)),
            ('Cargo', _v(w.employeePositionSnapshot ?? w.employeeUser?.workContractJobTitle)),
            ('Departamento/Area', _v(w.employeeDepartmentSnapshot)),
            ('Telefono', _v(w.employeePhoneSnapshot ?? w.employeeUser?.telefono)),
          ]),
          const SizedBox(height: 10),
          _InfoPanel(title: 'Documento', rows: [
            ('Fecha amonestacion', WarningLabels.fmt(w.warningDate)),
            ('Fecha del hecho', WarningLabels.fmt(w.incidentDate)),
            ('Hora aproximada', _v(w.incidentTime)),
            ('Lugar', _v(w.incidentPlace)),
            (
              'Tipo',
              WarningLabels.warningType[w.warningType ?? ''] ?? _v(w.warningType),
            ),
            ('Encargado', _v(w.issuedByNameSnapshot ?? w.createdByUser?.nombreCompleto)),
            ('Cargo encargado', _v(w.issuedByPositionSnapshot ?? w.createdByUser?.workContractJobTitle)),
          ]),
          const SizedBox(height: 10),
          _InfoPanel(title: 'Empresa', rows: [
            ('Nombre', _v(w.companyNameSnapshot)),
            ('RNC', _v(w.companyRncSnapshot)),
            ('Direccion', _v(w.companyAddressSnapshot)),
          ]),
          const SizedBox(height: 10),
          _TextPanel(title: 'Motivo', text: reason),
          const SizedBox(height: 10),
          _TextPanel(title: 'Detalle de los hechos', text: details),
          const SizedBox(height: 10),
          _TextPanel(
            title: 'Texto completo generado',
            text: (w.generatedText ?? '').trim().isEmpty ? details : (w.generatedText ?? '').trim(),
          ),
          if ((w.internalNotes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _TextPanel(title: 'Observaciones internas', text: (w.internalNotes ?? '').trim()),
          ],
          if (w.pdfUrl != null || w.signedPdfUrl != null) ...[
            const SizedBox(height: 10),
            _PdfPanel(
              warning: w,
              warningId: w.id,
              onOpenInApp: (url) => _openPdfInApp(context, url, w.id),
            ),
          ],
          if (w.signatures.isNotEmpty) ...[
            const SizedBox(height: 10),
            _TextPanel(
              title: 'Firma legacy (historico)',
              text: 'Este registro conserva datos de firma historicos del flujo anterior.',
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _v(String? value) {
    final v = (value ?? '').trim();
    return v.isEmpty ? 'No registrado' : v;
  }

  Future<void> _annul(BuildContext context, EmployeeWarning w) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Anular amonestacion'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Motivo de anulacion',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Anular')),
        ],
      ),
    );
    if (ok != true) return;
    if (reasonCtrl.text.trim().isEmpty) return;

    setState(() => _actionLoading = true);
    try {
      await ref.read(employeeWarningsRepositoryProvider).annul(w.id, reasonCtrl.text.trim());
      ref.invalidate(warningDetailProvider(w.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amonestacion anulada'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _deleteWarning(BuildContext context, EmployeeWarning w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar borrador'),
        content: const Text('Esta accion no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _actionLoading = true);
    try {
      await ref.read(employeeWarningsRepositoryProvider).delete(w.id);
      ref.invalidate(warningsListControllerProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amonestacion eliminada'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _regeneratePdf(BuildContext context, EmployeeWarning w) async {
    setState(() => _actionLoading = true);
    try {
      await ref.read(employeeWarningsRepositoryProvider).generatePdf(w.id);
      ref.invalidate(warningDetailProvider(w.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF regenerado'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  void _openEdit(BuildContext context, EmployeeWarning w) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WarningCreateScreen(existing: w)),
    );
    if (result == true && mounted) {
      ref.invalidate(warningDetailProvider(w.id));
    }
  }

  List<String> _buildPdfCandidates(String warningId, String rawUrl) {
    final value = rawUrl.trim();
    final candidates = <String>[];

    // Primero: usar el endpoint API autenticado para descargar el PDF
    final apiBase = Env.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (apiBase.isNotEmpty) {
      candidates.add('$apiBase/employee-warnings/me/$warningId/pdf');
    }

    // Segundo: si la URL es una URL completa con esquema, usarla directamente
    if (value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      if (uri != null && uri.hasScheme) {
        candidates.add(uri.toString());
      } else {
        // Si es una ruta relativa, intentar construirla con el base URL
        if (apiBase.isNotEmpty) {
          final normalized = value.replaceAll('\\', '/');
          if (normalized.startsWith('/')) {
            candidates.add('$apiBase$normalized');
          } else {
            candidates.add('$apiBase/$normalized');
          }
        }
      }
    }

    return candidates.toSet().toList(); // Eliminar duplicados
  }

  Future<void> _openPdfInApp(BuildContext context, String rawUrl, String warningId) async {
    final candidates = _buildPdfCandidates(warningId, rawUrl);
    if (candidates.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WarningPdfViewerScreen(candidateUrls: candidates),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _InfoPanel({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) => _Container(
        title: title,
        child: Column(
          children: rows
              .map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          r.$1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      Expanded(child: Text(r.$2, style: const TextStyle(fontSize: 12))),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      );
}

class _TextPanel extends StatelessWidget {
  final String title;
  final String text;
  const _TextPanel({required this.title, required this.text});

  @override
  Widget build(BuildContext context) => _Container(
        title: title,
        child: Text(
          text.trim().isEmpty ? 'No registrado' : text.trim(),
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
      );
}

class _PdfPanel extends StatelessWidget {
  final EmployeeWarning warning;
  final String warningId;
  final ValueChanged<String> onOpenInApp;
  const _PdfPanel({required this.warning, required this.warningId, required this.onOpenInApp});

  @override
  Widget build(BuildContext context) => _Container(
        title: 'Documento PDF',
        child: Column(
          children: [
            if (warning.pdfUrl != null)
              _PdfButton(label: 'PDF principal', url: warning.pdfUrl!, onOpenInApp: onOpenInApp),
            if (warning.signedPdfUrl != null)
              _PdfButton(
                label: 'PDF historico firmado',
                url: warning.signedPdfUrl!,
                onOpenInApp: onOpenInApp,
              ),
          ],
        ),
      );
}

class _PdfButton extends StatelessWidget {
  final String label;
  final String url;
  final ValueChanged<String> onOpenInApp;
  const _PdfButton({required this.label, required this.url, required this.onOpenInApp});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onOpenInApp(url),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: Text(label),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: const Icon(Icons.open_in_new, size: 16),
            ),
          ],
        ),
      );
}

class _Container extends StatelessWidget {
  final String title;
  final Widget child;
  const _Container({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _WarningPdfViewerScreen extends StatefulWidget {
  final List<String> candidateUrls;
  const _WarningPdfViewerScreen({required this.candidateUrls});

  @override
  State<_WarningPdfViewerScreen> createState() => _WarningPdfViewerScreenState();
}

class _WarningPdfViewerScreenState extends State<_WarningPdfViewerScreen> {
  int _index = 0;

  String get _currentUrl => widget.candidateUrls[_index];

  void _onLoadFailed(PdfDocumentLoadFailedDetails details) {
    if (_index + 1 < widget.candidateUrls.length) {
      setState(() => _index += 1);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudo cargar el PDF: ${details.description}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documento PDF'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
      ),
      body: SfPdfViewer.network(
        _currentUrl,
        onDocumentLoadFailed: _onLoadFailed,
      ),
    );
  }
}
