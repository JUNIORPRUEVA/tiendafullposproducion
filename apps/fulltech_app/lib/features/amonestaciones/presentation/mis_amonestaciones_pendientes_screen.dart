import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../core/auth/auth_repository.dart';
import '../application/warnings_controller.dart';
import '../data/employee_warning_model.dart';
import '../data/employee_warnings_repository.dart';
import 'warning_labels.dart';

/// Screen shown to the authenticated employee listing their pending warnings.
class MisAmonestacionesPendientesScreen extends ConsumerWidget {
  const MisAmonestacionesPendientesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myPendingWarningsProvider);
    final baseUrl = ref.watch(dioProvider).options.baseUrl;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Pendientes de firma',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(myPendingWarningsProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 42),
              const SizedBox(height: 8),
              Text('$e', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: () => ref.invalidate(myPendingWarningsProvider),
                  child: const Text('Reintentar')),
            ],
          ),
        ),
        data: (list) => list.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 52, color: Colors.green),
                    SizedBox(height: 8),
                    Text('No tienes amonestaciones pendientes',
                        style: TextStyle(color: Colors.grey, fontSize: 15)),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(myPendingWarningsProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: list.length,
                  itemBuilder: (context, i) =>
                      _PendingCard(warning: list[i], baseUrl: baseUrl),
                ),
              ),
      ),
    );
  }
}

class _PendingCard extends StatefulWidget {
  final EmployeeWarning warning;
  final String baseUrl;

  const _PendingCard({required this.warning, required this.baseUrl});

  @override
  State<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends State<_PendingCard> {
  bool _expanded = false;

  String? _resolvePdfUrl(String rawUrl) {
    final value = rawUrl.trim();
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.hasScheme) return uri.toString();

    final base = widget.baseUrl.trim();
    if (base.isEmpty) return null;
    final baseUri = Uri.tryParse(base);
    if (baseUri == null) return null;
    return baseUri.resolveUri(uri).toString();
  }

  Future<void> _openPdf(BuildContext context, String rawUrl) async {
    final resolved = _resolvePdfUrl(rawUrl);
    if (resolved == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo construir la URL del PDF'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PendingWarningPdfViewerScreen(pdfUrl: resolved),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.warning;
    final severityColor = WarningLabels.severityColor(w.severity);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: severityColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(w.warningNumber,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      _Pill(
                          label: WarningLabels.severity[w.severity] ??
                              w.severity,
                          color: severityColor),
                      Icon(
                          _expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 20,
                          color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(w.title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                      WarningLabels.category[w.category] ?? w.category,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(height: 4),
                  Text('Emitida el ${WarningLabels.fmt(w.warningDate)}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Descripción',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1a1a2e))),
                  const SizedBox(height: 4),
                  Text(w.description,
                      style:
                          const TextStyle(fontSize: 13, height: 1.5)),
                  if (w.legalBasis != null) ...[
                    const SizedBox(height: 10),
                    const Text('Base legal',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1a1a2e))),
                    const SizedBox(height: 4),
                    Text(w.legalBasis!,
                        style: const TextStyle(fontSize: 13)),
                  ],
                  if (w.correctiveAction != null) ...[
                    const SizedBox(height: 10),
                    const Text('Acción correctiva',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1a1a2e))),
                    const SizedBox(height: 4),
                    Text(w.correctiveAction!,
                        style: const TextStyle(fontSize: 13)),
                  ],
                  if (w.pdfUrl != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _openPdf(context, w.pdfUrl!),
                      icon: const Icon(Icons.picture_as_pdf_outlined,
                          size: 16),
                      label:
                          const Text('Ver PDF', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 38)),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            _SignatureActions(warning: w),
          ],
        ],
      ),
    );
  }
}

class _PendingWarningPdfViewerScreen extends StatelessWidget {
  final String pdfUrl;

  const _PendingWarningPdfViewerScreen({required this.pdfUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documento PDF'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
      ),
      body: SfPdfViewer.network(
        pdfUrl,
        canShowPaginationDialog: true,
        enableDoubleTapZooming: true,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        onDocumentLoadFailed: (details) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo cargar el PDF: ${details.description}'),
              backgroundColor: Colors.red,
            ),
          );
        },
      ),
    );
  }
}

class _SignatureActions extends ConsumerStatefulWidget {
  final EmployeeWarning warning;
  const _SignatureActions({required this.warning});

  @override
  ConsumerState<_SignatureActions> createState() =>
      _SignatureActionsState();
}

class _SignatureActionsState extends ConsumerState<_SignatureActions> {
  bool _loading = false;

  Future<void> _sign() async {
    final nameCtrl = TextEditingController();
    final commentCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Firmar amonestación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Al firmar confirmas haber recibido y leído esta amonestación. '
              'Esto no implica que estés de acuerdo con su contenido.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tu nombre completo (firma)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: commentCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Comentario (opcional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1a1a2e),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Firmar'),
          ),
        ],
      ),
    );

    if (confirmed != true || nameCtrl.text.trim().isEmpty) return;

    setState(() => _loading = true);
    try {
      await ref.read(employeeWarningsRepositoryProvider).sign(
            widget.warning.id,
            typedName: nameCtrl.text.trim(),
            comment: commentCtrl.text.trim().isEmpty
                ? null
                : commentCtrl.text.trim(),
          );
      ref.invalidate(myPendingWarningsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Amonestación firmada correctamente'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al firmar: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refuse() async {
    final nameCtrl = TextEditingController();
    final commentCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Negarse a firmar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tu negativa a firmar quedará registrada junto a tu nombre y motivo.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tu nombre completo',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: commentCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo de la negativa (requerido)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Registrar negativa'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (nameCtrl.text.trim().isEmpty || commentCtrl.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nombre y motivo son requeridos'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(employeeWarningsRepositoryProvider).refuse(
            widget.warning.id,
            typedName: nameCtrl.text.trim(),
            comment: commentCtrl.text.trim(),
          );
      ref.invalidate(myPendingWarningsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Negativa registrada'),
              backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _refuse,
              icon: const Icon(Icons.close, size: 16, color: Colors.red),
              label: const Text('No firmar',
                  style: TextStyle(color: Colors.red, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _sign,
              icon: _loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check, size: 16),
              label: const Text('Firmar',
                  style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1a1a2e),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
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
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color)),
      );
}
