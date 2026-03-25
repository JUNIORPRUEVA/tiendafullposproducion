import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/app_role.dart';
import '../../core/cache/fulltech_cache_manager.dart';
import '../../core/cache/local_json_cache.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/evolution/evolution_api_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/product_model.dart';
import '../../core/realtime/catalog_realtime_service.dart';
import '../../core/routing/app_route_observer.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/product_network_image.dart';
import '../clientes/cliente_model.dart';
import '../clientes/data/clientes_repository.dart';
import '../ventas/data/ventas_repository.dart';
import 'ai/application/quotation_ai_controller.dart';
import 'ai/domain/models/ai_warning.dart';
import 'ai/domain/models/quotation_context.dart';
import 'ai/presentation/widgets/ai_chat_sheet.dart';
import 'ai/presentation/widgets/ai_warning_banner.dart';
import 'ai/presentation/widgets/quotation_rule_detail_sheet.dart';
import 'cotizacion_models.dart';
import 'data/cotizacion_catalog_local_data_source.dart';
import 'data/cotizaciones_repository.dart';
import 'utils/cotizacion_pdf_service.dart';

class CotizacionesScreen extends ConsumerStatefulWidget {
  const CotizacionesScreen({
    super.key,
    this.initialClient,
    this.returnSavedQuotation = false,
  });

  final ClienteModel? initialClient;
  final bool returnSavedQuotation;

  @override
  ConsumerState<CotizacionesScreen> createState() => _CotizacionesScreenState();
}

class _CotizacionesScreenState extends ConsumerState<CotizacionesScreen>
    with WidgetsBindingObserver
    implements RouteAware {
  static const double _desktopBreakpoint = 900;
  static const String _editorDraftCachePrefix = 'cotizaciones:editorDraft:';

  final LocalJsonCache _editorDraftCache = LocalJsonCache();
  Timer? _persistEditorDraftTimer;
  bool _restoringEditorDraft = false;

  final TextEditingController _searchCtrl = TextEditingController();

  final List<CotizacionItem> _items = [];
  List<ProductModel> _productos = const [];

  bool _loadingProducts = false;
  String? _error;
  String? _selectedCategory;

  String? _selectedClientId;
  String _selectedClientName = 'Sin cliente';
  String? _selectedClientPhone;
  String _note = '';

  bool _includeItbis = false;
  static const double _itbisRate = 0.18;

  String? _editingId;
  DateTime? _editingCreatedAt;

  List<_DesktopTicketDraft> _desktopTickets = [];
  String? _activeDesktopTicketId;

  bool _prefillFromRouteApplied = false;
  bool _routeObserverSubscribed = false;
  RouteObserver<ModalRoute<dynamic>>? _routeObserver;
  bool _remoteRefreshInFlight = false;
  DateTime? _lastSuccessfulRemoteSyncAt;
  DateTime? _lastAutoSyncAt;
  Timer? _liveSyncTimer;
  StreamSubscription<CatalogRealtimeMessage>? _realtimeSubscription;
  static const Duration _liveSyncInterval = Duration(minutes: 2);
  static const Duration _silentRefreshMinInterval = Duration(seconds: 20);
  static const Duration _catalogCacheFreshFor = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    final initialDraft = _DesktopTicketDraft.empty(
      id: _newId(),
      title: 'Ticket 1',
    );
    _desktopTickets = [initialDraft];
    _activeDesktopTicketId = initialDraft.id;
    WidgetsBinding.instance.addObserver(this);
    _subscribeRealtime();
    _applyInitialClient();
    unawaited(_bootstrapCatalog());
    _startLiveSync();
    if (!widget.returnSavedQuotation) {
      unawaited(_restorePersistedEditorDraftIfAny());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_syncQuotationAi(triggerAi: false));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeRouteObserver();
    _scheduleAutoSync();

    if (widget.returnSavedQuotation) {
      return;
    }

    if (_prefillFromRouteApplied) return;
    _prefillFromRouteApplied = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyClientPrefillFromRoute();
    });
  }

  void _applyInitialClient() {
    final client = widget.initialClient;
    if (client == null) return;
    _selectedClientId = client.id;
    _selectedClientName = client.nombre;
    _selectedClientPhone = client.telefono;
  }

  void _subscribeRouteObserver() {
    if (_routeObserverSubscribed) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final observer = ref.read(appRouteObserverProvider);
    observer.subscribe(this, route);
    _routeObserver = observer;
    _routeObserverSubscribed = true;
  }

  void _subscribeRealtime() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = ref
        .read(catalogRealtimeServiceProvider)
        .stream
        .listen((_) => _loadProducts(forceRemote: true, silent: true));
  }

  void _startLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(_liveSyncInterval, (_) {
      if (!mounted) return;
      _loadProducts(forceRemote: true, silent: true);
    });
  }

  void _stopLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
  }

  void _scheduleAutoSync() {
    final now = DateTime.now();
    final last = _lastAutoSyncAt;
    if (last != null && now.difference(last).inMilliseconds < 1200) return;
    _lastAutoSyncAt = now;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadProducts(forceRemote: true, silent: true);
    });
  }

  void _syncProductsOnEnter() {
    if (!mounted) return;
    _loadProducts(forceRemote: true, silent: true);
  }

  @override
  void didPush() {
    _syncProductsOnEnter();
  }

  @override
  void didPopNext() {
    _syncProductsOnEnter();
  }

  @override
  void didPushNext() {}

  @override
  void didPop() {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _startLiveSync();
      _loadProducts(forceRemote: true, silent: true);
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopLiveSync();
    }
  }

  void _applyClientPrefillFromRoute({bool force = false}) {
    final qp = GoRouterState.of(context).uri.queryParameters;
    final id = (qp['customerId'] ?? '').trim();
    final name = (qp['customerName'] ?? '').trim();
    final phone = (qp['customerPhone'] ?? '').trim();

    if (id.isEmpty && name.isEmpty && phone.isEmpty) return;

    final hasSelection =
        (_selectedClientId ?? '').trim().isNotEmpty ||
        _selectedClientName.trim() != 'Sin cliente';
    if (hasSelection && !force) return;

    setState(() {
      if (force) {
        _selectedClientId = id.isEmpty ? null : id;
        _selectedClientName = name.isEmpty ? 'Sin cliente' : name;
        _selectedClientPhone = phone.isEmpty ? null : phone;
      } else {
        if (id.isNotEmpty) _selectedClientId = id;
        if (name.isNotEmpty) _selectedClientName = name;
        if (phone.isNotEmpty) _selectedClientPhone = phone;
      }
      _writeActiveDesktopDraft();
    });
    _schedulePersistEditorDraft();
    unawaited(_syncQuotationAi(triggerAi: false));

    if ((_selectedClientId ?? '').trim().isEmpty && phone.isNotEmpty) {
      _resolveClientIdByPhone(phone);
    }
  }

  Future<void> _resolveClientIdByPhone(String phone) async {
    try {
      final clients = await ref
          .read(ventasRepositoryProvider)
          .searchClients(phone);
      if (!mounted) return;

      ClienteModel? match;
      for (final c in clients) {
        if (c.telefono.trim() == phone.trim()) {
          match = c;
          break;
        }
      }
      match ??= clients.isEmpty ? null : clients.first;
      if (match == null) return;

      final matchId = match.id;
      final matchName = match.nombre;
      final matchPhone = match.telefono;

      setState(() {
        _selectedClientId = matchId;
        _selectedClientName = matchName;
        _selectedClientPhone = matchPhone;
        _writeActiveDesktopDraft();
      });
      _schedulePersistEditorDraft();
      unawaited(_syncQuotationAi(triggerAi: false));
    } catch (_) {
      // Silencioso: si no se puede resolver, el usuario puede escoger cliente.
    }
  }

  @override
  void dispose() {
    _persistEditorDraftTimer?.cancel();
    _persistEditorDraftTimer = null;
    unawaited(_persistEditorDraft());
    WidgetsBinding.instance.removeObserver(this);
    if (_routeObserverSubscribed) {
      _routeObserver?.unsubscribe(this);
      _routeObserverSubscribed = false;
      _routeObserver = null;
    }
    _stopLiveSync();
    _realtimeSubscription?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _editorDraftCacheKey() {
    final ownerId = (ref.read(authStateProvider).user?.id ?? 'anon').trim();
    return '$_editorDraftCachePrefix$ownerId';
  }

  void _schedulePersistEditorDraft({bool immediate = false}) {
    if (_restoringEditorDraft) return;
    _persistEditorDraftTimer?.cancel();
    _persistEditorDraftTimer = null;

    if (immediate) {
      unawaited(_persistEditorDraft());
      return;
    }

    _persistEditorDraftTimer = Timer(const Duration(milliseconds: 450), () {
      _persistEditorDraftTimer = null;
      unawaited(_persistEditorDraft());
    });
  }

  Future<void> _persistEditorDraft() async {
    if (!mounted) return;
    try {
      final map = <String, dynamic>{
        'v': 1,
        'activeId': _activeDesktopTicketId,
        'tickets': _desktopTickets.map((t) => t.toMap()).toList(),
      };
      await _editorDraftCache.writeMap(_editorDraftCacheKey(), map);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _restorePersistedEditorDraftIfAny() async {
    if (!mounted) return;
    _restoringEditorDraft = true;
    try {
      final cached = await _editorDraftCache.readMap(_editorDraftCacheKey());
      if (!mounted) return;
      if (cached == null) return;

      final rawTickets = (cached['tickets'] as List?) ?? const [];
      final tickets = rawTickets
          .whereType<Map>()
          .map(
            (row) => _DesktopTicketDraft.fromMap(row.cast<String, dynamic>()),
          )
          .toList();

      if (tickets.isEmpty) return;

      final cachedActive = (cached['activeId'] ?? '').toString().trim();
      final activeId = tickets.any((t) => t.id == cachedActive)
          ? cachedActive
          : tickets.first.id;
      final activeTicket = tickets.firstWhere((t) => t.id == activeId);

      setState(() {
        _desktopTickets = tickets;
        _activeDesktopTicketId = activeId;
        _replaceEditorStateFromDraft(activeTicket);
        _writeActiveDesktopDraft();
      });
      _applyClientPrefillFromRoute(force: true);
      unawaited(_syncQuotationAi(triggerAi: false));
    } catch (_) {
      // Ignore invalid cache entries.
    } finally {
      _restoringEditorDraft = false;
    }
  }

  Future<void> _loadProducts({
    bool forceRemote = false,
    bool silent = false,
  }) async {
    if (silent && forceRemote && _remoteRefreshInFlight) return;
    if (silent &&
        forceRemote &&
        _productos.isNotEmpty &&
        _lastSuccessfulRemoteSyncAt != null &&
        DateTime.now().difference(_lastSuccessfulRemoteSyncAt!) <
            _silentRefreshMinInterval) {
      return;
    }
    if (silent && forceRemote) {
      _remoteRefreshInFlight = true;
    }

    if (!silent) {
      setState(() {
        _loadingProducts = true;
        _error = null;
      });
    }

    try {
      final rows = await ref
          .read(ventasRepositoryProvider)
          .fetchProducts(forceRefresh: forceRemote);
      final catalogVersion = buildCatalogSyncVersion(rows);
      final cachedRows = applyCatalogSyncVersion(rows, catalogVersion);
      final syncedAt = DateTime.now();

      unawaited(
        ref
            .read(cotizacionCatalogLocalDataSourceProvider)
            .saveSnapshot(
              cachedRows,
              syncedAt: syncedAt,
              catalogVersion: catalogVersion,
            ),
      );

      if (!mounted) return;
      setState(() {
        _productos = cachedRows;
        _loadingProducts = false;
        _error = null;
      });
      unawaited(_syncQuotationAi(triggerAi: false));
      Future<void>.microtask(
        () => FulltechImageCacheManager.warmImageUrls(
          cachedRows.map((item) => item.displayFotoUrl),
        ),
      );
      _lastSuccessfulRemoteSyncAt = syncedAt;
    } catch (e) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _loadingProducts = false;
        _error = 'No se pudieron cargar productos: $e';
      });
    } finally {
      if (silent && forceRemote) {
        _remoteRefreshInFlight = false;
      }
    }
  }

  Future<void> _bootstrapCatalog() async {
    try {
      final localDataSource = ref.read(
        cotizacionCatalogLocalDataSourceProvider,
      );
      final cacheSnapshot = await localDataSource.readSnapshot();
      final uiState = await localDataSource.readUiState();
      if (!mounted) return;

      final hasCachedProducts = cacheSnapshot.items.isNotEmpty;
      setState(() {
        if (hasCachedProducts) {
          _productos = cacheSnapshot.items;
          _loadingProducts = false;
          _error = null;
        }
        if (_searchCtrl.text.trim().isEmpty &&
            uiState.searchQuery.trim().isNotEmpty) {
          _searchCtrl.text = uiState.searchQuery;
        }
        if (_selectedCategory == null &&
            (uiState.selectedCategory ?? '').trim().isNotEmpty) {
          _selectedCategory = uiState.selectedCategory;
        }
      });

      if (hasCachedProducts) {
        unawaited(_syncQuotationAi(triggerAi: false));
        Future<void>.microtask(
          () => FulltechImageCacheManager.warmImageUrls(
            cacheSnapshot.items.map((item) => item.displayFotoUrl),
          ),
        );
      }

      final shouldRefresh =
          !hasCachedProducts ||
          cacheSnapshot.lastSyncedAt == null ||
          DateTime.now().difference(cacheSnapshot.lastSyncedAt!) >
              _catalogCacheFreshFor;

      if (shouldRefresh) {
        unawaited(_loadProducts(forceRemote: true, silent: true));
      }
    } catch (_) {
      if (!mounted) return;
      unawaited(_loadProducts(forceRemote: true, silent: true));
    }
  }

  void _persistCatalogUiState() {
    unawaited(
      ref
          .read(cotizacionCatalogLocalDataSourceProvider)
          .saveUiState(
            selectedCategory: _selectedCategory,
            searchQuery: _searchCtrl.text,
          ),
    );
  }

  List<String> get _categories {
    final values = _productos
        .map((product) => product.categoriaLabel.trim())
        .where((label) => label.isNotEmpty)
        .toSet()
        .toList();
    values.sort((left, right) => left.compareTo(right));
    return values;
  }

  List<ProductModel> get _visibleProducts {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _productos.where((product) {
      if (_selectedCategory != null &&
          product.categoriaLabel != _selectedCategory) {
        return false;
      }
      if (query.isEmpty) return true;
      return product.nombre.toLowerCase().contains(query) ||
          product.categoriaLabel.toLowerCase().contains(query);
    }).toList();
  }

  double get _subtotal => _items.fold(0, (sum, item) => sum + item.total);
  double get _itbisAmount => _includeItbis ? (_subtotal * _itbisRate) : 0;
  double get _total => _subtotal + _itbisAmount;
  double get _totalCost => _items.fold(0, (sum, item) => sum + item.subtotalCost);
  double get _utilityAmount => _total - _totalCost;

  String _money(double value) =>
      NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value);

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  _DesktopTicketDraft _snapshotCurrentDesktopDraft({
    required String id,
    required String title,
  }) {
    return _DesktopTicketDraft(
      id: id,
      title: title,
      items: _items.map((item) => item.copyWith()).toList(),
      selectedClientId: _selectedClientId,
      selectedClientName: _selectedClientName,
      selectedClientPhone: _selectedClientPhone,
      note: _note,
      includeItbis: _includeItbis,
      editingId: _editingId,
      editingCreatedAt: _editingCreatedAt,
      selectedCategory: _selectedCategory,
      searchQuery: _searchCtrl.text,
    );
  }

  _DesktopTicketDraft? _findDesktopTicket(String? id) {
    if (id == null) return null;
    for (final ticket in _desktopTickets) {
      if (ticket.id == id) return ticket;
    }
    return null;
  }

  void _writeActiveDesktopDraft() {
    final activeId = _activeDesktopTicketId;
    if (activeId == null || _desktopTickets.isEmpty) return;
    final index = _desktopTickets.indexWhere((ticket) => ticket.id == activeId);
    if (index < 0) return;
    final current = _desktopTickets[index];
    _desktopTickets[index] = _snapshotCurrentDesktopDraft(
      id: current.id,
      title: current.title,
    );
  }

  void _replaceEditorStateFromDraft(_DesktopTicketDraft draft) {
    _items
      ..clear()
      ..addAll(draft.items.map((item) => item.copyWith()));
    _selectedClientId = draft.selectedClientId;
    _selectedClientName = draft.selectedClientName;
    _selectedClientPhone = draft.selectedClientPhone;
    _note = draft.note;
    _includeItbis = draft.includeItbis;
    _editingId = draft.editingId;
    _editingCreatedAt = draft.editingCreatedAt;
    _selectedCategory = draft.selectedCategory;
    _searchCtrl.text = draft.searchQuery;
  }

  void _resetEditorState() {
    _items.clear();
    _searchCtrl.clear();
    _selectedCategory = null;
    _selectedClientId = null;
    _selectedClientName = 'Sin cliente';
    _selectedClientPhone = null;
    _note = '';
    _includeItbis = false;
    _editingId = null;
    _editingCreatedAt = null;
  }

  void _commitEditorChange(VoidCallback changes) {
    setState(() {
      changes();
      _writeActiveDesktopDraft();
    });
    _schedulePersistEditorDraft();
    _persistCatalogUiState();
    unawaited(_syncQuotationAi());
  }

  String _nextDesktopTicketTitle() => 'Ticket ${_desktopTickets.length + 1}';

  void _createNewDesktopTicket() {
    setState(() {
      _writeActiveDesktopDraft();
      final ticket = _DesktopTicketDraft.empty(
        id: _newId(),
        title: _nextDesktopTicketTitle(),
      );
      _desktopTickets = [..._desktopTickets, ticket];
      _activeDesktopTicketId = ticket.id;
      _replaceEditorStateFromDraft(ticket);
      _writeActiveDesktopDraft();
    });
    _schedulePersistEditorDraft();
  }

  void _switchDesktopTicket(String id) {
    if (id == _activeDesktopTicketId) return;
    setState(() {
      _writeActiveDesktopDraft();
      final next = _findDesktopTicket(id);
      if (next == null) return;
      _activeDesktopTicketId = next.id;
      _replaceEditorStateFromDraft(next);
    });
    _schedulePersistEditorDraft();
    unawaited(_syncQuotationAi());
  }

  Future<void> _syncQuotationAi({bool triggerAi = true}) {
    return ref
        .read(quotationAiControllerProvider.notifier)
        .setContext(_buildQuotationAiContext(), triggerAi: triggerAi);
  }

  QuotationContext _buildQuotationAiContext() {
    final totalQuantity = _items.fold<double>(0, (sum, item) => sum + item.qty);
    final productName = _items.length == 1
        ? _items.first.nombre
        : _items.isNotEmpty
        ? '${_items.length} productos seleccionados'
        : null;

    final contextItems = _items
        .map((item) {
          final official = _findOfficialProduct(item.productId);
          return QuotationContextItem(
            productId: item.productId,
            productName: item.nombre,
            category:
                official?.categoriaLabel ??
                _selectedCategory ??
                'Sin categoría',
            qty: item.qty,
            unitPrice: item.unitPrice,
            officialUnitPrice: official?.precio,
            lineTotal: item.total,
            notes: _note.trim().isEmpty ? null : _note.trim(),
          );
        })
        .toList(growable: false);

    final normalPrice = contextItems.fold<double>(0, (sum, item) {
      return sum + ((item.officialUnitPrice ?? item.unitPrice) * item.qty);
    });

    return QuotationContext(
      quotationId: (_editingId ?? '').trim().isEmpty ? null : _editingId,
      module: 'cotizaciones',
      productType: _selectedCategory,
      productName: productName,
      brand: null,
      quantity: totalQuantity,
      installationType: _detectInstallationType(),
      selectedPriceType: _detectSelectedPriceType(contextItems),
      selectedUnitPrice: _items.length == 1 ? _items.first.unitPrice : null,
      selectedTotal: _total,
      minimumPrice: null,
      offerPrice: null,
      normalPrice: normalPrice,
      components: _items.map((item) => item.nombre).toList(growable: false),
      notes: _note.trim().isEmpty ? null : _note.trim(),
      extraCharges: _detectExtraCharges(),
      currentDvrType: _detectCurrentDvrType(),
      requiredDvrType: _detectRequiredDvrType(totalQuantity: totalQuantity),
      screenName: 'Cotización',
      items: contextItems,
      metadata: {
        'clientId': _selectedClientId,
        'clientName': _selectedClientName,
        'clientPhone': _selectedClientPhone,
        'includeItbis': _includeItbis,
        'subtotal': _subtotal,
        'itbisAmount': _itbisAmount,
        'activeDesktopTicketId': _activeDesktopTicketId,
      },
    );
  }

  ProductModel? _findOfficialProduct(String productId) {
    for (final product in _productos) {
      if (product.id == productId) return product;
    }
    return null;
  }

  String? _detectInstallationType() {
    final text = _note.toLowerCase();
    if (text.contains('complej')) return 'compleja';
    if (text.contains('simple')) return 'simple';
    return null;
  }

  String? _detectSelectedPriceType(List<QuotationContextItem> items) {
    if (items.isEmpty) return null;
    var hasDiscount = false;
    var hasIncrease = false;
    for (final item in items) {
      final official = item.officialUnitPrice;
      if (official == null) continue;
      if (item.unitPrice < official) hasDiscount = true;
      if (item.unitPrice > official) hasIncrease = true;
    }
    if (hasDiscount && !hasIncrease) return 'descuento';
    if (hasIncrease && !hasDiscount) return 'ajuste';
    if (!hasDiscount && !hasIncrease) return 'normal';
    return 'mixto';
  }

  List<String> _detectExtraCharges() {
    final charges = <String>[];
    for (final item in _items) {
      final text = item.nombre.toLowerCase();
      if (text.contains('instal') ||
          text.contains('recargo') ||
          text.contains('cargo')) {
        charges.add(item.nombre);
      }
    }
    return charges;
  }

  String? _detectCurrentDvrType() {
    final text = _items.map((item) => item.nombre).join(' ');
    final match = RegExp(
      r'(\d{1,2})\s*(canales|canal)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    return '${match.group(1)} canales';
  }

  String? _detectRequiredDvrType({required double totalQuantity}) {
    final totalCameras = _items
        .where((item) => item.nombre.toLowerCase().contains('camara'))
        .fold<double>(0, (sum, item) => sum + item.qty);
    if (totalCameras <= 0) return null;
    if (totalCameras <= 4) return '4 canales';
    if (totalCameras <= 8) return '8 canales';
    if (totalCameras <= 16) return '16 canales';
    if (totalQuantity > 16) return '32 canales';
    return null;
  }

  Future<void> _openAiAssistantSheet({String? initialPrompt}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiChatSheet(initialPrompt: initialPrompt),
    );
  }

  Future<void> _openAiRelatedRule(String? ruleId, String? title) {
    return openQuotationRuleDetailSheet(
      context,
      ref,
      ruleId: ruleId,
      title: title,
    );
  }

  Future<void> _askAiAboutWarning(AiWarning warning) {
    return _openAiAssistantSheet(
      initialPrompt:
          'Explícame la advertencia "${warning.title}" usando únicamente la regla oficial relacionada.',
    );
  }

  Future<_DiscountInput?> _openDiscountDialog({
    required String title,
    required String subtitle,
  }) async {
    final amountCtrl = TextEditingController();
    var type = _DiscountType.percent;

    final result = await showDialog<_DiscountInput>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subtitle),
                const SizedBox(height: 14),
                SegmentedButton<_DiscountType>(
                  segments: const [
                    ButtonSegment<_DiscountType>(
                      value: _DiscountType.percent,
                      label: Text('%'),
                      icon: Icon(Icons.percent),
                    ),
                    ButtonSegment<_DiscountType>(
                      value: _DiscountType.fixed,
                      label: Text('Monto'),
                      icon: Icon(Icons.attach_money),
                    ),
                  ],
                  selected: <_DiscountType>{type},
                  onSelectionChanged: (selection) {
                    setDialogState(() => type = selection.first);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: type == _DiscountType.percent
                        ? 'Porcentaje'
                        : 'Monto a descontar',
                    hintText: type == _DiscountType.percent ? '10' : '500',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(amountCtrl.text.trim());
                if (amount == null || amount <= 0) return;
                Navigator.pop(
                  dialogContext,
                  _DiscountInput(type: type, amount: amount),
                );
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );

    amountCtrl.dispose();
    return result;
  }

  Future<void> _applyItemDiscount(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    final input = await _openDiscountDialog(
      title: 'Descuento en ${item.nombre}',
      subtitle: 'Se ajustará el precio unitario de esta línea.',
    );
    if (input == null || !mounted) return;

    final currentTotal = item.total;
    final discountedTotal = input.type == _DiscountType.percent
        ? currentTotal * (1 - (input.amount / 100))
        : currentTotal - input.amount;
    final nextTotal = discountedTotal.clamp(0, currentTotal).toDouble();
    final nextUnitPrice = item.qty <= 0 ? 0.0 : nextTotal / item.qty;

    _commitEditorChange(() {
      _items[index] = item.copyWith(unitPrice: nextUnitPrice);
    });
  }

  Future<void> _applyGeneralDiscount() async {
    if (_items.isEmpty || _subtotal <= 0) return;
    final input = await _openDiscountDialog(
      title: 'Descuento general',
      subtitle: 'Se distribuirá proporcionalmente entre todas las líneas.',
    );
    if (input == null || !mounted) return;

    final rawFactor = input.type == _DiscountType.percent
        ? 1 - (input.amount / 100)
        : 1 - (input.amount / _subtotal);
    final factor = rawFactor.clamp(0, 1).toDouble();

    _commitEditorChange(() {
      for (var index = 0; index < _items.length; index++) {
        final item = _items[index];
        _items[index] = item.copyWith(unitPrice: item.unitPrice * factor);
      }
    });
  }

  void _addProduct(ProductModel product) {
    final index = _items.indexWhere((item) => item.productId == product.id);
    _commitEditorChange(() {
      if (index >= 0) {
        final current = _items[index];
        _items[index] = current.copyWith(qty: current.qty + 1);
      } else {
        _items.add(
          CotizacionItem(
            productId: product.id,
            nombre: product.nombre,
            imageUrl: product.displayFotoUrl,
            unitPrice: product.precio,
            qty: 1,
            costUnit: product.costo,
          ),
        );
      }
    });
  }

  Future<void> _openExternalItemDialog({int? editIndex}) async {
    final editingItem =
        editIndex != null &&
            editIndex >= 0 &&
            editIndex < _items.length &&
            _items[editIndex].isExternal
        ? _items[editIndex]
        : null;
    final nameCtrl = TextEditingController(text: editingItem?.nombre ?? '');
    final qtyCtrl = TextEditingController(
      text: editingItem == null
          ? '1'
          : (editingItem.qty % 1 == 0
                ? editingItem.qty.toStringAsFixed(0)
                : editingItem.qty.toStringAsFixed(2)),
    );
    final costCtrl = TextEditingController(
      text: editingItem?.externalCostUnit?.toStringAsFixed(2) ?? '',
    );
    final priceCtrl = TextEditingController(
      text: editingItem?.unitPrice.toStringAsFixed(2) ?? '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          editingItem == null
              ? 'Agregar producto fuera de inventario'
              : 'Editar producto fuera de inventario',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre producto o servicio',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Cantidad'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Costo unitario'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Precio unitario'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(editingItem == null ? 'Agregar' : 'Guardar'),
          ),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0;
    final externalCost = costCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(costCtrl.text.trim());
    final unitPrice = double.tryParse(priceCtrl.text.trim()) ?? -1;

    nameCtrl.dispose();
    qtyCtrl.dispose();
    costCtrl.dispose();
    priceCtrl.dispose();

    if (ok != true) return;

    if (name.isEmpty || qty <= 0 || unitPrice < 0 || (externalCost ?? 0) < 0) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Completa datos válidos: nombre, cantidad mayor que 0, costo y precio no negativos',
          ),
        ),
      );
      return;
    }

    _commitEditorChange(() {
      final next = CotizacionItem(
        productId: '',
        nombre: name,
        imageUrl: null,
        unitPrice: unitPrice,
        qty: qty,
        externalCostUnit: externalCost,
      );
      if (editingItem != null && editIndex != null) {
        _items[editIndex] = next;
      } else {
        _items.add(next);
      }
    });
  }

  void _setQty(int index, double qty) {
    if (qty <= 0) {
      _commitEditorChange(() => _items.removeAt(index));
      return;
    }
    _commitEditorChange(() => _items[index] = _items[index].copyWith(qty: qty));
  }

  void _setUnitPrice(int index, double price) {
    if (price < 0) return;
    _commitEditorChange(
      () => _items[index] = _items[index].copyWith(unitPrice: price),
    );
  }

  Future<void> _pickCategory() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final categories = _categories;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: Icon(
                  _selectedCategory == null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: const Text('Todas las categorías'),
                onTap: () => Navigator.pop(context, null),
              ),
              ...categories.map(
                (category) => ListTile(
                  leading: Icon(
                    _selectedCategory == category
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(category),
                  onTap: () => Navigator.pop(context, category),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected == _selectedCategory) return;
    _commitEditorChange(() => _selectedCategory = selected);
  }

  Future<void> _openNoteDialog() async {
    final controller = TextEditingController(text: _note);
    final nextNote = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nota de cotización'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Escribe una nota para esta cotización',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nextNote == null || !mounted) return;
    _commitEditorChange(() => _note = nextNote);
  }

  Future<void> _openClientDialog() async {
    final repo = ref.read(ventasRepositoryProvider);
    final clientesRepo = ref.read(clientesRepositoryProvider);
    final ownerId = (ref.read(authStateProvider).user?.id ?? '').trim();
    final searchCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    List<ClienteModel> clients = const [];
    bool loading = true;
    bool creating = false;
    bool editingCurrent = false;
    String? error;
    ClienteModel? currentClient;

    Future<void> loadCurrentClient() async {
      final currentId = (_selectedClientId ?? '').trim();
      if (currentId.isEmpty || ownerId.isEmpty) return;
      try {
        currentClient = await clientesRepo.getClientById(
          ownerId: ownerId,
          id: currentId,
        );
        nameCtrl.text = currentClient?.nombre ?? _selectedClientName;
        phoneCtrl.text =
            currentClient?.telefono ?? (_selectedClientPhone ?? '');
        addressCtrl.text = currentClient?.direccion ?? '';
        emailCtrl.text = currentClient?.correo ?? '';
      } catch (_) {
        currentClient = null;
      }
    }

    void fillCreateDefaults() {
      nameCtrl.text = _selectedClientName == 'Sin cliente'
          ? ''
          : _selectedClientName;
      phoneCtrl.text = _selectedClientPhone ?? '';
      addressCtrl.clear();
      emailCtrl.clear();
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          Future<void> loadClients() async {
            setStateDialog(() {
              loading = true;
              error = null;
            });
            try {
              clients = await repo.searchClients(searchCtrl.text.trim());
              if (!context.mounted) return;
              setStateDialog(() => loading = false);
            } catch (e) {
              if (!context.mounted) return;
              setStateDialog(() {
                loading = false;
                error = '$e';
              });
            }
          }

          if (loading && clients.isEmpty && error == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => loadClients());
          }

          return AlertDialog(
            title: const Text('Cliente'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!creating && !editingCurrent) ...[
                    TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Buscar cliente',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          onPressed: loadClients,
                          icon: const Icon(Icons.filter_alt_outlined),
                        ),
                        isDense: true,
                      ),
                      onSubmitted: (_) => loadClients(),
                    ),
                    const SizedBox(height: 10),
                    if (loading)
                      const LinearProgressIndicator()
                    else if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    else
                      SizedBox(
                        height: 280,
                        child: clients.isEmpty
                            ? const Center(
                                child: Text('No hay clientes, crea uno nuevo'),
                              )
                            : ListView.separated(
                                itemCount: clients.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final client = clients[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(client.nombre),
                                    subtitle: Text(
                                      client.telefono,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () {
                                      _commitEditorChange(() {
                                        _selectedClientId = client.id;
                                        _selectedClientName = client.nombre;
                                        _selectedClientPhone = client.telefono;
                                      });
                                      Navigator.pop(context);
                                    },
                                  );
                                },
                              ),
                      ),
                  ] else ...[
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: addressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Dirección',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo',
                        isDense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
              if (!creating && !editingCurrent)
                OutlinedButton.icon(
                  onPressed: () {
                    fillCreateDefaults();
                    setStateDialog(() => creating = true);
                  },
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Nuevo'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => setStateDialog(() {
                    creating = false;
                    editingCurrent = false;
                  }),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Lista'),
                ),
              if (!creating &&
                  !editingCurrent &&
                  (_selectedClientId ?? '').trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () async {
                    await loadCurrentClient();
                    if (!context.mounted) return;
                    setStateDialog(() => editingCurrent = true);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar actual'),
                ),
              if (creating || editingCurrent)
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final phone = phoneCtrl.text.trim();
                    if (name.isEmpty || phone.isEmpty) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text('Nombre y teléfono son obligatorios'),
                        ),
                      );
                      return;
                    }
                    try {
                      if (editingCurrent) {
                        if (ownerId.isEmpty || currentClient == null) return;
                        final updated = await clientesRepo.upsertClient(
                          ownerId: ownerId,
                          cliente: currentClient!.copyWith(
                            nombre: name,
                            telefono: phone,
                            direccion: addressCtrl.text.trim(),
                            correo: emailCtrl.text.trim(),
                            clearDireccion: addressCtrl.text.trim().isEmpty,
                            clearCorreo: emailCtrl.text.trim().isEmpty,
                          ),
                        );
                        if (!context.mounted) return;
                        _commitEditorChange(() {
                          _selectedClientId = updated.id;
                          _selectedClientName = updated.nombre;
                          _selectedClientPhone = updated.telefono;
                        });
                        Navigator.pop(context);
                        return;
                      }

                      final created = await repo.createQuickClient(
                        nombre: name,
                        telefono: phone,
                      );
                      if (!context.mounted) return;
                      _commitEditorChange(() {
                        _selectedClientId = created.id;
                        _selectedClientName = created.nombre;
                        _selectedClientPhone = created.telefono;
                      });
                      Navigator.pop(context);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(content: Text('No se pudo crear: $e')),
                      );
                    }
                  },
                  child: Text(
                    editingCurrent ? 'Guardar cambios' : 'Guardar cliente',
                  ),
                ),
            ],
          );
        },
      ),
    );

    searchCtrl.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    emailCtrl.dispose();
  }

  CotizacionModel _buildDraftCotizacion() {
    return CotizacionModel(
      id: _editingId ?? _newId(),
      createdAt: _editingCreatedAt ?? DateTime.now(),
      customerId: _selectedClientId,
      customerName: _selectedClientName,
      customerPhone: _selectedClientPhone,
      note: _note,
      includeItbis: _includeItbis,
      itbisRate: _itbisRate,
      items: [..._items],
    );
  }

  Future<void> _openPdfPreview() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega productos para generar PDF')),
      );
      return;
    }

    final scaffoldContext = context;

    final cotizacion = _buildDraftCotizacion();
    final company = await ref
        .read(companySettingsRepositoryProvider)
        .getSettings();
    final bytes = await buildCotizacionPdf(
      cotizacion: cotizacion,
      company: company,
    );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        var sendingWhatsApp = false;
        final media = MediaQuery.sizeOf(context);
        final compact = media.width < 560;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final phone = (cotizacion.customerPhone ?? '').trim();
            final evolution = ref.read(evolutionApiRepositoryProvider);
            final normalizedPhone = evolution.normalizeWhatsAppNumber(phone);
            final canSend = normalizedPhone.isNotEmpty && !sendingWhatsApp;

            String fileName() {
              final dateFmt = DateFormat('yyyyMMdd_HHmm');
              return 'cotizacion_${dateFmt.format(cotizacion.createdAt)}_${cotizacion.id.substring(0, 6)}.pdf';
            }

            String caption() {
              final name = cotizacion.customerName.trim();
              final safeName = name.isEmpty ? 'cliente' : name;
              return 'Señor(a) $safeName, aquí está el presupuesto. Por favor, hágame saber cualquier detalle.';
            }

            Future<void> sendWhatsApp() async {
              setDialogState(() => sendingWhatsApp = true);
              try {
                final cancelToken = CancelToken();
                await evolution
                    .sendPdfDocument(
                      toNumber: normalizedPhone,
                      bytes: bytes,
                      fileName: fileName(),
                      caption: caption(),
                      cancelToken: cancelToken,
                    )
                    .timeout(
                      const Duration(seconds: 25),
                      onTimeout: () {
                        cancelToken.cancel('timeout');
                        throw TimeoutException('timeout');
                      },
                    );
                if (!scaffoldContext.mounted) return;
                ScaffoldMessenger.maybeOf(scaffoldContext)?.showSnackBar(
                  const SnackBar(
                    content: Text('Cotización enviada vía WhatsApp.'),
                  ),
                );
              } on TimeoutException {
                if (!scaffoldContext.mounted) return;
                ScaffoldMessenger.maybeOf(scaffoldContext)?.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Tiempo de espera agotado enviando por WhatsApp (Evolution).',
                    ),
                  ),
                );
              } on ApiException catch (e) {
                if (!scaffoldContext.mounted) return;
                ScaffoldMessenger.maybeOf(scaffoldContext)?.showSnackBar(
                  SnackBar(
                    content: Text(
                      normalizedPhone.isEmpty
                          ? 'Teléfono inválido para WhatsApp.'
                          : e.message,
                    ),
                  ),
                );
              } catch (e) {
                if (!scaffoldContext.mounted) return;
                ScaffoldMessenger.maybeOf(scaffoldContext)?.showSnackBar(
                  SnackBar(content: Text('No se pudo enviar: $e')),
                );
              } finally {
                if (context.mounted) {
                  setDialogState(() => sendingWhatsApp = false);
                }
              }
            }

            return Dialog(
              insetPadding: EdgeInsets.all(compact ? 8 : 16),
              child: SizedBox(
                width: compact ? media.width - 16 : 900,
                height: compact ? media.height * 0.92 : 760,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
                      child: Row(
                        children: [
                          const Icon(Icons.picture_as_pdf_outlined),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'PDF de cotización',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: phone.isEmpty
                                ? null
                                : (canSend ? sendWhatsApp : null),
                            icon: sendingWhatsApp
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.chat_outlined),
                            label: Text(
                              compact
                                  ? 'WhatsApp'
                                  : 'Enviar cotización vía WhatsApp',
                            ),
                          ),
                          const SizedBox(width: 6),
                          TextButton.icon(
                            onPressed: () => shareCotizacionPdf(
                              bytes: bytes,
                              cotizacion: cotizacion,
                            ),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Descargar'),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: PdfPreview(
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        canDebug: false,
                        allowPrinting: true,
                        allowSharing: true,
                        build: (_) async => bytes,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openHistory() async {
    final payload = await context.push<CotizacionEditorPayload>(
      Routes.cotizacionesHistorial,
    );

    if (payload == null || !mounted) return;

    _commitEditorChange(() {
      _items
        ..clear()
        ..addAll(payload.source.items.map((item) => item.copyWith()));
      _selectedClientId = payload.source.customerId;
      _selectedClientName = payload.source.customerName;
      _selectedClientPhone = payload.source.customerPhone;
      _note = payload.source.note;
      _includeItbis = payload.source.includeItbis;
      _editingId = payload.duplicate ? null : payload.source.id;
      _editingCreatedAt = payload.duplicate ? null : payload.source.createdAt;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          payload.duplicate
              ? 'Cotización duplicada en editor'
              : 'Cotización cargada para editar',
        ),
      ),
    );
  }

  Future<void> _finalizeCotizacion() async {
    if (_selectedClientId == null || _selectedClientName == 'Sin cliente') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona o crea un cliente primero')),
      );
      return;
    }

    if ((_selectedClientPhone ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El cliente debe tener teléfono')),
      );
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un producto al ticket')),
      );
      return;
    }

    final wasEditing = (_editingId ?? '').trim().isNotEmpty;
    final cotizacion = _buildDraftCotizacion();
    CotizacionModel? savedQuotation;
    var queued = false;
    try {
      final repository = ref.read(cotizacionesRepositoryProvider);
      if (widget.returnSavedQuotation) {
        savedQuotation = (_editingId ?? '').trim().isEmpty
            ? await repository.create(cotizacion)
            : await repository.update(_editingId!, cotizacion);
      } else {
        queued = (_editingId ?? '').trim().isEmpty
            ? await repository.createOrQueue(cotizacion)
            : await repository.updateOrQueue(_editingId!, cotizacion);
      }

      if (!mounted) return;

      if (!widget.returnSavedQuotation) {
        _commitEditorChange(_resetEditorState);
        _schedulePersistEditorDraft(immediate: true);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.returnSavedQuotation
                ? wasEditing
                    ? 'Cotización actualizada'
                    : 'Cotización creada'
                : queued
                ? 'Cotización guardada localmente. Se sincronizará en segundo plano.'
                : wasEditing
                ? 'Cotización actualizada en nube'
                : 'Cotización guardada en nube',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
      return;
    }

    if (widget.returnSavedQuotation && mounted) {
      context.pop(savedQuotation);
      return;
    }

    final qp = GoRouterState.of(context).uri.queryParameters;
    final popOnSave = (qp['popOnSave'] ?? '').trim() == '1';
    if (popOnSave && mounted) {
      context.pop(true);
    }
  }

  AppBar _buildMobileAppBar() {
    return AppBar(
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => _commitEditorChange(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar producto',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: IconButton(
                      tooltip: 'Filtrar por categoría',
                      onPressed: _pickCategory,
                      icon: Icon(
                        _selectedCategory == null
                            ? Icons.filter_alt_outlined
                            : Icons.filter_alt,
                        size: 20,
                      ),
                    ),
                    isDense: true,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Agregar fuera de inventario',
              onPressed: _openExternalItemDialog,
              icon: const Icon(Icons.add_box_outlined),
            ),
            IconButton(
              tooltip: 'Cliente',
              onPressed: _openClientDialog,
              icon: const Icon(Icons.person_outline),
            ),
            IconButton(
              tooltip: 'Nota',
              onPressed: _openNoteDialog,
              icon: Icon(
                _note.trim().isEmpty
                    ? Icons.sticky_note_2_outlined
                    : Icons.sticky_note_2,
              ),
            ),
            IconButton(
              tooltip: 'PDF',
              onPressed: _openPdfPreview,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            IconButton(
              tooltip: 'Historial',
              onPressed: _openHistory,
              icon: const Icon(Icons.history),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildDesktopAppBar() {
    return AppBar(
      title: const Text('Cotizaciones'),
      actions: const [SizedBox(width: 8)],
    );
  }

  Widget _buildStatusChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        Chip(
          avatar: const Icon(Icons.person, size: 16),
          label: Text(_selectedClientName),
        ),
        if (_selectedCategory != null)
          Chip(
            avatar: const Icon(Icons.category_outlined, size: 16),
            label: Text(_selectedCategory!),
            onDeleted: () =>
                _commitEditorChange(() => _selectedCategory = null),
          ),
        if (_note.trim().isNotEmpty)
          Chip(
            avatar: const Icon(Icons.note_alt_outlined, size: 16),
            label: Text(_note, overflow: TextOverflow.ellipsis),
            onDeleted: () => _commitEditorChange(() => _note = ''),
          ),
      ],
    );
  }

  Widget _buildProductStrip() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _openExternalItemDialog,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Agregar fuera de inventario'),
            ),
          ),
        ),
        SizedBox(
          height: 116,
          child: _visibleProducts.isEmpty
              ? Center(
                  child: Text(
                    _searchCtrl.text.trim().isNotEmpty ||
                            _selectedCategory != null
                        ? 'No hay productos con este filtro'
                        : 'Agrega fuera de inventario o usa el catálogo cuando sincronice',
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _visibleProducts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final product = _visibleProducts[index];
                    return _ProductThumbCard(
                      product: product,
                      onTap: () => _addProduct(product),
                      money: _money,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTicketPanel() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _editingId == null
                        ? 'Ticket abierto · ${_items.length} líneas'
                        : 'Editando cotización · ${_items.length} líneas',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Agregar fuera de inventario',
                  onPressed: _openExternalItemDialog,
                  icon: const Icon(Icons.add_box_outlined),
                ),
                Text(
                  DateFormat('dd/MM h:mm a', 'es_DO').format(DateTime.now()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text(
                      'Toca un producto arriba para agregarlo',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    itemCount: _items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return _TicketCompactItem(
                        item: item,
                        money: _money,
                        onMinus: () => _setQty(index, item.qty - 1),
                        onPlus: () => _setQty(index, item.qty + 1),
                        onChangePrice: (value) => _setUnitPrice(index, value),
                        onEdit: item.isExternal
                            ? () => _openExternalItemDialog(editIndex: index)
                            : null,
                        onRemove: () =>
                            _commitEditorChange(() => _items.removeAt(index)),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Subtotal')),
                    Text(_money(_subtotal)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Text('Aplicar ITBIS'),
                          const SizedBox(width: 6),
                          Switch.adaptive(
                            value: _includeItbis,
                            onChanged: (value) => _commitEditorChange(
                              () => _includeItbis = value,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(_money(_itbisAmount)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total cotización',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      _money(_total),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                if (ref.watch(authStateProvider).user?.appRole == AppRole.admin)
                  ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Utilidad total',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.green,
                            ),
                          ),
                        ),
                        Text(
                          _money(_utilityAmount),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _items.isEmpty
                            ? null
                            : () {
                                _commitEditorChange(() {
                                  _items.clear();
                                  _editingId = null;
                                  _editingCreatedAt = null;
                                });
                              },
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Limpiar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _finalizeCotizacion,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Finalizar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBody(QuotationAiState aiState) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: _buildStatusChips(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: AiWarningBanner(
            warnings: aiState.visibleWarnings,
            analyzing: aiState.analyzing || aiState.loadingRules,
            onOpenRule: (warning) => _openAiRelatedRule(
              warning.relatedRuleId,
              warning.relatedRuleTitle,
            ),
            onAskAi: _askAiAboutWarning,
          ),
        ),
        _buildProductStrip(),
        const SizedBox(height: 8),
        Expanded(child: _buildTicketPanel()),
      ],
    );
  }

  Widget _buildDesktopBody(QuotationAiState aiState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        children: [
          AiWarningBanner(
            warnings: aiState.visibleWarnings,
            analyzing: aiState.analyzing || aiState.loadingRules,
            onOpenRule: (warning) => _openAiRelatedRule(
              warning.relatedRuleId,
              warning.relatedRuleTitle,
            ),
            onAskAi: _askAiAboutWarning,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 7,
                  child: _DesktopCatalogPane(
                    searchController: _searchCtrl,
                    selectedCategory: _selectedCategory,
                    visibleProducts: _visibleProducts,
                    loadingProducts: _loadingProducts,
                    error: _error,
                    money: _money,
                    onSearchChanged: () => _commitEditorChange(() {}),
                    onPickCategory: _pickCategory,
                    onAddProduct: _addProduct,
                    onAddExternalItem: _openExternalItemDialog,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 3,
                  child: _DesktopQuotePanel(
                    tickets: _desktopTickets,
                    activeTicketId: _activeDesktopTicketId,
                    editingId: _editingId,
                    items: _items,
                    selectedClientName: _selectedClientName,
                    note: _note,
                    includeItbis: _includeItbis,
                    subtotal: _subtotal,
                    itbisAmount: _itbisAmount,
                    total: _total,
                    money: _money,
                    onPickClient: _openClientDialog,
                    onEditNote: _openNoteDialog,
                    onOpenPdf: _openPdfPreview,
                    onOpenHistory: _openHistory,
                    onCreateTicket: _createNewDesktopTicket,
                    onSwitchTicket: _switchDesktopTicket,
                    onAddExternalItem: _openExternalItemDialog,
                    onToggleItbis: (value) =>
                        _commitEditorChange(() => _includeItbis = value),
                    onClear: _items.isEmpty
                        ? null
                        : () {
                            _commitEditorChange(_resetEditorState);
                          },
                    onFinalize: _finalizeCotizacion,
                    onMinusQty: (index) =>
                        _setQty(index, _items[index].qty - 1),
                    onPlusQty: (index) => _setQty(index, _items[index].qty + 1),
                    onChangePrice: _setUnitPrice,
                    onDiscountItem: _applyItemDiscount,
                    onGeneralDiscount: _applyGeneralDiscount,
                    onEditExternalItem: (index) =>
                        _openExternalItemDialog(editIndex: index),
                    onRemoveItem: (index) =>
                        _commitEditorChange(() => _items.removeAt(index)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final aiState = ref.watch(quotationAiControllerProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    return Scaffold(
      appBar: isDesktop ? _buildDesktopAppBar() : _buildMobileAppBar(),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: SafeArea(
        child: isDesktop
            ? _buildDesktopBody(aiState)
            : _buildMobileBody(aiState),
      ),
    );
  }
}

class _ProductThumbCard extends StatelessWidget {
  const _ProductThumbCard({
    required this.product,
    required this.onTap,
    required this.money,
  });

  final ProductModel product;
  final VoidCallback onTap;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Material(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  child: (product.displayFotoUrl ?? '').trim().isEmpty
                      ? const Icon(Icons.inventory_2_outlined, size: 17)
                      : ClipOval(
                          child: ProductNetworkImage(
                            imageUrl: product.displayFotoUrl!,
                            productId: product.id,
                            productName: product.nombre,
                            originalUrl: product.originalFotoUrl,
                            fit: BoxFit.cover,
                            loading: Container(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  size: 17,
                                ),
                              ),
                            ),
                            fallback: Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 18,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 5),
                Text(
                  product.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  product.categoriaLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontSize: 10),
                ),
                Text(
                  money(product.precio),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopCatalogPane extends StatefulWidget {
  const _DesktopCatalogPane({
    required this.searchController,
    required this.selectedCategory,
    required this.visibleProducts,
    required this.loadingProducts,
    required this.error,
    required this.money,
    required this.onSearchChanged,
    required this.onPickCategory,
    required this.onAddProduct,
    required this.onAddExternalItem,
  });

  final TextEditingController searchController;
  final String? selectedCategory;
  final List<ProductModel> visibleProducts;
  final bool loadingProducts;
  final String? error;
  final String Function(double) money;
  final VoidCallback onSearchChanged;
  final Future<void> Function() onPickCategory;
  final ValueChanged<ProductModel> onAddProduct;
  final Future<void> Function({int? editIndex}) onAddExternalItem;

  @override
  State<_DesktopCatalogPane> createState() => _DesktopCatalogPaneState();
}

class _DesktopCatalogPaneState extends State<_DesktopCatalogPane> {
  late final ScrollController _gridScrollController;

  @override
  void initState() {
    super.initState();
    _gridScrollController = ScrollController();
  }

  @override
  void dispose() {
    _gridScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.surfaceContainerLowest,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.searchController,
                    onChanged: (_) => widget.onSearchChanged(),
                    decoration: InputDecoration(
                      hintText: 'Buscar producto',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Filtrar categoría',
                            onPressed: widget.onPickCategory,
                            icon: Icon(
                              widget.selectedCategory == null
                                  ? Icons.filter_alt_outlined
                                  : Icons.filter_alt,
                            ),
                          ),
                          if (widget.searchController.text.trim().isNotEmpty)
                            IconButton(
                              tooltip: 'Limpiar búsqueda',
                              onPressed: () {
                                widget.searchController.clear();
                                widget.onSearchChanged();
                              },
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: widget.onPickCategory,
                  icon: Icon(
                    widget.selectedCategory == null
                        ? Icons.tune_outlined
                        : Icons.filter_alt,
                  ),
                  label: Text(
                    widget.selectedCategory == null
                        ? 'Categorías'
                        : widget.selectedCategory!,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => widget.onAddExternalItem(),
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Fuera inventario'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: widget.visibleProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.playlist_add_circle_outlined,
                            size: 54,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.searchController.text.trim().isNotEmpty ||
                                    widget.selectedCategory != null
                                ? 'No hay productos con este filtro'
                                : 'La pantalla abre al instante y el catálogo se sincroniza en segundo plano',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final columns = width >= 1500
                            ? 6
                            : width >= 1180
                            ? 5
                            : width >= 900
                            ? 4
                            : 3;
                        final spacing = width >= 1180 ? 14.0 : 12.0;
                        final cardWidth =
                            (width - spacing * (columns - 1)) / columns;
                        final cardHeight = (cardWidth * 0.82).clamp(
                          160.0,
                          205.0,
                        );

                        return Scrollbar(
                          controller: _gridScrollController,
                          thumbVisibility: true,
                          interactive: true,
                          child: GridView.builder(
                            controller: _gridScrollController,
                            primary: false,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: spacing,
                                  mainAxisSpacing: spacing,
                                  mainAxisExtent: cardHeight,
                                ),
                            itemCount: widget.visibleProducts.length,
                            itemBuilder: (context, index) {
                              final product = widget.visibleProducts[index];
                              return _DesktopProductCard(
                                product: product,
                                money: widget.money,
                                onTap: () => widget.onAddProduct(product),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopQuotePanel extends StatelessWidget {
  const _DesktopQuotePanel({
    required this.tickets,
    required this.activeTicketId,
    required this.editingId,
    required this.items,
    required this.selectedClientName,
    required this.note,
    required this.includeItbis,
    required this.subtotal,
    required this.itbisAmount,
    required this.total,
    required this.money,
    required this.onPickClient,
    required this.onEditNote,
    required this.onOpenPdf,
    required this.onOpenHistory,
    required this.onCreateTicket,
    required this.onSwitchTicket,
    required this.onAddExternalItem,
    required this.onToggleItbis,
    required this.onClear,
    required this.onFinalize,
    required this.onMinusQty,
    required this.onPlusQty,
    required this.onChangePrice,
    required this.onDiscountItem,
    required this.onGeneralDiscount,
    required this.onEditExternalItem,
    required this.onRemoveItem,
  });

  final List<_DesktopTicketDraft> tickets;
  final String? activeTicketId;
  final String? editingId;
  final List<CotizacionItem> items;
  final String selectedClientName;
  final String note;
  final bool includeItbis;
  final double subtotal;
  final double itbisAmount;
  final double total;
  final String Function(double) money;
  final VoidCallback onPickClient;
  final VoidCallback onEditNote;
  final VoidCallback onOpenPdf;
  final VoidCallback onOpenHistory;
  final VoidCallback onCreateTicket;
  final ValueChanged<String> onSwitchTicket;
  final VoidCallback onAddExternalItem;
  final ValueChanged<bool> onToggleItbis;
  final VoidCallback? onClear;
  final VoidCallback onFinalize;
  final ValueChanged<int> onMinusQty;
  final ValueChanged<int> onPlusQty;
  final void Function(int index, double value) onChangePrice;
  final ValueChanged<int> onDiscountItem;
  final VoidCallback onGeneralDiscount;
  final ValueChanged<int> onEditExternalItem;
  final ValueChanged<int> onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeIndex = tickets.indexWhere(
      (ticket) => ticket.id == activeTicketId,
    );
    final activeLabel = activeIndex >= 0
        ? tickets[activeIndex].label(activeIndex)
        : 'Ticket';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PopupMenuButton<String>(
                  tooltip: 'Cambiar ticket',
                  onSelected: onSwitchTicket,
                  itemBuilder: (context) {
                    return [
                      for (var index = 0; index < tickets.length; index++)
                        PopupMenuItem<String>(
                          value: tickets[index].id,
                          child: Text(tickets[index].label(index)),
                        ),
                    ];
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          activeLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Nuevo ticket',
                  onPressed: onCreateTicket,
                  icon: const Icon(Icons.add_circle_outline),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    selectedClientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cliente',
                  onPressed: onPickClient,
                  icon: const Icon(Icons.person_outline),
                ),
                IconButton(
                  tooltip: 'Agregar fuera de inventario',
                  onPressed: onAddExternalItem,
                  icon: const Icon(Icons.add_box_outlined),
                ),
                IconButton(
                  tooltip: note.trim().isEmpty ? 'Agregar nota' : 'Editar nota',
                  onPressed: onEditNote,
                  icon: Icon(
                    note.trim().isEmpty
                        ? Icons.sticky_note_2_outlined
                        : Icons.sticky_note_2,
                  ),
                ),
                IconButton(
                  tooltip: 'PDF',
                  onPressed: onOpenPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
                IconButton(
                  tooltip: 'Historial',
                  onPressed: onOpenHistory,
                  icon: const Icon(Icons.history),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              editingId == null
                  ? '${items.length} productos agregados'
                  : 'Editando cotización · ${items.length} productos',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_shopping_cart_outlined,
                            size: 56,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Haz clic en un producto del catálogo para agregarlo',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _DesktopTicketItem(
                          item: item,
                          money: money,
                          onTap: () => onDiscountItem(index),
                          onMinus: () => onMinusQty(index),
                          onPlus: () => onPlusQty(index),
                          onChangePrice: (value) => onChangePrice(index, value),
                          onEdit: item.isExternal
                              ? () => onEditExternalItem(index)
                              : null,
                          onRemove: () => onRemoveItem(index),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.55,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _DesktopTotalRow(label: 'Subtotal', value: money(subtotal)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Aplicar ITBIS'),
                            const SizedBox(height: 2),
                            Text(
                              'Calcula impuestos automáticamente',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: includeItbis,
                        onChanged: onToggleItbis,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _DesktopTotalRow(label: 'ITBIS', value: money(itbisAmount)),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  _DesktopTotalRow(
                    label: 'Total',
                    value: money(total),
                    emphasize: true,
                    hint: 'Doble clic para descuento general',
                    onDoubleTap: onGeneralDiscount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Limpiar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onFinalize,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Finalizar'),
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

class _DesktopProductCard extends StatelessWidget {
  const _DesktopProductCard({
    required this.product,
    required this.money,
    required this.onTap,
  });

  final ProductModel product;
  final String Function(double) money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        (product.displayFotoUrl ?? '').trim().isEmpty
                            ? Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: const Center(
                                  child: Icon(
                                    Icons.inventory_2_outlined,
                                    size: 34,
                                  ),
                                ),
                              )
                            : ProductNetworkImage(
                                imageUrl: product.displayFotoUrl!,
                                productId: product.id,
                                productName: product.nombre,
                                originalUrl: product.originalFotoUrl,
                                fit: BoxFit.cover,
                                loading: Container(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: const Center(
                                    child: Icon(
                                      Icons.inventory_2_outlined,
                                      size: 30,
                                    ),
                                  ),
                                ),
                                fallback: Container(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      size: 30,
                                    ),
                                  ),
                                ),
                              ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x05000000), Color(0x5E000000)],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.58),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              money(product.precio),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product.categoriaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
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

class _DesktopTotalRow extends StatelessWidget {
  const _DesktopTotalRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.hint,
    this.onDoubleTap,
  });

  final String label;
  final String value;
  final bool emphasize;
  final String? hint;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)
        : Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700);

    return GestureDetector(
      onDoubleTap: onDoubleTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: style),
                if ((hint ?? '').trim().isNotEmpty)
                  Text(
                    hint!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _DesktopTicketItem extends StatefulWidget {
  const _DesktopTicketItem({
    required this.item,
    required this.money,
    required this.onTap,
    required this.onMinus,
    required this.onPlus,
    required this.onChangePrice,
    required this.onEdit,
    required this.onRemove,
  });

  final CotizacionItem item;
  final String Function(double) money;
  final VoidCallback onTap;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<double> onChangePrice;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  @override
  State<_DesktopTicketItem> createState() => _DesktopTicketItemState();
}

class _DesktopTicketItemState extends State<_DesktopTicketItem> {
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: widget.item.unitPrice.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant _DesktopTicketItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.unitPrice != widget.item.unitPrice) {
      _priceCtrl.text = widget.item.unitPrice.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final qtyText = item.qty % 1 == 0
        ? item.qty.toStringAsFixed(0)
        : item.qty.toStringAsFixed(2);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: item.isExternal
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.isExternal
                  ? theme.colorScheme.primary.withValues(alpha: 0.45)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: (item.imageUrl ?? '').trim().isEmpty
                      ? Container(
                          color: item.isExternal
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            item.isExternal
                                ? Icons.edit_note_outlined
                                : Icons.inventory_2_outlined,
                            size: 15,
                            color: item.isExternal
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        )
                      : ProductNetworkImage(
                          imageUrl: item.imageUrl!,
                          productId: item.productId,
                          productName: item.nombre,
                          originalUrl: item.imageUrl,
                          fit: BoxFit.cover,
                          loading: Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          fallback: Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              size: 14,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    if (item.isExternal)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Manual',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(fontSize: 11),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Precio',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  onTap: () {},
                  onSubmitted: (value) {
                    final parsed = double.tryParse(value.trim());
                    if (parsed != null) widget.onChangePrice(parsed);
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Restar unidad',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onMinus,
                icon: const Icon(Icons.remove, size: 16),
              ),
              SizedBox(
                width: 24,
                child: Text(
                  qtyText,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sumar unidad',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onPlus,
                icon: const Icon(Icons.add, size: 16),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 96,
                child: Text(
                  widget.money(item.total),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              if (widget.onEdit != null)
                IconButton(
                  tooltip: 'Editar producto manual',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                ),
              IconButton(
                tooltip: 'Eliminar producto',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopTicketDraft {
  const _DesktopTicketDraft({
    required this.id,
    required this.title,
    required this.items,
    required this.selectedClientId,
    required this.selectedClientName,
    required this.selectedClientPhone,
    required this.note,
    required this.includeItbis,
    required this.editingId,
    required this.editingCreatedAt,
    required this.selectedCategory,
    required this.searchQuery,
  });

  factory _DesktopTicketDraft.empty({
    required String id,
    required String title,
  }) {
    return _DesktopTicketDraft(
      id: id,
      title: title,
      items: const [],
      selectedClientId: null,
      selectedClientName: 'Sin cliente',
      selectedClientPhone: null,
      note: '',
      includeItbis: false,
      editingId: null,
      editingCreatedAt: null,
      selectedCategory: null,
      searchQuery: '',
    );
  }

  final String id;
  final String title;
  final List<CotizacionItem> items;
  final String? selectedClientId;
  final String selectedClientName;
  final String? selectedClientPhone;
  final String note;
  final bool includeItbis;
  final String? editingId;
  final DateTime? editingCreatedAt;
  final String? selectedCategory;
  final String searchQuery;

  String label(int index) {
    final client = selectedClientName.trim();
    if (client.isNotEmpty && client != 'Sin cliente') return client;
    return title.isEmpty ? 'Ticket ${index + 1}' : title;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'items': items.map((item) => item.toMap()).toList(),
    'selectedClientId': selectedClientId,
    'selectedClientName': selectedClientName,
    'selectedClientPhone': selectedClientPhone,
    'note': note,
    'includeItbis': includeItbis,
    'editingId': editingId,
    'editingCreatedAt': editingCreatedAt?.toIso8601String(),
    'selectedCategory': selectedCategory,
    'searchQuery': searchQuery,
  };

  factory _DesktopTicketDraft.fromMap(Map<String, dynamic> map) {
    final rawItems = (map['items'] as List?) ?? const [];
    return _DesktopTicketDraft(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      items: rawItems
          .whereType<Map>()
          .map((row) => CotizacionItem.fromMap(row.cast<String, dynamic>()))
          .toList(growable: false),
      selectedClientId: map['selectedClientId']?.toString(),
      selectedClientName: (map['selectedClientName'] ?? 'Sin cliente')
          .toString(),
      selectedClientPhone: map['selectedClientPhone']?.toString(),
      note: (map['note'] ?? '').toString(),
      includeItbis: map['includeItbis'] == true,
      editingId: map['editingId']?.toString(),
      editingCreatedAt: DateTime.tryParse(
        (map['editingCreatedAt'] ?? '').toString(),
      ),
      selectedCategory: map['selectedCategory']?.toString(),
      searchQuery: (map['searchQuery'] ?? '').toString(),
    );
  }
}

enum _DiscountType { percent, fixed }

class _DiscountInput {
  const _DiscountInput({required this.type, required this.amount});

  final _DiscountType type;
  final double amount;
}

class _TicketCompactItem extends StatefulWidget {
  const _TicketCompactItem({
    required this.item,
    required this.money,
    required this.onMinus,
    required this.onPlus,
    required this.onChangePrice,
    required this.onEdit,
    required this.onRemove,
  });

  final CotizacionItem item;
  final String Function(double) money;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<double> onChangePrice;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  @override
  State<_TicketCompactItem> createState() => _TicketCompactItemState();
}

class _TicketCompactItemState extends State<_TicketCompactItem> {
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: widget.item.unitPrice.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant _TicketCompactItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.unitPrice != widget.item.unitPrice) {
      _priceCtrl.text = widget.item.unitPrice.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final qtyText = item.qty % 1 == 0
        ? item.qty.toStringAsFixed(0)
        : item.qty.toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: item.isExternal
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.30)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.isExternal
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.45)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
                if (item.isExternal)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Manual',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 86,
            child: TextField(
              controller: _priceCtrl,
              style: const TextStyle(fontSize: 11),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Precio',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                final next = double.tryParse(value.trim());
                if (next != null) widget.onChangePrice(next);
              },
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
            splashRadius: 14,
            onPressed: widget.onMinus,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
          ),
          Text(
            qtyText,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
            splashRadius: 14,
            onPressed: widget.onPlus,
            icon: const Icon(Icons.add_circle_outline, size: 18),
          ),
          const SizedBox(width: 6),
          if (widget.onEdit != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
              splashRadius: 14,
              tooltip: 'Editar producto manual',
              onPressed: widget.onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
            ),
          Text(
            widget.money(item.total),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
            splashRadius: 14,
            onPressed: widget.onRemove,
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }
}
