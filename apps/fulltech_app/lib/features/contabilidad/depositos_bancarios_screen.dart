import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/api/env.dart';
import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/role_permissions.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../user/data/users_repository.dart';
import 'data/contabilidad_repository.dart';
import 'deposit_bank_catalog.dart';
import 'models/deposit_order_model.dart';
import 'utils/deposit_order_pdf_service.dart';

enum _DepositTileMenuAction {
  detail,
  pdf,
  voucher,
  uploadVoucher,
  edit,
  delete,
}

class DepositosBancariosScreen extends ConsumerStatefulWidget {
  const DepositosBancariosScreen({super.key});

  @override
  ConsumerState<DepositosBancariosScreen> createState() =>
      _DepositosBancariosScreenState();
}

class _DepositosBancariosScreenState
    extends ConsumerState<DepositosBancariosScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
  final _dateFmt = DateFormat('dd/MM/yyyy');
  final _amountInputFmt = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RD ',
    decimalDigits: 2,
  );
  bool _loading = true;
  String? _error;
  List<DepositOrderModel> _orders = const [];
  List<String> _collaborators = const [];
  DateTimeRange? _dateRange;

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
      final rows = await ref.read(contabilidadRepositoryProvider).listDepositOrders(
            from: _dateRange?.start,
            to: _dateRange?.end,
          );
      rows.sort((left, right) {
        final byWindow = right.windowFrom.compareTo(left.windowFrom);
        if (byWindow != 0) return byWindow;
        return right.createdAt.compareTo(left.createdAt);
      });
      if (!mounted) return;
      setState(() {
        _orders = rows;
        _loading = false;
      });
      await _loadCollaborators(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los depósitos: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadCollaborators({bool forceRefresh = false}) async {
    try {
      final users = await ref.read(usersRepositoryProvider).getAllUsers(
            forceRefresh: forceRefresh,
            skipLoader: true,
          );
      final collaborators = users
          .map((item) => item.nombreCompleto.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _collaborators = collaborators;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _collaborators = const [];
      });
    }
  }

  bool get _isAdmin => ref.read(authStateProvider).user?.appRole.isAdmin ?? false;

  Future<void> _applyDateRange(DateTimeRange? value) async {
    setState(() {
      _dateRange = value;
    });
    await _load();
  }

  Future<void> _clearDateRange() => _applyDateRange(null);

  Future<void> _pickDateRangeFromAppBar() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _dateRange,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    await _applyDateRange(picked);
  }

  Future<void> _showSnack(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openEditor({DepositOrderModel? initial}) async {
    if (_collaborators.isEmpty) {
      await _loadCollaborators(forceRefresh: true);
    }
    if (!mounted) return;

    final createdAt = initial?.windowFrom ?? DateTime.now();
    final dateCtrl = TextEditingController(text: _dateFmt.format(createdAt));
    final amountCtrl = TextEditingController(
      text: initial == null ? '' : _amountInputFmt.format(initial.depositTotal),
    );
    final noteCtrl = TextEditingController(text: initial?.note ?? '');

    var depositDate = createdAt;
    var selectedBank = _resolveBank(initial?.bankName);
    var selectedAccount = _resolveAccount(selectedBank, initial?.bankAccount);
    var selectedCollaborator = _resolveCollaborator(initial?.collaboratorName);
    var saving = false;
    String? localError;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'DepositosBancariosForm',
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDesktop = MediaQuery.sizeOf(context).width >= 900;

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
              final parsedAmount = _parseFormattedAmount(amountCtrl.text);
              if (selectedBank == null) {
                setDialogState(() => localError = 'Debes seleccionar el banco');
                return;
              }
              if (selectedAccount == null) {
                setDialogState(() => localError = 'Debes seleccionar la cuenta');
                return;
              }
              if (selectedCollaborator == null || selectedCollaborator!.trim().isEmpty) {
                setDialogState(() => localError = 'Debes seleccionar el colaborador');
                return;
              }
              if (parsedAmount == null || parsedAmount <= 0) {
                setDialogState(() => localError = 'Indica un monto válido');
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
                    collaboratorName: selectedCollaborator,
                    note: noteCtrl.text,
                    reserveAmount: 0,
                    totalAvailableCash: parsedAmount,
                    depositTotal: parsedAmount,
                    closesCountByType: const {'GENERAL': 1},
                    depositByType: {'GENERAL': parsedAmount},
                    accountByType: {'GENERAL': selectedAccount!.label},
                  );
                } else {
                  await repo.updateDepositOrder(
                    id: initial.id,
                    windowFrom: depositDate,
                    windowTo: depositDate,
                    bankName: selectedBank!.label,
                    bankAccount: selectedAccount!.label,
                    collaboratorName: selectedCollaborator,
                    note: noteCtrl.text,
                    reserveAmount: 0,
                    totalAvailableCash: parsedAmount,
                    depositTotal: parsedAmount,
                    closesCountByType: const {'GENERAL': 1},
                    depositByType: {'GENERAL': parsedAmount},
                    accountByType: {'GENERAL': selectedAccount!.label},
                  );
                }
                if (!mounted || !dialogContext.mounted) return;
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

            final dialogChild = Material(
              color: Colors.transparent,
              child: Align(
                alignment: isDesktop ? Alignment.centerRight : Alignment.center,
                child: Container(
                  width: isDesktop ? 560 : double.infinity,
                  margin: EdgeInsets.fromLTRB(
                    isDesktop ? 0 : 12,
                    isDesktop ? 24 : 12,
                    isDesktop ? 24 : 12,
                    isDesktop ? 24 : 12,
                  ),
                  constraints: BoxConstraints(
                    maxWidth: 560,
                    maxHeight: isDesktop
                        ? MediaQuery.sizeOf(context).height - 48
                        : MediaQuery.sizeOf(context).height * 0.94,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(isDesktop ? 24 : 28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x260F172A),
                        blurRadius: 30,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isDesktop ? 20 : 18),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            initial == null
                                ? 'Nuevo depósito bancario'
                                : 'Editar depósito bancario',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Registra el depósito con banco, cuenta, colaborador y monto.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFF64748B),
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
                            key: ValueKey('bank-${selectedBank?.id ?? 'none'}'),
                            initialValue: selectedBank,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Banco'),
                            items: depositBankCatalog
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item,
                                    child: Text(
                                      item.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
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
                            key: ValueKey(
                              'account-${selectedBank?.id ?? 'none'}-${selectedAccount?.id ?? 'none'}',
                            ),
                            initialValue: selectedAccount,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Cuenta destino'),
                            items: accounts
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item,
                                    child: Text(
                                      item.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: accounts.isEmpty
                                ? null
                                : (value) => setDialogState(() => selectedAccount = value),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            key: ValueKey('collaborator-${selectedCollaborator ?? 'none'}'),
                            initialValue: selectedCollaborator,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Colaborador que deposita',
                            ),
                            items: _collaborators
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item,
                                    child: Text(
                                      item,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _collaborators.isEmpty
                                ? null
                                : (value) => setDialogState(() => selectedCollaborator = value),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: const [_CurrencyAmountTextInputFormatter()],
                            decoration: const InputDecoration(
                              labelText: 'Monto a depositar',
                              hintText: 'RD 22,500.20',
                            ),
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
                                onPressed: saving
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
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
                ),
              ),
            );

            return dialogChild;
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        final beginOffset = MediaQuery.sizeOf(context).width >= 900
            ? const Offset(0.12, 0)
            : const Offset(0, 0.06);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  String? _resolveCollaborator(String? name) {
    final normalized = (name ?? '').trim().toLowerCase();
    for (final item in _collaborators) {
      if (item.trim().toLowerCase() == normalized) return item;
    }
    return _collaborators.isEmpty ? null : _collaborators.first;
  }

  double? _parseFormattedAmount(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final cents = int.tryParse(digits);
    if (cents == null) return null;
    return cents / 100;
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
      final updated = await ref
          .read(contabilidadRepositoryProvider)
          .uploadDepositVoucher(id: item.id, file: result.files.first);
      if (!mounted) return;
      setState(() {
        _orders = _orders
            .map((row) => row.id == updated.id ? updated : row)
            .toList(growable: false);
      });
      await _showSnack('Voucher cargado correctamente.');
    } catch (e) {
      await _showSnack('No se pudo cargar el voucher: $e');
    }
  }

  Future<DepositOrderModel> _getFreshOrder(DepositOrderModel item) async {
    try {
      final updated = await ref.read(contabilidadRepositoryProvider).getDepositOrder(item.id);
      if (mounted) {
        setState(() {
          _orders = _orders
              .map((row) => row.id == updated.id ? updated : row)
              .toList(growable: false);
        });
      }
      return updated;
    } catch (_) {
      return item;
    }
  }

  Future<void> _openVoucher(DepositOrderModel item) async {
    final fresh = await _getFreshOrder(item);
    if (!mounted) return;
    final uri = _resolveVoucherUri(fresh, forceNow: true);
    if (uri == null) {
      await _showSnack('El voucher no tiene una URL válida.');
      return;
    }
    await safeOpenUrl(context, uri, copiedMessage: 'No se pudo abrir el voucher. Link copiado.');
  }

  Future<void> _openVoucherImageFullscreen(DepositOrderModel item) async {
    final fresh = await _getFreshOrder(item);
    if (!mounted) return;
    final imageUrl = _resolveVoucherUri(fresh)?.toString() ?? '';
    if (imageUrl.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No se pudo cargar la imagen del voucher.',
                            style: TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton.filled(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openDepositDetail(DepositOrderModel item) async {
    final fresh = await _getFreshOrder(item);
    if (!mounted) return;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final hasImageVoucher = _isImageVoucher(fresh);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: isDesktop ? 980 : double.infinity,
            height: isDesktop ? 760 : 700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Detalle del depósito',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _DetailInfoCard(
                              title: 'Resumen',
                              children: [
                                _DetailRow(label: 'Estado', value: item.status.label),
                                _DetailRow(label: 'Estado', value: fresh.status.label),
                                _DetailRow(label: 'Monto', value: _money.format(fresh.depositTotal)),
                                _DetailRow(label: 'Banco', value: fresh.bankName),
                                _DetailRow(
                                  label: 'Cuenta',
                                  value: fresh.bankAccount ?? 'No indicada',
                                ),
                                _DetailRow(
                                  label: 'Fecha',
                                  value: _dateFmt.format(fresh.windowFrom),
                                ),
                              ],
                            ),
                            _DetailInfoCard(
                              title: 'Responsables',
                              children: [
                                _DetailRow(
                                  label: 'Ordenado por',
                                  value: fresh.createdByName ?? fresh.createdById ?? 'No indicado',
                                ),
                                _DetailRow(
                                  label: 'Ejecutado por',
                                  value: fresh.executedByName ?? fresh.collaboratorName ?? 'No indicado',
                                ),
                                _DetailRow(
                                  label: 'Actualizado',
                                  value: DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(fresh.updatedAt),
                                ),
                                if (fresh.executedAt != null)
                                  _DetailRow(
                                    label: 'Ejecutado el',
                                    value: DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(fresh.executedAt!),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _DetailInfoCard(
                          title: 'Cuentas y montos',
                          fullWidth: true,
                          children: [
                            ...fresh.depositByType.entries.map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${entry.key} · ${fresh.accountByType[entry.key] ?? fresh.bankAccount ?? 'Cuenta sin indicar'}',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      _money.format(entry.value),
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if ((fresh.note ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _DetailInfoCard(
                            title: 'Comentario',
                            fullWidth: true,
                            children: [
                              Text(
                                fresh.note!.trim(),
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFF475569),
                                    ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        _DetailInfoCard(
                          title: 'Voucher subido',
                          fullWidth: true,
                          children: [
                            if (!fresh.hasVoucher)
                              const Text('Este depósito todavía no tiene voucher cargado.'),
                            if (fresh.hasVoucher) ...[
                              _DetailRow(
                                label: 'Archivo',
                                value: fresh.voucherFileName ?? 'Voucher cargado',
                              ),
                              _DetailRow(
                                label: 'Tipo',
                                value: fresh.voucherMimeType ?? 'No indicado',
                              ),
                              const SizedBox(height: 8),
                              if (hasImageVoucher)
                                InkWell(
                                  onTap: () => _openVoucherImageFullscreen(fresh),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      constraints: const BoxConstraints(maxHeight: 360),
                                      color: const Color(0xFFF8FAFC),
                                      child: Image.network(
                                        fresh.voucherUrl!,
                                        fit: BoxFit.contain,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return const Padding(
                                            padding: EdgeInsets.all(24),
                                            child: Center(child: CircularProgressIndicator()),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return const Padding(
                                            padding: EdgeInsets.all(24),
                                            child: Text('No se pudo cargar la imagen del voucher.'),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              if (!hasImageVoucher)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFFD9E0E8)),
                                  ),
                                  child: const Text(
                                    'El voucher no es una imagen visible dentro de la app. Puedes abrirlo con el botón de abajo.',
                                  ),
                                ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _openVoucher(fresh),
                                    icon: const Icon(Icons.open_in_new_outlined),
                                    label: Text(hasImageVoucher ? 'Abrir original' : 'Abrir voucher'),
                                  ),
                                  if (hasImageVoucher)
                                    FilledButton.icon(
                                      onPressed: () => _openVoucherImageFullscreen(fresh),
                                      icon: const Icon(Icons.zoom_out_map_outlined),
                                      label: const Text('Ver imagen grande'),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isImageVoucher(DepositOrderModel item) {
    final mime = (item.voucherMimeType ?? '').trim().toLowerCase();
    if (mime.startsWith('image/')) return true;
    final url = (_resolveVoucherUri(item)?.path ?? item.voucherUrl ?? '').trim().toLowerCase();
    return url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.webp');
  }

  Uri? _resolveVoucherUri(DepositOrderModel item, {bool forceNow = false}) {
    final raw = (item.voucherUrl ?? '').trim();
    if (raw.isEmpty) return null;

    final normalized = raw.replaceAll('\\', '/');
    final baseUrl = Env.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

    Uri? uri;
    if (normalized.startsWith('/uploads/')) {
      uri = Uri.tryParse('$baseUrl$normalized');
    } else if (normalized.startsWith('uploads/')) {
      uri = Uri.tryParse('$baseUrl/$normalized');
    } else if (normalized.startsWith('./uploads/')) {
      uri = Uri.tryParse('$baseUrl/${normalized.substring(2)}');
    } else {
      uri = Uri.tryParse(normalized);
      if (uri != null && !uri.hasScheme) {
        uri = Uri.tryParse(
          normalized.startsWith('/') ? '$baseUrl$normalized' : '$baseUrl/$normalized',
        );
      }
    }

    if (uri == null) return null;

    final cacheKey = forceNow
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : item.updatedAt.millisecondsSinceEpoch.toString();
    final query = Map<String, String>.from(uri.queryParameters);
    query['v'] = cacheKey;
    return uri.replace(queryParameters: query);
  }

  Future<void> _openPdfPreview(DepositOrderModel item) async {
    final pdfBytes = await buildDepositOrderPdf(
      data: DepositOrderPdfData(
        generatedAt: DateTime.now(),
        windowFrom: item.windowFrom,
        windowTo: item.windowTo,
        bankName: item.bankName,
        createdByName: item.createdByName,
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

  Future<void> _handleTileAction(
    DepositOrderModel item,
    _DepositTileMenuAction action,
  ) async {
    switch (action) {
      case _DepositTileMenuAction.detail:
        await _openDepositDetail(item);
        break;
      case _DepositTileMenuAction.pdf:
        await _openPdfPreview(item);
        break;
      case _DepositTileMenuAction.voucher:
        await _openVoucher(item);
        break;
      case _DepositTileMenuAction.uploadVoucher:
        await _uploadVoucher(item);
        break;
      case _DepositTileMenuAction.edit:
        await _openEditor(initial: item);
        break;
      case _DepositTileMenuAction.delete:
        await _confirmDelete(item);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canUseModule = canAccessContabilidadByRole(user?.role);
    final pendingCount =
      _orders.where((item) => item.status == DepositOrderStatus.pending).length;
    final executedCount =
      _orders.where((item) => item.status == DepositOrderStatus.executed).length;
    final executedOrders = _orders
        .where((item) => item.status == DepositOrderStatus.executed)
        .toList(growable: false);
    final executedTotal = executedOrders.fold<double>(
      0,
      (sum, item) => sum + item.depositTotal,
    );

    if (!canUseModule) {
      return Scaffold(
        key: _scaffoldKey,
        appBar: CustomAppBar(
          title: 'Depósitos bancarios',
          showLogo: false,
          showDepartmentLabel: false,
          actions: [
            IconButton(
              tooltip: 'Menú',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          ],
        ),
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AppBarBackButton(
                onPressed: () => AppNavigator.goBack(context),
              ),
              const SizedBox(height: 16),
              const Expanded(
                child: Center(
                  child: Text(
                    'Este módulo está disponible solo para usuarios autorizados.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final summaryPanel = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AppBarBackButton(
          onPressed: () => AppNavigator.goBack(context),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DepositsSummaryBar(
            total: _orders.length,
            pending: pendingCount,
            executed: executedCount,
            depositedCount: executedOrders.length,
            depositedTotal: executedTotal,
            money: _money,
          ),
        ),
      ],
    );

    return Scaffold(
      key: _scaffoldKey,
      appBar: CustomAppBar(
        title: 'Depósitos bancarios',
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          IconButton(
            tooltip: 'Menú',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
          IconButton(
            tooltip: _dateRange == null ? 'Filtrar' : 'Cambiar filtro',
            onPressed: _pickDateRangeFromAppBar,
            icon: Badge(
              isLabelVisible: _dateRange != null,
              smallSize: 8,
              child: const Icon(Icons.filter_alt_outlined),
            ),
          ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo depósito'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            summaryPanel,
            const SizedBox(height: 12),
            if (_dateRange != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    avatar: const Icon(Icons.date_range_outlined, size: 18),
                    label: Text(
                      '${_dateFmt.format(_dateRange!.start)} - ${_dateFmt.format(_dateRange!.end)}',
                    ),
                    onDeleted: _clearDateRange,
                  ),
                ),
              ),
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
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFD9E0E8)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F0F172A),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _DepositListHeader(isAdmin: _isAdmin),
                    for (var index = 0; index < _orders.length; index++) ...[
                      if (index > 0) const Divider(height: 1),
                      _DepositOrderTile(
                        item: _orders[index],
                        money: _money,
                        statusColor: _statusColor(_orders[index].status),
                        isAdmin: _isAdmin,
                        onTap: () => _openDepositDetail(_orders[index]),
                        onSelectedAction: (action) =>
                            _handleTileAction(_orders[index], action),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DepositsSummaryBar extends StatelessWidget {
  const _DepositsSummaryBar({
    required this.total,
    required this.pending,
    required this.executed,
    required this.depositedCount,
    required this.depositedTotal,
    required this.money,
  });
  final int total;
  final int pending;
  final int executed;
  final int depositedCount;
  final double depositedTotal;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A5F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _SummaryPill(label: 'Total', value: '$total')),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryPill(label: 'Pendiente', value: '$pending'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryPill(label: 'Ejecutada', value: '$executed'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SummaryPill(label: 'Número', value: '$depositedCount'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _SummaryPill(
                    label: 'Depositado',
                    value: money.format(depositedTotal),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBarBackButton extends StatelessWidget {
  const _AppBarBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: SizedBox(
        width: 52,
        height: 52,
        child: IconButton(
          tooltip: 'Regresar',
          onPressed: onPressed,
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DepositListHeader extends StatelessWidget {
  const _DepositListHeader({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: const Color(0xFF64748B),
          fontWeight: FontWeight.w800,
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Banco', style: style)),
          Expanded(flex: 2, child: Text('Ejecutó', style: style)),
          Expanded(
            child: Text('Monto', style: style, textAlign: TextAlign.end),
          ),
          SizedBox(
            width: isAdmin ? 48 : 44,
            child: Text('Más', style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _CurrencyAmountTextInputFormatter extends TextInputFormatter {
  const _CurrencyAmountTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final cents = int.tryParse(digits);
    if (cents == null) return oldValue;

    final amount = cents / 100;
    final formatted = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'RD ',
      decimalDigits: 2,
    ).format(amount);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _DepositOrderTile extends StatelessWidget {
  const _DepositOrderTile({
    required this.item,
    required this.money,
    required this.statusColor,
    required this.isAdmin,
    required this.onTap,
    required this.onSelectedAction,
  });

  final DepositOrderModel item;
  final NumberFormat money;
  final Color statusColor;
  final bool isAdmin;
  final VoidCallback onTap;
  final ValueChanged<_DepositTileMenuAction> onSelectedAction;

  @override
  Widget build(BuildContext context) {
    final executedBy = item.executedByName ?? item.collaboratorName ?? 'No indicado';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.bankName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.bankAccount ?? 'Cuenta sin indicar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    executedBy,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.status.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                money.format(item.depositTotal),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            PopupMenuButton<_DepositTileMenuAction>(
              tooltip: 'Más acciones',
              onSelected: onSelectedAction,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _DepositTileMenuAction.detail,
                  child: _DepositMenuItem(
                    icon: Icons.visibility_outlined,
                    label: 'Ver detalle',
                  ),
                ),
                const PopupMenuItem(
                  value: _DepositTileMenuAction.pdf,
                  child: _DepositMenuItem(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'Carta PDF',
                  ),
                ),
                if (item.hasVoucher)
                  const PopupMenuItem(
                    value: _DepositTileMenuAction.voucher,
                    child: _DepositMenuItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'Ver voucher',
                    ),
                  ),
                if (isAdmin)
                  PopupMenuItem(
                    value: _DepositTileMenuAction.uploadVoucher,
                    child: _DepositMenuItem(
                      icon: Icons.upload_file_outlined,
                      label: item.hasVoucher ? 'Cambiar voucher' : 'Subir voucher',
                    ),
                  ),
                if (isAdmin)
                  const PopupMenuItem(
                    value: _DepositTileMenuAction.edit,
                    child: _DepositMenuItem(
                      icon: Icons.edit_outlined,
                      label: 'Editar',
                    ),
                  ),
                if (isAdmin)
                  const PopupMenuItem(
                    value: _DepositTileMenuAction.delete,
                    child: _DepositMenuItem(
                      icon: Icons.delete_outline,
                      label: 'Eliminar',
                    ),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.more_vert_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepositMenuItem extends StatelessWidget {
  const _DepositMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0F172A)),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

class _DetailInfoCard extends StatelessWidget {
  const _DetailInfoCard({
    required this.title,
    required this.children,
    this.fullWidth = false,
  });

  final String title;
  final List<Widget> children;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: fullWidth ? double.infinity : 440,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E0E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
    return fullWidth ? card : SizedBox(width: 440, child: card);
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF0F172A),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}