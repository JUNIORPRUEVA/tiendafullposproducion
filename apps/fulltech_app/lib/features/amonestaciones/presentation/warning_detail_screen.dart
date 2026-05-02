import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/env.dart';
import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../application/warnings_controller.dart';
import '../data/employee_warning_model.dart';
import '../data/employee_warnings_repository.dart';
import 'warning_labels.dart';
import 'warning_create_screen.dart';

class WarningDetailScreen extends ConsumerStatefulWidget {
  final String warningId;
  const WarningDetailScreen({super.key, required this.warningId});

  @override
  ConsumerState<WarningDetailScreen> createState() =>
      _WarningDetailScreenState();
}

class _WarningDetailScreenState extends ConsumerState<WarningDetailScreen> {
  bool _actionLoading = false;

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(canAccessAmonestacionesProvider);
    
    // Solo ADMIN puede ver detalles
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle')),
        body: const Center(
          child: Text('Acceso no permitido para este usuario'),
        ),
      );
    }

    final async = ref.watch(warningDetailProvider(widget.warningId));

    return async.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Detalle')),
        body: Center(child: Text('Error: $e')),
      ),
      data: (w) => _buildDetail(context, w),
    );
  }

  Widget _buildDetail(BuildContext context, EmployeeWarning w) {
    final statusColor = WarningLabels.statusColor(w.status);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(w.warningNumber,
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: _buildActions(context, w),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // ── Status / severity header ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                          WarningLabels.category[w.category] ?? w.category,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Pill(
                        label: WarningLabels.status[w.status] ?? w.status,
                        color: statusColor),
                    const SizedBox(height: 4),
                    _Pill(
                      label: WarningLabels.severity[w.severity] ?? w.severity,
                      color: WarningLabels.severityColor(w.severity),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Dates & parties ──
          _InfoPanel(title: 'Información general', rows: [
            ('Número', w.warningNumber),
            ('Fecha del documento', WarningLabels.fmt(w.warningDate)),
            ('Fecha del incidente', WarningLabels.fmt(w.incidentDate)),
            (
              'Empleado',
              w.employeeUser?.nombreCompleto ?? w.employeeUserId
            ),
            if (w.employeeUser?.workContractJobTitle != null)
              ('Cargo', w.employeeUser!.workContractJobTitle!),
            if (w.employeeUser?.cedula != null)
              ('Cédula', w.employeeUser!.cedula!),
            ('Creado por', w.createdByUser?.nombreCompleto ?? '—'),
            ('Creado el', WarningLabels.fmt(w.createdAt)),
          ]),
          const SizedBox(height: 10),

          // ── Description ──
          _TextPanel(title: 'Descripción de los hechos', text: w.description),
          if (w.employeeExplanation != null) ...[
            const SizedBox(height: 10),
            _TextPanel(
                title: 'Descargo del empleado',
                text: w.employeeExplanation!),
          ],
          if (w.legalBasis != null) ...[
            const SizedBox(height: 10),
            _TextPanel(title: 'Base legal', text: w.legalBasis!),
          ],
          if (w.internalRuleReference != null) ...[
            const SizedBox(height: 10),
            _TextPanel(
                title: 'Referencia reglamento',
                text: w.internalRuleReference!),
          ],
          if (w.correctiveAction != null) ...[
            const SizedBox(height: 10),
            _TextPanel(
                title: 'Acción correctiva', text: w.correctiveAction!),
          ],
          if (w.consequenceNote != null) ...[
            const SizedBox(height: 10),
            _TextPanel(title: 'Consecuencias', text: w.consequenceNote!),
          ],

          // ── Evidences ──
          if (w.evidences.isNotEmpty) ...[
            const SizedBox(height: 10),
            _EvidencePanel(evidences: w.evidences),
          ],

          // ── Signature ──
          if (w.signatures.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SignaturePanel(signatures: w.signatures),
          ],

          // ── Annulment ──
          if (w.status == 'ANNULLED') ...[
            const SizedBox(height: 10),
            _AnnulmentPanel(warning: w),
          ],

          // ── PDF actions ──
          if (w.pdfUrl != null || w.signedPdfUrl != null) ...[
            const SizedBox(height: 10),
            _PdfPanel(
              warning: w,
              onOpenInApp: (url) => _openPdfInApp(context, url),
            ),
          ],

          // ── Audit log ──
          if (w.auditLogs.isNotEmpty) ...[
            const SizedBox(height: 10),
            _AuditPanel(logs: w.auditLogs),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context, EmployeeWarning w) {
    final actions = <Widget>[];
    final role = ref.watch(authStateProvider).user?.appRole;
    final isAdmin = role == AppRole.admin;

    if (w.status == 'DRAFT') {
      actions.add(IconButton(
        icon: const Icon(Icons.edit_outlined),
        tooltip: 'Editar',
        onPressed: () => _openEdit(context, w),
      ));
      actions.add(IconButton(
        icon: const Icon(Icons.send_rounded),
        tooltip: 'Enviar para firma',
        onPressed: _actionLoading ? null : () => _submit(context, w),
      ));
      if (isAdmin) {
        actions.add(IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Eliminar amonestación',
          onPressed: _actionLoading ? null : () => _deleteWarning(context, w),
        ));
      }
    }

    if (w.status == 'PENDING_SIGNATURE' ||
        w.status == 'SIGNED' ||
        w.status == 'REFUSED_TO_SIGN') {
      actions.add(IconButton(
        icon: const Icon(Icons.block_rounded),
        tooltip: 'Anular',
        onPressed: _actionLoading ? null : () => _annul(context, w),
      ));
    }

    actions.add(IconButton(
      icon: const Icon(Icons.picture_as_pdf_outlined),
      tooltip: 'Regenerar PDF',
      onPressed: _actionLoading ? null : () => _regeneratePdf(context, w),
    ));

    return actions;
  }

  Future<void> _submit(BuildContext context, EmployeeWarning w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enviar para firma'),
        content: const Text(
            'Se generará el PDF y el empleado podrá firmar desde la app. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Enviar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _actionLoading = true);
    try {
      await ref.read(employeeWarningsRepositoryProvider).submit(w.id);
      ref.invalidate(warningDetailProvider(w.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Enviada para firma'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _annul(BuildContext context, EmployeeWarning w) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Anular amonestación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Indica el motivo de la anulación:'),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'Motivo de anulación',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (reasonCtrl.text.trim().isEmpty) return;

    setState(() => _actionLoading = true);
    try {
      await ref
          .read(employeeWarningsRepositoryProvider)
          .annul(w.id, reasonCtrl.text.trim());
      ref.invalidate(warningDetailProvider(w.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Amonestación anulada'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _regeneratePdf(BuildContext context, EmployeeWarning w) async {
    setState(() => _actionLoading = true);
    try {
      await ref.read(employeeWarningsRepositoryProvider).generatePdf(w.id);
      ref.invalidate(warningDetailProvider(w.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('PDF regenerado'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _deleteWarning(BuildContext context, EmployeeWarning w) async {
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) {
        bool canDelete = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Eliminar amonestación'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vas a eliminar "${w.warningNumber}". Esta acción es irreversible.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Para confirmar, escribe ELIMINAR:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'ELIMINAR',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    final next = value.trim().toUpperCase() == 'ELIMINAR';
                    if (next != canDelete) {
                      setDialogState(() => canDelete = next);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: canDelete
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: const Text('Sí, eliminar'),
              ),
            ],
          ),
        );
      },
    );
    confirmCtrl.dispose();
    if (ok != true) return;

    setState(() => _actionLoading = true);
    try {
      await ref.read(employeeWarningsRepositoryProvider).delete(w.id);
      ref.invalidate(warningsListControllerProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Amonestación eliminada'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  List<String> _buildPdfCandidates(String rawUrl) {
    final value = rawUrl.trim();
    if (value.isEmpty) return const [];

    final out = <String>[];
    final seen = <String>{};
    void addCandidate(String? v) {
      final candidate = (v ?? '').trim();
      if (candidate.isEmpty) return;
      if (seen.add(candidate)) out.add(candidate);
    }

    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      addCandidate(uri.toString());
    } else {
      final normalized = value.replaceAll('\\', '/');
      final baseUrl = Env.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      if (baseUrl.isNotEmpty) {
        if (normalized.startsWith('/')) {
          addCandidate('$baseUrl$normalized');
        } else if (normalized.startsWith('./')) {
          addCandidate('$baseUrl/${normalized.substring(2)}');
        } else {
          addCandidate('$baseUrl/$normalized');
        }
      }
      addCandidate(normalized);
    }

    final baseUri = Uri.tryParse(Env.apiBaseUrl.trim());
    if (baseUri != null) {
      final originals = List<String>.from(out);
      for (final candidate in originals) {
        final cUri = Uri.tryParse(candidate);
        if (cUri == null || !cUri.hasScheme) continue;
        if (cUri.host != baseUri.host) continue;

        final segments = cUri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.isEmpty) continue;
        if (segments.first == 'api') {
          final noApi = cUri.replace(pathSegments: segments.skip(1));
          addCandidate(noApi.toString());
        } else {
          final withApi = cUri.replace(pathSegments: ['api', ...segments]);
          addCandidate(withApi.toString());
        }
      }
    }

    return out;
  }

  Future<void> _openPdfInApp(BuildContext context, String rawUrl) async {
    final candidates = _buildPdfCandidates(rawUrl);
    if (candidates.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No fue posible construir la URL del PDF'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WarningPdfViewerScreen(candidateUrls: candidates),
      ),
    );
  }

  void _openEdit(BuildContext context, EmployeeWarning w) async {
    final result = await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WarningCreateScreen(existing: w),
    ));
    if (result == true && mounted) {
      ref.invalidate(warningDetailProvider(w.id));
    }
  }
}

// ── Panels ────────────────────────────────────────────────────────────────────

class _InfoPanel extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;

  const _InfoPanel({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) => _Container(
        title: title,
        child: Column(
          children: rows
              .map((r) => Padding(
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
                                color: Colors.grey.shade600),
                          ),
                        ),
                        Expanded(
                          child: Text(r.$2,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ))
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
        child: Text(text,
            style: const TextStyle(fontSize: 13, height: 1.5)),
      );
}

class _EvidencePanel extends StatelessWidget {
  final List<EmployeeWarningEvidence> evidences;

  const _EvidencePanel({required this.evidences});

  @override
  Widget build(BuildContext context) => _Container(
        title: 'Evidencias (${evidences.length})',
        child: Column(
          children: evidences
              .map((ev) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.attach_file, size: 18),
                    title: Text(ev.fileName,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(ev.fileType,
                        style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.open_in_new, size: 16),
                      onPressed: () => launchUrl(Uri.parse(ev.fileUrl)),
                    ),
                  ))
              .toList(),
        ),
      );
}

class _SignaturePanel extends StatelessWidget {
  final List<EmployeeWarningSignature> signatures;

  const _SignaturePanel({required this.signatures});

  @override
  Widget build(BuildContext context) {
    final sig = signatures.first;
    final isSigned = sig.signatureType == 'SIGNED';

    return _Container(
      title: isSigned ? 'Firmada por el empleado' : 'Negativa a firmar',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row('Nombre escrito', sig.typedName),
          _Row(
              isSigned ? 'Firmado el' : 'Negativa el',
              WarningLabels.fmt(sig.signedAt)),
          if (sig.comment != null && sig.comment!.isNotEmpty)
            _Row('Comentario', sig.comment!),
        ],
      ),
    );
  }

  Widget _Row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
            ),
            Expanded(
                child: Text(value, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );
}

class _AnnulmentPanel extends StatelessWidget {
  final EmployeeWarning warning;

  const _AnnulmentPanel({required this.warning});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ANULADA',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.red,
                    letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Text(
              'Anulada el ${WarningLabels.fmt(warning.annulledAt)} por '
              '${warning.annulledByUser?.nombreCompleto ?? "—"}',
              style: const TextStyle(fontSize: 12),
            ),
            if (warning.annulmentReason != null) ...[
              const SizedBox(height: 4),
              Text('Motivo: ${warning.annulmentReason}',
                  style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      );
}

class _PdfPanel extends StatelessWidget {
  final EmployeeWarning warning;
  final ValueChanged<String> onOpenInApp;

  const _PdfPanel({required this.warning, required this.onOpenInApp});

  @override
  Widget build(BuildContext context) => _Container(
        title: 'Documentos PDF',
        child: Column(
          children: [
            if (warning.pdfUrl != null)
              _PdfButton(
                label: 'PDF original',
                url: warning.pdfUrl!,
                onOpenInApp: onOpenInApp,
              ),
            if (warning.signedPdfUrl != null)
              _PdfButton(
                label: 'PDF firmado / negativa',
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

  const _PdfButton({
    required this.label,
    required this.url,
    required this.onOpenInApp,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onOpenInApp(url),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: Text(label, style: const TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 38),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Abrir externo',
              child: OutlinedButton(
                onPressed: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(42, 38),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.open_in_new, size: 16),
              ),
            ),
          ],
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Intentando ruta alternativa para abrir el PDF...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No se pudo cargar el PDF: ${details.description}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documento PDF'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Abrir externo',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(
              Uri.parse(_currentUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: SfPdfViewer.network(
        _currentUrl,
        key: ValueKey(_currentUrl),
        canShowPaginationDialog: true,
        enableDoubleTapZooming: true,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        onDocumentLoadFailed: _onLoadFailed,
      ),
    );
  }
}

class _AuditPanel extends StatelessWidget {
  final List<EmployeeWarningAuditLog> logs;

  const _AuditPanel({required this.logs});

  static const Map<String, String> _actionLabels = {
    'created': 'Creada',
    'updated': 'Actualizada',
    'submitted_for_signature': 'Enviada para firma',
    'signed': 'Firmada',
    'refused_to_sign': 'Negativa a firmar',
    'annulled': 'Anulada',
    'pdf_generated': 'PDF generado',
    'evidence_uploaded': 'Evidencia subida',
  };

  @override
  Widget build(BuildContext context) => _Container(
        title: 'Auditoría',
        child: Column(
          children: logs.reversed
              .take(20)
              .map(
                (log) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle, size: 7,
                          color: Color(0xFF1a1a2e)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _actionLabels[log.action] ?? log.action,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${log.actorUser?.nombreCompleto ?? "Sistema"} · '
                              '${WarningLabels.fmt(log.createdAt)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      );
}

class _Container extends StatelessWidget {
  final String title;
  final Widget child;

  const _Container({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1a1a2e),
                    letterSpacing: 0.5)),
            const Divider(height: 12),
            child,
          ],
        ),
      );
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
