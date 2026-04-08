import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/role_permissions.dart';
import '../../core/errors/api_exception.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'data/contabilidad_repository.dart';
import 'deposit_bank_catalog.dart';
import 'models/deposit_order_model.dart';
import 'utils/deposit_order_pdf_service.dart';

class DepositosBancariosScreen extends ConsumerStatefulWidget {
  const DepositosBancariosScreen({super.key});

  @override
  ConsumerState<DepositosBancariosScreen> createState() =>
      _DepositosBancariosScreenState();
}

class _DepositosBancariosScreenState
    extends ConsumerState<DepositosBancariosScreen> {
  final _money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
  final _dateFmt = DateFormat('dd/MM/yyyy');
  bool _loading = true;
  String? _error;
  List<DepositOrderModel> _orders = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(contabilidadRepositoryProvider).listDepositOrders();
      if (!mounted) return;
      setState(() {
        _orders = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los depósitos: $e';
        _loading = false;
      });
    }
  }

  bool get _isAdmin => ref.read(authStateProvider).user?.appRole.isAdmin ?? false;

  Future<void> _showSnack(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openEditor({DepositOrderModel? initial}) async {
    final createdAt = initial?.windowFrom ?? DateTime.now();
    final dateCtrl = TextEditingController(text: _dateFmt.format(createdAt));
    final collaboratorCtrl = TextEditingController(text: initial?.collaboratorName ?? '');
    final amountCtrl = TextEditingController(
      text: initial == null ? '' : initial.depositTotal.toStringAsFixed(2),
    );
    final reserveCtrl = TextEditingController(
      text: initial == null ? '0' : initial.reserveAmount.toStringAsFixed(2),
    );
    final availableCtrl = TextEditingController(
      text: initial == null ? '' : initial.totalAvailableCash.toStringAsFixed(2),
    );
    final noteCtrl = TextEditingController(text: initial?.note ?? '');

    var depositDate = createdAt;
    var selectedBank = _resolveBank(initial?.bankName);
    var selectedAccount = _resolveAccount(selectedBank, initial?.bankAccount);
    var saving = false;
    String? localError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: depositDate,
                firstDate: DateTime(2024),
                lastDate: DateTime(2100),
              );
              if (picked == null) return;
              setDialogState(() {
                depositDate = picked;
                dateCtrl.text = _dateFmt.format(picked);
              });
            }

            Future<void> submit() async {
              final amount = double.tryParse(amountCtrl.text.trim().replaceAll(',', '.'));
              final reserve = double.tryParse(reserveCtrl.text.trim().replaceAll(',', '.')) ?? 0;
              final available = double.tryParse(availableCtrl.text.trim().replaceAll(',', '.'));
              if (selectedBank == null) {
                setDialogState(() => localError = 'Debes seleccionar el banco');
                return;
              }
              if (selectedAccount == null) {
                setDialogState(() => localError = 'Debes seleccionar la cuenta');
                return;
              }
              if (amount == null || amount <= 0) {
                setDialogState(() => localError = 'Indica un monto válido');
                return;
              }
              if (available == null || available < amount) {
                setDialogState(() => localError = 'El efectivo disponible debe cubrir el depósito');
                return;
              }

              setDialogState(() {
                saving = true;
                localError = null;
              });

              try {
                final repo = ref.read(contabilidadRepositoryProvider);
                if (initial == null) {
                  await repo.createDepositOrder(
                    windowFrom: depositDate,
                    windowTo: depositDate,
                    bankName: selectedBank!.label,
                    bankAccount: selectedAccount!.label,
                    collaboratorName: collaboratorCtrl.text,
                    note: noteCtrl.text,
                    reserveAmount: reserve,
                    totalAvailableCash: available,
                    depositTotal: amount,
                    closesCountByType: const {'GENERAL': 1},
                    depositByType: {'GENERAL': amount},
                    accountByType: {'GENERAL': selectedAccount!.label},
                  );
                } else {
                  await repo.updateDepositOrder(
                    id: initial.id,
                    windowFrom: depositDate,
                    windowTo: depositDate,
                    bankName: selectedBank!.label,
                    bankAccount: selectedAccount!.label,
                    collaboratorName: collaboratorCtrl.text,
                    note: noteCtrl.text,
                    reserveAmount: reserve,
                    totalAvailableCash: available,
                    depositTotal: amount,
                    closesCountByType: const {'GENERAL': 1},
                    depositByType: {'GENERAL': amount},
                    accountByType: {'GENERAL': selectedAccount!.label},
                  );
                }
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                await _load();
                await _showSnack(initial == null
                    ? 'Depósito bancario creado.'
                    : 'Depósito bancario actualizado.');
              } catch (e) {
                setDialogState(() {
                  saving = false;
                  localError = e is ApiException ? e.message : 'No se pudo guardar el depósito';
                });
              }
            }

            final accounts = selectedBank?.accounts ?? const <DepositBankAccountOption>[];

            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        initial == null ? 'Nuevo depósito bancario' : 'Editar depósito bancario',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: dateCtrl,
                        readOnly: true,
                        onTap: pickDate,
                        decoration: const InputDecoration(
                          labelText: 'Fecha del depósito',
                          suffixIcon: Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<DepositBankOption>(
                        value: selectedBank,
                        decoration: const InputDecoration(labelText: 'Banco'),
                        items: depositBankCatalog
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedBank = value;
                            selectedAccount = value?.accounts.isNotEmpty == true
                                ? value!.accounts.first
                                : null;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<DepositBankAccountOption>(
                        value: selectedAccount,
                        decoration: const InputDecoration(labelText: 'Cuenta destino'),
                        items: accounts
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item.label),
                              ),
                            )
                            .toList(),
                        onChanged: accounts.isEmpty
                            ? null
                            : (value) => setDialogState(() => selectedAccount = value),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: collaboratorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Colaborador que deposita',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Monto a depositar'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: availableCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Efectivo disponible'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: reserveCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Fondo a dejar en caja'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: noteCtrl,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Nota'),
                      ),
                      if (localError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          localError!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: saving ? null : submit,
                            icon: saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(initial == null ? 'Crear' : 'Guardar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  DepositBankOption? _resolveBank(String? bankName) {
    final normalized = (bankName ?? '').trim().toLowerCase();
    for (final item in depositBankCatalog) {
      if (item.label.toLowerCase() == normalized) return item;
    }
    return depositBankCatalog.isEmpty ? null : depositBankCatalog.first;
  }

  DepositBankAccountOption? _resolveAccount(
    DepositBankOption? bank,
    String? accountLabel,
  ) {
    if (bank == null) return null;
    final normalized = (accountLabel ?? '').trim().toLowerCase();
    for (final item in bank.accounts) {
      if (item.label.toLowerCase() == normalized) return item;
    }
    return bank.accounts.isEmpty ? null : bank.accounts.first;
  }

  Future<void> _confirmDelete(DepositOrderModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar depósito'),
        content: Text('Se eliminará el depósito de ${_money.format(item.depositTotal)}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref.read(contabilidadRepositoryProvider).deleteDepositOrder(item.id);
      await _load();
      await _showSnack('Depósito eliminado.');
    } catch (e) {
      await _showSnack('No se pudo eliminar el depósito: $e');
    }
  }

  Future<void> _uploadVoucher(DepositOrderModel item) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    try {
      await ref
          .read(contabilidadRepositoryProvider)
          .uploadDepositVoucher(id: item.id, file: result.files.first);
      await _load();
      await _showSnack('Voucher cargado correctamente.');
    } catch (e) {
      await _showSnack('No se pudo cargar el voucher: $e');
    }
  }

  Future<void> _openVoucher(DepositOrderModel item) async {
    final rawUrl = item.voucherUrl;
    if (rawUrl == null || rawUrl.trim().isEmpty) return;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) {
      await _showSnack('El voucher no tiene una URL válida.');
      return;
    }
    await safeOpenUrl(context, uri, copiedMessage: 'No se pudo abrir el voucher. Link copiado.');
  }

  Future<void> _openPdfPreview(DepositOrderModel item) async {
    final pdfBytes = await buildDepositOrderPdf(
      data: DepositOrderPdfData(
        generatedAt: DateTime.now(),
        windowFrom: item.windowFrom,
        windowTo: item.windowTo,
        bankName: item.bankName,
        collaboratorName: item.collaboratorName,
        note: item.note,
        reserveInCash: item.reserveAmount,
        totalAvailableCash: item.totalAvailableCash,
        depositTotal: item.depositTotal,
        closesCountByType: item.closesCountByType,
        depositByType: item.depositByType,
        accountByType: item.accountByType,
      ),
    );
    if (!mounted) return;
    final filename = 'deposito_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 980,
          height: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Carta PDF del depósito',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Printing.sharePdf(bytes: pdfBytes, filename: filename),
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
                  build: (_) async => pdfBytes,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(DepositOrderStatus status) {
    switch (status) {
      case DepositOrderStatus.executed:
        return const Color(0xFF0F766E);
      case DepositOrderStatus.cancelled:
        return const Color(0xFFB91C1C);
      case DepositOrderStatus.pending:
        return const Color(0xFFB45309);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canUseModule = canAccessContabilidadByRole(user?.role);

    if (!canUseModule) {
      return Scaffold(
        appBar: const CustomAppBar(
          title: 'Depósitos bancarios',
          showLogo: false,
          showDepartmentLabel: false,
        ),
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Este módulo está disponible solo para usuarios autorizados.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Depósitos bancarios',
        showLogo: false,
        showDepartmentLabel: false,
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DepositsHeader(
              total: _orders.length,
              pending: _orders.where((item) => item.status == DepositOrderStatus.pending).length,
              executed: _orders.where((item) => item.status == DepositOrderStatus.executed).length,
              onCreate: () => _openEditor(),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              )
            else if (_orders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Todavía no hay depósitos registrados.'),
              )
            else
              ..._orders.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DepositOrderTile(
                    item: item,
                    money: _money,
                    dateFmt: _dateFmt,
                    statusColor: _statusColor(item.status),
                    isAdmin: _isAdmin,
                    onPdf: () => _openPdfPreview(item),
                    onVoucher: item.hasVoucher ? () => _openVoucher(item) : null,
                    onUploadVoucher: _isAdmin ? () => _uploadVoucher(item) : null,
                    onEdit: _isAdmin ? () => _openEditor(initial: item) : null,
                    onDelete: _isAdmin ? () => _confirmDelete(item) : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DepositsHeader extends StatelessWidget {
  const _DepositsHeader({
    required this.total,
    required this.pending,
    required this.executed,
    required this.onCreate,
  });

  final int total;
  final int pending;
  final int executed;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E0E8)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Gestión de depósitos bancarios',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          _HeaderChip(label: 'Total: $total'),
          _HeaderChip(label: 'Pendientes: $pending'),
          _HeaderChip(label: 'Ejecutados: $executed'),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Nuevo depósito'),
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD9E0E8)),
      ),
      child: Text(label),
    );
  }
}

class _DepositOrderTile extends StatelessWidget {
  const _DepositOrderTile({
    required this.item,
    required this.money,
    required this.dateFmt,
    required this.statusColor,
    required this.isAdmin,
    required this.onPdf,
    this.onVoucher,
    this.onUploadVoucher,
    this.onEdit,
    this.onDelete,
  });

  final DepositOrderModel item;
  final NumberFormat money;
  final DateFormat dateFmt;
  final Color statusColor;
  final bool isAdmin;
  final VoidCallback onPdf;
  final VoidCallback? onVoucher;
  final VoidCallback? onUploadVoucher;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD9E0E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                money.format(item.depositTotal),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.status.label,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w800),
                ),
              ),
              Text('${item.bankName} · ${item.bankAccount ?? 'Cuenta sin indicar'}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Fecha: ${dateFmt.format(item.windowFrom)} · Colaborador: ${item.collaboratorName ?? 'No indicado'} · Disponible: ${money.format(item.totalAvailableCash)} · Fondo: ${money.format(item.reserveAmount)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF475569),
                ),
          ),
          if ((item.note ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.note!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
              if (onVoucher != null)
                OutlinedButton.icon(
                  onPressed: onVoucher,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Ver voucher'),
                ),
              if (onUploadVoucher != null)
                OutlinedButton.icon(
                  onPressed: onUploadVoucher,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(item.hasVoucher ? 'Cambiar voucher' : 'Subir voucher'),
                ),
              if (onEdit != null)
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
              if (onDelete != null)
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar'),
                ),
              if (!isAdmin)
                const Text('Asistente: puede crear depósitos; edición y eliminación solo admin.'),
            ],
          ),
        ],
      ),
    );
  }
}