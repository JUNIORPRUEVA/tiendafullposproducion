import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:signature/signature.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/models/user_model.dart';
import '../../modules/nomina/data/nomina_repository.dart';
import 'data/users_repository.dart';
import 'utils/work_contract_pdf_service.dart';

class WorkContractScreen extends ConsumerStatefulWidget {
  const WorkContractScreen({super.key});

  @override
  ConsumerState<WorkContractScreen> createState() => _WorkContractScreenState();
}

class _WorkContractScreenState extends ConsumerState<WorkContractScreen> {
  static const String _workContractVersion = '2026-03-07';

  late final SignatureController _signatureCtrl;

  late final Future<_ContractPdfState> _pdfFuture;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _signatureCtrl = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    _pdfFuture = _buildPdf();
  }

  @override
  void dispose() {
    _signatureCtrl.dispose();
    super.dispose();
  }

  Future<_ContractPdfState> _buildPdf() async {
    final auth = ref.read(authStateProvider);
    final user = auth.user;
    if (user == null) {
      throw StateError('Usuario no autenticado');
    }

    final settingsRepo = ref.read(companySettingsRepositoryProvider);
    final nominaRepo = ref.read(nominaRepositoryProvider);

    final company = await settingsRepo.getSettings();

    String? salario;
    String? periodicidadPago;

    try {
      final history = await nominaRepo.listMyPayrollHistory();
      final latest = history.isEmpty
          ? null
          : history.reduce((a, b) => a.periodEnd.isAfter(b.periodEnd) ? a : b);
      final baseSalary = latest?.baseSalary;
      if (baseSalary != null && baseSalary > 0) {
        final fmt = NumberFormat.currency(symbol: 'RD\$', decimalDigits: 2);
        salario = fmt.format(baseSalary);

        // La nómina del sistema suele ser por período (típicamente quincenal),
        // pero esto puede variar. Se deja como fallback si no se define otra regla.
        periodicidadPago = 'Quincenal';
      }
    } catch (_) {
      // Si nómina falla, dejamos el salario en blanco.
    }

    final bytes = await buildWorkContractPdf(
      employee: user,
      company: company,
      salario: salario,
      moneda: 'DOP',
      periodicidadPago: periodicidadPago,
      metodoPago: 'Transferencia',
    );

    final safeName = user.nombreCompleto.trim().isEmpty
        ? 'empleado'
        : user.nombreCompleto.trim().replaceAll(RegExp(r'\s+'), '_');
    final dateFmt = DateFormat('yyyyMMdd');
    final fileName =
        'contrato_${safeName}_${dateFmt.format(DateTime.now())}.pdf';

    return _ContractPdfState(bytes: bytes, fileName: fileName, employee: user);
  }

  Future<void> _signNow(UserModel user) async {
    if (_submitting) return;

    if (_signatureCtrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes firmar antes de continuar')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final png = await _signatureCtrl.toPngBytes();
      if (png == null || png.isEmpty) {
        throw StateError('No se pudo exportar la firma');
      }

      final repo = ref.read(usersRepositoryProvider);
      final fileName =
          'firma_contrato_${user.id}_${DateTime.now().millisecondsSinceEpoch}.png';
      final signatureUrl = await repo.uploadUserDocument(
        bytes: png,
        fileName: fileName,
      );

      final updated = await repo.signWorkContract(
        version: _workContractVersion,
        signatureUrl: signatureUrl,
      );

      ref.read(authStateProvider.notifier).setUser(updated);
      _signatureCtrl.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contrato firmado correctamente')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo firmar: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;

    final signedAt = user?.workContractSignedAt;
    final isSigned = signedAt != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Contrato')),
      body: user == null
          ? const Center(child: Text('No hay usuario autenticado'))
          : Column(
              children: [
                Expanded(
                  child: FutureBuilder<_ContractPdfState>(
                    future: _pdfFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        return Center(
                          child: Text(
                            'No se pudo generar el contrato.\n${snapshot.error ?? ''}',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      final data = snapshot.data!;
                      return PdfPreview(
                        pdfFileName: data.fileName,
                        canChangeOrientation: false,
                        canChangePageFormat: false,
                        build: (format) async => data.bytes,
                      );
                    },
                  ),
                ),
                Material(
                  elevation: 6,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.edit_document, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isSigned
                                      ? 'Firmado el ${DateFormat('dd/MM/yyyy HH:mm').format(signedAt)}'
                                      : 'Firma obligatoria',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (user.workContractVersion != null &&
                                  user.workContractVersion!.trim().isNotEmpty)
                                Text(
                                  'v ${user.workContractVersion}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (isSigned)
                            const Text(
                              'Ya has firmado este contrato.',
                              textAlign: TextAlign.left,
                            )
                          else ...[
                            Container(
                              height: 140,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Signature(
                                controller: _signatureCtrl,
                                backgroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _submitting
                                        ? null
                                        : () => _signatureCtrl.clear(),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Borrar'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _submitting
                                        ? null
                                        : () => _signNow(user),
                                    icon: _submitting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.check),
                                    label: Text(
                                      _submitting ? 'Firmando...' : 'Firmar',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ContractPdfState {
  final Uint8List bytes;
  final String fileName;
  final UserModel employee;

  _ContractPdfState({
    required this.bytes,
    required this.fileName,
    required this.employee,
  });
}
