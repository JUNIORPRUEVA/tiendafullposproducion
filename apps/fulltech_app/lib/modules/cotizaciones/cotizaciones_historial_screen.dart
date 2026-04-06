import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../features/catalogo/data/catalog_local_repository.dart';
import '../clientes/cliente_model.dart';
import '../clientes/data/clientes_repository.dart';
import 'cotizacion_models.dart';
import 'data/cotizaciones_repository.dart';

class CotizacionesHistorialScreen extends ConsumerStatefulWidget {
  final String? customerPhone;
  final bool pickForEditor;
  final String? quoteId;

  const CotizacionesHistorialScreen({
    super.key,
    this.customerPhone,
    this.pickForEditor = true,
    this.quoteId,
  });

  @override
  ConsumerState<CotizacionesHistorialScreen> createState() =>
      _CotizacionesHistorialScreenState();
}

class _CotizacionesHistorialScreenState
    extends ConsumerState<CotizacionesHistorialScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<CotizacionModel> _items = const [];
  List<ClienteModel> _knownClients = const [];
  Map<String, String> _categoryByProductId = const {};
  Set<String> _ownedClientIds = const {};
  Set<String> _ownedClientPhones = const {};
  bool _autoOpened = false;
  String _searchQuery = '';
  String? _selectedClientKey;
  String? _selectedQuoteTag;
  DateTime? _fromDate;
  DateTime? _toDate;

  String _money(double value) =>
      NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value);

  bool _canEditOrDelete(CotizacionModel item) {
    final user = ref.read(authStateProvider).user;
    if (user == null) return false;
    if (user.appRole == AppRole.admin) return true;

    final createdByUserId = (item.createdByUserId ?? '').trim();
    if (createdByUserId.isEmpty) return false;

    return createdByUserId == user.id.trim();
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_handleSearchChanged);
    _loadSupportData();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_handleSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchCtrl.text.trim();
    if (next == _searchQuery) return;
    setState(() => _searchQuery = next);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _refreshing = false;
      _error = null;
    });
    final repo = ref.read(cotizacionesRepositoryProvider);
    try {
      final cached = await repo.getCachedList(
        customerPhone: widget.customerPhone,
      );
      if (!mounted) return;
      if (cached.isNotEmpty) {
        setState(() {
          _items = cached;
          _loading = false;
          _refreshing = true;
        });
      }

      final rows = await repo.listAndCache(customerPhone: widget.customerPhone);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
        _refreshing = false;
      });

      await _maybeAutoOpenQuote();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _loadSupportData() async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    final clientsRepo = ref.read(clientesRepositoryProvider);
    final catalogRepo = ref.read(catalogLocalRepositoryProvider);

    try {
      final cachedClients = await clientsRepo.getCachedClients(ownerId: user.id);
      final catalogSnapshot = await catalogRepo.readSnapshot();
      if (!mounted) return;
      setState(() {
        _applyKnownClients(cachedClients, userId: user.id);
        _categoryByProductId = {
          for (final product in catalogSnapshot.items)
            if ((product.categoria ?? '').trim().isNotEmpty) product.id: product.categoria!.trim(),
        };
      });

      final remoteClients = await clientsRepo.listClients(
        ownerId: user.id,
        pageSize: 300,
        skipLoader: true,
      );
      if (!mounted) return;
      setState(() {
        _applyKnownClients(remoteClients, userId: user.id);
      });
    } catch (_) {
      // Never block the screen if support metadata cannot be hydrated.
    }
  }

  void _applyKnownClients(List<ClienteModel> clients, {required String userId}) {
    final active = clients.where((client) => !client.isDeleted).toList(growable: false);
    _knownClients = active;
    _ownedClientIds = {
      for (final client in active)
        if (client.ownerId.trim() == userId.trim() && client.id.trim().isNotEmpty)
          client.id.trim(),
    };
    _ownedClientPhones = {
      for (final client in active)
        if (client.ownerId.trim() == userId.trim()) _normalizePhone(client.telefono),
    }..remove('');
  }

  Future<void> _maybeAutoOpenQuote() async {
    if (_autoOpened) return;
    final id = (widget.quoteId ?? '').trim();
    if (id.isEmpty) return;

    _autoOpened = true;

    try {
      CotizacionModel? found;
      for (final item in _items) {
        if (item.id.trim() == id) {
          found = item;
          break;
        }
      }

        final selected =
          found ??
          await ref.read(cotizacionesRepositoryProvider).getCachedById(id) ??
          await ref.read(cotizacionesRepositoryProvider).getByIdAndCache(id);
        if (!mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _viewDetail(selected);
      });
    } catch (_) {
      // Ignore: deep-link should never block screen rendering.
    }
  }

  Future<void> _delete(CotizacionModel item) async {
    if (!widget.pickForEditor) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cotización'),
        content: Text('¿Eliminar la cotización de ${item.customerName}?'),
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
    if (ok != true) return;

    await ref.read(cotizacionesRepositoryProvider).deleteOrQueue(item.id);
    await _load();
  }

  String _normalizePhone(String? value) {
    return (value ?? '').replaceAll(RegExp(r'[^0-9]'), '').trim();
  }

  String _clientKey({String? customerId, String? customerPhone, required String customerName}) {
    final id = (customerId ?? '').trim();
    if (id.isNotEmpty) return 'id:$id';
    final phone = _normalizePhone(customerPhone);
    if (phone.isNotEmpty) return 'phone:$phone';
    return 'name:${customerName.trim().toLowerCase()}';
  }

  bool _isOwnClient(CotizacionModel item) {
    final customerId = (item.customerId ?? '').trim();
    if (customerId.isNotEmpty && _ownedClientIds.contains(customerId)) {
      return true;
    }
    final phone = _normalizePhone(item.customerPhone);
    return phone.isNotEmpty && _ownedClientPhones.contains(phone);
  }

  Set<String> _quoteTags(CotizacionModel item) {
    final tags = <String>{};
    for (final line in item.items) {
      final category = _categoryByProductId[line.productId]?.trim();
      if (category != null && category.isNotEmpty) {
        tags.add(category);
      }
    }

    final keywordTag = _inferKeywordTag(
      [
        item.note,
        item.customerName,
        for (final line in item.items) line.nombre,
      ].join(' '),
    );
    if (keywordTag != null) {
      tags.add(keywordTag);
    }

    if (tags.isEmpty) {
      tags.add('General');
    }
    return tags;
  }

  String? _inferKeywordTag(String source) {
    final text = source.toLowerCase();
    const groups = <String, List<String>>{
      'Camaras': ['camara', 'cctv', 'dvr', 'nvr'],
      'Alarmas': ['alarma', 'sensor', 'sirena'],
      'Redes': ['router', 'wifi', 'red', 'switch', 'network'],
      'Control de acceso': ['acceso', 'biometr', 'huella', 'cerradura'],
      'Intercom': ['intercom', 'videoportero', 'portero'],
      'Portones': ['porton', 'motor'],
      'Electricidad': ['inversor', 'bateria', 'panel', 'electr'],
    };

    for (final entry in groups.entries) {
      for (final token in entry.value) {
        if (text.contains(token)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  bool _matchesSearch(CotizacionModel item) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final createdDate = DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(item.createdAt);
    final haystack = [
      item.id,
      item.customerName,
      item.customerPhone ?? '',
      item.createdByUserName ?? '',
      item.note,
      createdDate,
      ..._quoteTags(item),
      for (final line in item.items) ...[
        line.nombre,
        line.productId,
      ],
    ].join(' ').toLowerCase();

    return haystack.contains(query);
  }

  List<_ClientFilterOption> get _clientOptions {
    final options = <String, _ClientFilterOption>{};

    for (final client in _knownClients) {
      final key = _clientKey(
        customerId: client.id,
        customerPhone: client.telefono,
        customerName: client.nombre,
      );
      options[key] = _ClientFilterOption(
        key: key,
        label: client.nombre.trim().isEmpty ? 'Cliente sin nombre' : client.nombre.trim(),
        subtitle: client.telefono.trim(),
        owned: client.ownerId.trim().isNotEmpty && client.ownerId.trim() == ref.read(authStateProvider).user?.id.trim(),
      );
    }

    for (final item in _items) {
      final key = _clientKey(
        customerId: item.customerId,
        customerPhone: item.customerPhone,
        customerName: item.customerName,
      );
      options.putIfAbsent(
        key,
        () => _ClientFilterOption(
          key: key,
          label: item.customerName,
          subtitle: (item.customerPhone ?? '').trim(),
          owned: _isOwnClient(item),
        ),
      );
    }

    final values = options.values.toList(growable: false);
    values.sort((a, b) {
      if (a.owned != b.owned) return a.owned ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return values;
  }

  List<String> get _availableTags {
    final values = {
      for (final item in _items) ..._quoteTags(item),
    }.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  int get _activeFilterCount {
    var count = 0;
    if (_selectedClientKey != null) count++;
    if (_selectedQuoteTag != null) count++;
    if (_fromDate != null || _toDate != null) count++;
    return count;
  }

  List<CotizacionModel> get _visibleItems {
    final filtered = _items.where((item) {
      if (!_matchesSearch(item)) return false;
      if (_selectedClientKey != null &&
          _clientKey(
                customerId: item.customerId,
                customerPhone: item.customerPhone,
                customerName: item.customerName,
              ) !=
              _selectedClientKey) {
        return false;
      }
      if (_selectedQuoteTag != null && !_quoteTags(item).contains(_selectedQuoteTag)) {
        return false;
      }
      if (_fromDate != null) {
        final start = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
        if (item.createdAt.isBefore(start)) return false;
      }
      if (_toDate != null) {
        final end = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59, 999);
        if (item.createdAt.isAfter(end)) return false;
      }
      return true;
    }).toList(growable: false);

    filtered.sort((a, b) {
      final aOwned = _isOwnClient(a);
      final bOwned = _isOwnClient(b);
      if (aOwned != bOwned) return aOwned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return filtered;
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_HistorialFilterState>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var clientKey = _selectedClientKey;
        var quoteTag = _selectedQuoteTag;
        var fromDate = _fromDate;
        var toDate = _toDate;

        Future<DateTime?> pickDate(DateTime? initialDate) async {
          final now = DateTime.now();
          return showDatePicker(
            context: context,
            initialDate: initialDate ?? now,
            firstDate: DateTime(now.year - 5),
            lastDate: DateTime(now.year + 2),
            locale: const Locale('es', 'DO'),
          );
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Filtros del historial',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Filtra por cliente, fecha o categoria para encontrar cotizaciones mas rapido.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String?>(
                        initialValue: clientKey,
                        decoration: const InputDecoration(
                          labelText: 'Cliente',
                          prefixIcon: Icon(Icons.person_search_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Todos los clientes'),
                          ),
                          ..._clientOptions.map(
                            (option) => DropdownMenuItem<String?>(
                              value: option.key,
                              child: Text(option.label),
                            ),
                          ),
                        ],
                        onChanged: (value) => setSheetState(() => clientKey = value),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String?>(
                        initialValue: quoteTag,
                        decoration: const InputDecoration(
                          labelText: 'Categoria / tipo de servicio',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Todas las categorias'),
                          ),
                          ..._availableTags.map(
                            (tag) => DropdownMenuItem<String?>(
                              value: tag,
                              child: Text(tag),
                            ),
                          ),
                        ],
                        onChanged: (value) => setSheetState(() => quoteTag = value),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 220,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await pickDate(fromDate);
                                if (picked == null) return;
                                setSheetState(() {
                                  fromDate = picked;
                                  if (toDate != null && toDate!.isBefore(picked)) {
                                    toDate = picked;
                                  }
                                });
                              },
                              icon: const Icon(Icons.event_outlined),
                              label: Text(
                                fromDate == null
                                    ? 'Desde'
                                    : DateFormat('dd/MM/yyyy', 'es_DO').format(fromDate!),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await pickDate(toDate);
                                if (picked == null) return;
                                setSheetState(() {
                                  toDate = picked;
                                  if (fromDate != null && fromDate!.isAfter(picked)) {
                                    fromDate = picked;
                                  }
                                });
                              },
                              icon: const Icon(Icons.event_available_outlined),
                              label: Text(
                                toDate == null
                                    ? 'Hasta'
                                    : DateFormat('dd/MM/yyyy', 'es_DO').format(toDate!),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(
                                context,
                                const _HistorialFilterState.clear(),
                              );
                            },
                            child: const Text('Limpiar filtros'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(
                                context,
                                _HistorialFilterState(
                                  clientKey: clientKey,
                                  quoteTag: quoteTag,
                                  fromDate: fromDate,
                                  toDate: toDate,
                                ),
                              );
                            },
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Aplicar'),
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

    if (!mounted || result == null) return;
    setState(() {
      _selectedClientKey = result.clientKey;
      _selectedQuoteTag = result.quoteTag;
      _fromDate = result.fromDate;
      _toDate = result.toDate;
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedClientKey = null;
      _selectedQuoteTag = null;
      _fromDate = null;
      _toDate = null;
    });
  }

  String _clientLabelForKey(String key) {
    for (final option in _clientOptions) {
      if (option.key == key) return option.label;
    }
    return 'Cliente';
  }

  Widget _buildToolbar(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 860;
    final theme = Theme.of(context);

    final searchField = TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: 'Buscar por cliente, telefono, creador, nota, item, fecha o categoria',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: () => _searchCtrl.clear(),
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );

    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        FilledButton.tonalIcon(
          onPressed: _openFilters,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.tune_rounded),
              if (_activeFilterCount > 0)
                Positioned(
                  right: -8,
                  top: -7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$_activeFilterCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          label: const Text('Filtros'),
        ),
        if (_activeFilterCount > 0 || _searchQuery.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () {
              _searchCtrl.clear();
              _clearFilters();
            },
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Limpiar'),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isWide
              ? Row(
                  children: [
                    Expanded(flex: 3, child: searchField),
                    const SizedBox(width: 12),
                    Flexible(flex: 2, child: Align(alignment: Alignment.centerRight, child: actions)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [searchField, const SizedBox(height: 12), actions],
                ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(
                icon: Icons.format_list_bulleted_rounded,
                label: '${_visibleItems.length} cotizaciones',
              ),
              const _InfoPill(
                icon: Icons.vertical_align_top_rounded,
                label: 'Tus clientes primero',
              ),
              if (_selectedClientKey != null)
                InputChip(
                  avatar: const Icon(Icons.person_outline_rounded, size: 16),
                  label: Text(_clientLabelForKey(_selectedClientKey!)),
                  onDeleted: () => setState(() => _selectedClientKey = null),
                ),
              if (_selectedQuoteTag != null)
                InputChip(
                  avatar: const Icon(Icons.category_outlined, size: 16),
                  label: Text(_selectedQuoteTag!),
                  onDeleted: () => setState(() => _selectedQuoteTag = null),
                ),
              if (_fromDate != null || _toDate != null)
                InputChip(
                  avatar: const Icon(Icons.event_note_outlined, size: 16),
                  label: Text(
                    '${_fromDate == null ? 'Inicio' : DateFormat('dd/MM/yyyy', 'es_DO').format(_fromDate!)} - ${_toDate == null ? 'Hoy' : DateFormat('dd/MM/yyyy', 'es_DO').format(_toDate!)}',
                  ),
                  onDeleted: () => setState(() {
                    _fromDate = null;
                    _toDate = null;
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _viewDetail(CotizacionModel item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalle de cotización'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cliente: ${item.customerName}'),
                if ((item.customerPhone ?? '').trim().isNotEmpty)
                  Text('Teléfono: ${item.customerPhone}'),
                Text(
                  'Fecha: ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(item.createdAt)}',
                ),
                if ((item.createdByUserName ?? '').trim().isNotEmpty)
                  Text('Creada por: ${item.createdByUserName}'),
                if (item.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Nota: ${item.note}'),
                ],
                const Divider(height: 18),
                ...item.items.map(
                  (line) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${line.nombre} x${line.qty.toStringAsFixed(line.qty % 1 == 0 ? 0 : 2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(_money(line.total)),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 18),
                Row(
                  children: [
                    const Expanded(child: Text('Subtotal')),
                    Text(_money(item.subtotal)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ITBIS ${item.includeItbis ? '(18%)' : '(no aplicado)'}',
                      ),
                    ),
                    Text(_money(item.itbisAmount)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      _money(item.total),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = (widget.customerPhone ?? '').trim();
    final visibleItems = _visibleItems;

    return Scaffold(
      appBar: CustomAppBar(
        title: phone.isEmpty
            ? 'Historial cotizaciones'
            : 'Cotizaciones · $phone',
        fallbackRoute: Routes.cotizaciones,
        showLogo: false,
        showDepartmentLabel: false,
      ),
      body: Column(
        children: [
          _buildToolbar(context),
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  )
                : _items.isEmpty
                ? Center(
                    child: Text(
                      phone.isEmpty
                          ? 'No hay cotizaciones guardadas'
                          : 'Este cliente no tiene cotizaciones',
                    ),
                  )
                : visibleItems.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 42,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No encontramos cotizaciones con esos filtros.',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Prueba cambiando la busqueda o quitando algun filtro activo.',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                      itemCount: visibleItems.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = visibleItems[index];
                        final canEditOrDelete = _canEditOrDelete(item);
                        final quoteTags = _quoteTags(item).take(2).toList(growable: false);
                        final isOwnClient = _isOwnClient(item);
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      item.customerName,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    if (isOwnClient)
                                      _StatusBadge(
                                        icon: Icons.vertical_align_top_rounded,
                                        label: 'Mi cliente',
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.10),
                                        foregroundColor: Theme.of(context).colorScheme.primary,
                                      ),
                                    if ((item.createdByUserName ?? '').trim().isNotEmpty)
                                      _StatusBadge(
                                        icon: Icons.person_outline_rounded,
                                        label: item.createdByUserName!.trim(),
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .secondaryContainer
                                            .withValues(alpha: 0.55),
                                        foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  children: [
                                    _MiniInfo(label: DateFormat('dd/MM/yyyy · h:mm a', 'es_DO').format(item.createdAt)),
                                    _MiniInfo(label: 'Lineas ${item.items.length}'),
                                    _MiniInfo(label: 'Total ${_money(item.total)}'),
                                    if ((item.customerPhone ?? '').trim().isNotEmpty)
                                      _MiniInfo(label: item.customerPhone!.trim()),
                                  ],
                                ),
                                if (quoteTags.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final tag in quoteTags)
                                        Chip(
                                          avatar: const Icon(Icons.sell_outlined, size: 16),
                                          label: Text(tag),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                    ],
                                  ),
                                ],
                                if (item.note.trim().isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    item.note.trim(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _viewDetail(item),
                                      icon: const Icon(Icons.visibility_outlined),
                                      label: const Text('Ver'),
                                    ),
                                    if (widget.pickForEditor) ...[
                                      if (canEditOrDelete)
                                        OutlinedButton.icon(
                                          onPressed: () => Navigator.pop(
                                            context,
                                            CotizacionEditorPayload(
                                              source: item,
                                              duplicate: false,
                                            ),
                                          ),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: const Text('Editar'),
                                        ),
                                      OutlinedButton.icon(
                                        onPressed: () => Navigator.pop(
                                          context,
                                          CotizacionEditorPayload(
                                            source: item,
                                            duplicate: true,
                                          ),
                                        ),
                                        icon: const Icon(Icons.copy_all_outlined),
                                        label: const Text('Duplicar'),
                                      ),
                                      if (canEditOrDelete)
                                        OutlinedButton.icon(
                                          onPressed: () => _delete(item),
                                          icon: const Icon(Icons.delete_outline),
                                          label: const Text('Eliminar'),
                                        ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistorialFilterState {
  const _HistorialFilterState({
    required this.clientKey,
    required this.quoteTag,
    required this.fromDate,
    required this.toDate,
  });

  const _HistorialFilterState.clear()
      : clientKey = null,
        quoteTag = null,
        fromDate = null,
        toDate = null;

  final String? clientKey;
  final String? quoteTag;
  final DateTime? fromDate;
  final DateTime? toDate;
}

class _ClientFilterOption {
  const _ClientFilterOption({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.owned,
  });

  final String key;
  final String label;
  final String subtitle;
  final bool owned;
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
