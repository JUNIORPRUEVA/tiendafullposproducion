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
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../user/data/users_repository.dart';
import 'data/contabilidad_repository.dart';
import 'deposit_bank_catalog.dart';
import 'models/deposit_order_model.dart';
import 'utils/deposit_order_pdf_service.dart';
import 'widgets/date_range_picker_field.dart';

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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canUseModule = canAccessContabilidadByRole(user?.role);
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
      key: _scaffoldKey,
      appBar: CustomAppBar(
        title: 'Depósitos bancarios',
        showLogo: false,
        showDepartmentLabel: false,
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
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
              dateRange: _dateRange,
              isAdmin: _isAdmin,
              depositedCount: executedOrders.length,
              depositedTotal: executedTotal,
              onDateRangeChanged: _applyDateRange,
              onClearDateRange: _dateRange == null ? null : _clearDateRange,
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
                    onDetail: () => _openDepositDetail(item),
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
    required this.dateRange,
    required this.isAdmin,
    required this.depositedCount,
    required this.depositedTotal,
    required this.onDateRangeChanged,
    required this.onClearDateRange,
    required this.onCreate,
  });

  final int total;
  final int pending;
  final int executed;
  final DateTimeRange? dateRange;
  final bool isAdmin;
  final int depositedCount;
  final double depositedTotal;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final VoidCallback? onClearDateRange;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E0E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gestión de depósitos bancarios',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: isMobile ? 15 : null,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Filtra por fechas y revisa el historial de depósitos más recientes primero.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF64748B),
                            fontSize: isMobile ? 12 : null,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: Text(isMobile ? 'Nuevo' : 'Nuevo depósito'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                height: isMobile ? 40 : 44,
                child: DateRangePickerField(
                  value: dateRange,
                  label: 'Intervalo',
                  onChanged: onDateRangeChanged,
                ),
              ),
              if (onClearDateRange != null)
                SizedBox(
                  height: isMobile ? 40 : 44,
                  child: OutlinedButton.icon(
                    onPressed: onClearDateRange,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: const Text('Limpiar'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: isMobile ? 6 : 12,
            runSpacing: 6,
            children: [
              _HeaderChip(label: 'Total: $total', compact: isMobile),
              _HeaderChip(label: 'Pendientes: $pending', compact: isMobile),
              _HeaderChip(label: 'Ejecutados: $executed', compact: isMobile),
            ],
          ),
          if (isAdmin) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(isMobile ? 12 : 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD9E0E8)),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _AdminSummaryTile(
                    compact: isMobile,
                    icon: Icons.paid_outlined,
                    label: 'Monto total depositado',
                    value: money.format(depositedTotal),
                    helper: 'Solo depósitos ejecutados',
                  ),
                  _AdminSummaryTile(
                    compact: isMobile,
                    icon: Icons.local_shipping_outlined,
                    label: 'Veces depositadas',
                    value: '$depositedCount',
                    helper: 'Cantidad de depósitos ejecutados',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminSummaryTile extends StatelessWidget {
  const _AdminSummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final String value;
  final String helper;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = compact ? double.infinity : 250.0;
    return SizedBox(
      width: width,
      child: Container(
        padding: EdgeInsets.all(compact ? 12 : 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD9E0E8)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    helper,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
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

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD9E0E8)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: compact ? 11 : 13),
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
    required this.dateFmt,
    required this.statusColor,
    required this.isAdmin,
    required this.onDetail,
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
  final VoidCallback onDetail;
  final VoidCallback onPdf;
  final VoidCallback? onVoucher;
  final VoidCallback? onUploadVoucher;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 14,
        vertical: isMobile ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD9E0E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      money.format(item.depositTotal),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: isMobile ? 16 : null,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.bankName} · ${item.bankAccount ?? 'Cuenta sin indicar'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF475569),
                            fontSize: isMobile ? 12.5 : null,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 8 : 10,
                  vertical: isMobile ? 4 : 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.status.label,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: isMobile ? 11.5 : 13,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 6 : 8),
          Text(
            'Fecha: ${dateFmt.format(item.windowFrom)} · ${item.collaboratorName ?? 'No indicado'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF475569),
                  fontSize: isMobile ? 12 : null,
                ),
          ),
          if ((item.note ?? '').trim().isNotEmpty) ...[
            SizedBox(height: isMobile ? 4 : 6),
            Text(
              item.note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontSize: isMobile ? 11.5 : null,
                  ),
            ),
          ],
          SizedBox(height: isMobile ? 8 : 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onDetail,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Detalle'),
                style: isMobile
                    ? FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: Size.zero,
                      )
                    : null,
              ),
              OutlinedButton.icon(
                onPressed: onPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
                style: isMobile
                    ? OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: Size.zero,
                      )
                    : null,
              ),
              if (onVoucher != null)
                OutlinedButton.icon(
                  onPressed: onVoucher,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Ver voucher'),
                  style: isMobile
                      ? OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: Size.zero,
                        )
                      : null,
                ),
              if (onUploadVoucher != null)
                OutlinedButton.icon(
                  onPressed: onUploadVoucher,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(item.hasVoucher ? 'Cambiar voucher' : 'Subir voucher'),
                  style: isMobile
                      ? OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: Size.zero,
                        )
                      : null,
                ),
              if (onEdit != null)
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                  style: isMobile
                      ? OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: Size.zero,
                        )
                      : null,
                ),
              if (onDelete != null)
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Eliminar'),
                  style: isMobile
                      ? OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: Size.zero,
                        )
                      : null,
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