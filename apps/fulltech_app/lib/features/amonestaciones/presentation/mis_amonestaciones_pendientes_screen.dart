import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:signature/signature.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../core/auth/auth_provider.dart';
import '../application/warnings_controller.dart';
import '../data/employee_warning_model.dart';
import '../data/employee_warnings_repository.dart';
import 'warning_labels.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Screen
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class MisAmonestacionesPendientesScreen extends ConsumerWidget {
  const MisAmonestacionesPendientesScreen({super.key});

  double _maxContentWidth(double width) {
    if (width >= 1500) return 860;
    if (width >= 1200) return 800;
    if (width >= 980) return 760;
    return double.infinity;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myPendingWarningsProvider);
    final width = MediaQuery.sizeOf(context).width;
    final maxContentWidth = _maxContentWidth(width);
    final listHorizontalPadding = width >= 980 ? 20.0 : 12.0;

    return Scaffold(
      backgroundColor: const Color(0xFFEEF1F8),
      appBar: AppBar(
        title: const Text(
          'Pendientes de firma',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(myPendingWarningsProvider),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF6F8FD), Color(0xFFEEF1F8)],
          ),
        ),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        '$e',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => ref.invalidate(myPendingWarningsProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: const _EmptyState(),
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(myPendingWarningsProvider),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(listHorizontalPadding, 18, listHorizontalPadding, 96),
                    itemCount: list.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return _PendingSummaryHeader(count: list.length);
                      }
                      return _WarningCard(warning: list[i - 1]);
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PendingSummaryHeader extends StatelessWidget {
  final int count;
  const _PendingSummaryHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.assignment_late_outlined, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count == 1
                  ? 'Tienes 1 amonestacion pendiente de firma'
                  : 'Tienes $count amonestaciones pendientes de firma',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.chevron_right_rounded, color: Colors.white70),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Empty state
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline, size: 44, color: Colors.green),
            ),
            const SizedBox(height: 16),
            const Text(
              'Todo en orden',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1a1a2e)),
            ),
            const SizedBox(height: 6),
            const Text(
              'No tienes amonestaciones pendientes de firma.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Warning card â€” full text view + PDF button + action buttons
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _WarningCard extends ConsumerStatefulWidget {
  final EmployeeWarning warning;
  const _WarningCard({required this.warning});

  @override
  ConsumerState<_WarningCard> createState() => _WarningCardState();
}

class _WarningCardState extends ConsumerState<_WarningCard> {
  bool _loading = false;

  EmployeeWarning get w => widget.warning;

  Color get _severityColor => WarningLabels.severityColor(w.severity);

  // â”€â”€ View PDF â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _viewPdf() async {
    setState(() => _loading = true);
    try {
      final bytes = await ref
          .read(employeeWarningsRepositoryProvider)
          .getMyWarningPdfBytes(id: w.id, rawPdfUrl: w.pdfUrl);

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PdfBytesViewerScreen(
            bytes: bytes,
            filename: 'amonestacion-${w.warningNumber}.pdf',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cargar el PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // â”€â”€ Sign â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _sign() async {
    final authUser = ref.read(authStateProvider).user;
    final fixedName = (authUser?.nombreCompleto ?? '').trim().toUpperCase();
    final signatureResult = await Navigator.of(context).push<_SignatureCaptureResult>(
      MaterialPageRoute(
        builder: (_) => _SignatureCaptureScreen(initialTypedName: fixedName),
      ),
    );

    if (signatureResult == null) return;

    setState(() => _loading = true);
    try {
      await ref.read(employeeWarningsRepositoryProvider).sign(
            w.id,
            typedName: signatureResult.typedName,
            comment: signatureResult.comment,
            signatureImageUrl: signatureResult.signatureDataUrl,
          );
      ref.invalidate(myPendingWarningsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('âœ“ AmonestaciÃ³n firmada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al firmar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // â”€â”€ Refuse â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _refuse() async {
    final nameCtrl = TextEditingController();
    final commentCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
            SizedBox(width: 8),
            Text('Negarse a firmar'),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'Tu negativa quedarÃ¡ registrada con tu nombre y motivo. '
                  'Este acto tambiÃ©n queda documentado.',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Tu nombre completo',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.person_outline, size: 18),
                ),
              ),
              const SizedBox(height: 10),
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Registrar negativa'),
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
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(employeeWarningsRepositoryProvider).refuse(
            w.id,
            typedName: nameCtrl.text.trim(),
            comment: commentCtrl.text.trim(),
          );
      ref.invalidate(myPendingWarningsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Negativa registrada correctamente'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shadowColor: _severityColor.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _severityColor.withValues(alpha: 0.35), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // â”€â”€ Company header â”€â”€
          _CompanyHeader(severityColor: _severityColor),

          // â”€â”€ Warning metadata â”€â”€
          _WarningMetaSection(warning: w),

          // â”€â”€ Full text content â”€â”€
          _WarningTextSection(warning: w),

          // â”€â”€ PDF button â”€â”€
          if (w.pdfUrl != null && w.pdfUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _viewPdf,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFe63946)),
                label: const Text(
                  'Ver carta completa (PDF)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 42),
                  side: const BorderSide(color: Color(0xFFe63946)),
                  foregroundColor: const Color(0xFFe63946),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),

          const Divider(height: 1),

          // â”€â”€ Action buttons â”€â”€
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _refuse,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('No firmar', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _sign,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.draw_outlined, size: 16),
                    label: const Text(
                      'Firmar',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1a1a2e),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Company header widget
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _CompanyHeader extends StatelessWidget {
  final Color severityColor;
  const _CompanyHeader({required this.severityColor});

  static const _companyName = 'FULLTECH, SRL';
  static const _department = 'Recursos Humanos';
  static const _docType = 'AMONESTACIÃ“N LABORAL';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Center(
              child: Image.asset(
                'assets/logoprincipal.png',
                width: 28,
                height: 28,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.business,
                  color: Colors.white70,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  _companyName,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_department Â· $_docType',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: severityColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'PENDIENTE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Warning metadata section
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _WarningMetaSection extends StatelessWidget {
  final EmployeeWarning warning;
  const _WarningMetaSection({required this.warning});

  @override
  Widget build(BuildContext context) {
    final w = warning;
    final severityColor = WarningLabels.severityColor(w.severity);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  w.warningNumber,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Color(0xFF1a1a2e),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              _Pill(
                label: WarningLabels.severity[w.severity] ?? w.severity,
                color: severityColor,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            w.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1a1a2e),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _InfoChip(
                icon: Icons.category_outlined,
                label: WarningLabels.category[w.category] ?? w.category,
              ),
              _InfoChip(
                icon: Icons.calendar_today_outlined,
                label: 'Emitida: ${WarningLabels.fmt(w.warningDate)}',
              ),
              _InfoChip(
                icon: Icons.event_outlined,
                label: 'Incidente: ${WarningLabels.fmt(w.incidentDate)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Full text content section
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _WarningTextSection extends StatelessWidget {
  final EmployeeWarning warning;
  const _WarningTextSection({required this.warning});

  @override
  Widget build(BuildContext context) {
    final w = warning;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          _Section(
            title: 'DescripciÃ³n de los hechos',
            icon: Icons.description_outlined,
            content: w.description,
          ),
          if (w.legalBasis != null && w.legalBasis!.isNotEmpty)
            _Section(
              title: 'Base legal',
              icon: Icons.gavel_outlined,
              content: w.legalBasis!,
            ),
          if (w.internalRuleReference != null && w.internalRuleReference!.isNotEmpty)
            _Section(
              title: 'Referencia reglamento interno',
              icon: Icons.menu_book_outlined,
              content: w.internalRuleReference!,
            ),
          if (w.correctiveAction != null && w.correctiveAction!.isNotEmpty)
            _Section(
              title: 'AcciÃ³n correctiva requerida',
              icon: Icons.build_outlined,
              content: w.correctiveAction!,
              highlightColor: const Color(0xFFFFF3CD),
            ),
          if (w.consequenceNote != null && w.consequenceNote!.isNotEmpty)
            _Section(
              title: 'Consecuencias',
              icon: Icons.warning_amber_outlined,
              content: w.consequenceNote!,
              highlightColor: const Color(0xFFFFEBEB),
            ),
          if (w.employeeExplanation != null && w.employeeExplanation!.isNotEmpty)
            _Section(
              title: 'Descargo del empleado',
              icon: Icons.chat_bubble_outline,
              content: w.employeeExplanation!,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final String content;
  final Color? highlightColor;

  const _Section({
    required this.title,
    required this.icon,
    required this.content,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: const Color(0xFF1a1a2e)),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1a1a2e),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: highlightColor ?? const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
            ),
            child: Text(
              content,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: Color(0xFF2D2D2D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// PDF bytes viewer screen
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SignatureCaptureResult {
  final String typedName;
  final String? comment;
  final String signatureDataUrl;

  const _SignatureCaptureResult({
    required this.typedName,
    required this.comment,
    required this.signatureDataUrl,
  });
}

class _SignatureCaptureScreen extends StatefulWidget {
  final String initialTypedName;

  const _SignatureCaptureScreen({required this.initialTypedName});

  @override
  State<_SignatureCaptureScreen> createState() => _SignatureCaptureScreenState();
}

class _SignatureCaptureScreenState extends State<_SignatureCaptureScreen> {
  late final SignatureController _signatureCtrl;
  bool _saving = false;

  bool get _isMobile => MediaQuery.sizeOf(context).width < 900;
  bool get _supportsOrientationLock {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    _signatureCtrl = SignatureController(
      penStrokeWidth: 2.6,
      penColor: const Color(0xFF121212),
      exportBackgroundColor: Colors.white,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isMobile && _supportsOrientationLock) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    });
  }

  @override
  void dispose() {
    _signatureCtrl.dispose();
    if (_supportsOrientationLock) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.initialTypedName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontro el nombre del usuario autenticado')),
      );
      return;
    }
    if (_signatureCtrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes dibujar tu firma en el recuadro')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final pngBytes = await _signatureCtrl.toPngBytes(
        height: _isMobile ? 700 : 820,
        width: _isMobile ? 1800 : 2400,
      );
      if (!mounted || pngBytes == null || pngBytes.isEmpty) return;

      final base64 = base64Encode(pngBytes);
      final signatureDataUrl = 'data:image/png;base64,$base64';

      Navigator.of(context).pop(
        _SignatureCaptureResult(
          typedName: widget.initialTypedName,
          comment: null,
          signatureDataUrl: signatureDataUrl,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final canvasHeight = _isMobile ? 280.0 : 420.0;
    final maxContentWidth = _isMobile ? width : 1100.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F4FA),
      appBar: AppBar(
        title: const Text('Firma de recibido'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4DB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE9C98B)),
                  ),
                  child: Text(
                    _isMobile
                        ? 'Modo movil: pantalla horizontal para una firma comoda y amplia.'
                        : 'Modo escritorio: area de firma ampliada para mayor precision.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A4E13),
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo (usuario autenticado)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  child: Text(
                    widget.initialTypedName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFCED6E0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.draw_rounded, size: 18, color: Color(0xFF1a1a2e)),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Dibuja tu firma dentro del recuadro',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _signatureCtrl.clear,
                            icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                            label: const Text('Limpiar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: canvasHeight,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFB0BEC5), width: 1.2),
                        ),
                        child: Signature(
                          controller: _signatureCtrl,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('Guardar firma y continuar'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: const Color(0xFF1a1a2e),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PdfBytesViewerScreen extends StatelessWidget {
  final Uint8List bytes;
  final String filename;

  const _PdfBytesViewerScreen({required this.bytes, required this.filename});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(filename, style: const TextStyle(fontSize: 15)),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SfPdfViewer.memory(
        bytes,
        canShowPaginationDialog: true,
        enableDoubleTapZooming: true,
        canShowScrollHead: true,
        canShowScrollStatus: true,
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Helpers
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F8),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ],
        ),
      );
}
