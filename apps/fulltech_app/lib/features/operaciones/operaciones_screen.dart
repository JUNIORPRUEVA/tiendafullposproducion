import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' hide ServiceStatus;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/user_model.dart';
import '../../core/models/punch_model.dart';
import '../../core/routing/routes.dart';
import '../../core/storage/storage_repository.dart';
import '../../core/storage/storage_models.dart';
import '../../core/utils/geo_utils.dart';
import '../../core/utils/external_launcher.dart';
import '../../core/utils/local_file_image.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/utils/string_utils.dart';
import '../../core/utils/video_preview_controller.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/local_file_image.dart';
import '../../modules/cotizaciones/data/cotizaciones_repository.dart';
import '../../modules/cotizaciones/cotizacion_models.dart';
import '../catalogo/catalogo_screen.dart';
import 'presentation/operations_back_button.dart';
import 'presentation/operations_compact_filter_panel.dart';
import '../ponche/application/punch_controller.dart';
import '../user/data/users_repository.dart';
import 'application/operations_controller.dart';
import 'application/operations_metadata_providers.dart';
import 'data/operations_repository.dart';
import 'operations_models.dart' hide ServiceStatus;
import 'operations_models.dart' as ops show ServiceStatus, parseStatus;
import 'presentation/service_agenda_card.dart';
import 'presentation/create_order_form_ui.dart';
import 'presentation/full_screen_image_viewer.dart';
import 'presentation/operations_filters.dart';
import 'presentation/operations_mobile_widgets.dart';
import 'presentation/operations_permissions.dart';
import 'presentation/service_actions_sheet.dart';
import 'presentation/service_location_helpers.dart';
import 'presentation/map_preview.dart';
import 'presentation/service_order_detail_widgets.dart';
import 'presentation/service_pdf_exporter.dart';
import 'presentation/status_picker_sheet.dart';
import 'tecnico/application/tech_operations_controller.dart';
import 'tecnico/widgets/service_report_pdf_screen.dart';
import '../../modules/clientes/cliente_model.dart';

class _EditableServiceAddressData {
  final String addressLine;
  final String gpsText;

  const _EditableServiceAddressData({
    required this.addressLine,
    required this.gpsText,
  });
}

_EditableServiceAddressData _extractEditableServiceAddress(
  String rawAddressText,
) {
  var addressLine = '';
  var gpsLine = '';
  var mapsLine = '';

  for (final line in rawAddressText.split('\n')) {
    final value = line.trim();
    if (value.isEmpty) continue;
    final lower = value.toLowerCase();
    if (lower.startsWith('gps:')) {
      gpsLine = value.substring(4).trim();
      continue;
    }
    if (lower.startsWith('maps:')) {
      mapsLine = value.substring(5).trim();
      continue;
    }
    if (addressLine.isEmpty) {
      addressLine = value;
    }
  }

  return _EditableServiceAddressData(
    addressLine: addressLine,
    gpsText: gpsLine.isNotEmpty ? gpsLine : mapsLine,
  );
}

String? _buildEditableServiceAddressSnapshot({
  required String addressLine,
  required String gpsText,
}) {
  final address = addressLine.trim();
  final gps = gpsText.trim();
  if (address.isEmpty && gps.isEmpty) return null;

  final point = parseLatLngFromText(gps);
  if (point != null) {
    final lines = <String>[];
    if (address.isNotEmpty) lines.add(address);
    lines.add('GPS: ${formatLatLng(point)}');
    lines.add('MAPS: ${buildGoogleMapsSearchUrl(point)}');
    return lines.join('\n');
  }

  final isUrl = RegExp(r'https?://', caseSensitive: false).hasMatch(gps);
  final lines = <String>[];
  if (address.isNotEmpty) lines.add(address);
  if (gps.isNotEmpty) {
    lines.add(isUrl ? 'MAPS: $gps' : 'GPS: $gps');
  }
  return lines.join('\n');
}

bool _isDesktopPlatform() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

const _agendaKindOptions = <String>[
  'reserva',
  'instalacion',
  'mantenimiento',
  'garantia',
  'levantamiento',
];

String _normalizeAgendaKindValue(
  String? rawValue, {
  String fallback = 'mantenimiento',
}) {
  final normalized = (rawValue ?? '').trim().toLowerCase();
  if (_agendaKindOptions.contains(normalized)) return normalized;
  return fallback;
}

String _agendaKindLabel(String? rawValue) {
  return switch (_normalizeAgendaKindValue(rawValue)) {
    'reserva' => 'Reserva',
    'instalacion' => 'Instalación',
    'garantia' => 'Garantía',
    'levantamiento' => 'Levantamiento',
    _ => 'Mantenimiento',
  };
}

String _serviceTypeForAgendaKind(
  String? rawValue, {
  String fallback = 'maintenance',
}) {
  return switch (_normalizeAgendaKindValue(rawValue, fallback: fallback)) {
    'instalacion' => 'installation',
    'garantia' => 'warranty',
    'levantamiento' => fallback,
    'reserva' => fallback,
    _ => 'maintenance',
  };
}

String _effectiveServiceKindLabel(ServiceModel service) {
  final orderType = _normalizeAgendaKindValue(
    service.orderType,
    fallback: service.orderType.trim().toLowerCase().isEmpty
        ? 'mantenimiento'
        : service.orderType.trim().toLowerCase(),
  );
  if (_agendaKindOptions.contains(orderType)) {
    return _agendaKindLabel(orderType);
  }

  final phase = service.currentPhase.trim().toLowerCase();
  if (_agendaKindOptions.contains(phase)) {
    return _agendaKindLabel(phase);
  }

  switch (service.serviceType.trim().toLowerCase()) {
    case 'installation':
      return 'Instalación';
    case 'warranty':
      return 'Garantía';
    case 'pos_support':
      return 'Soporte POS';
    case 'other':
      return 'Servicio';
    default:
      return 'Mantenimiento';
  }
}

String _serviceCategoryDropdownLabel(ServiceChecklistCategoryModel item) {
  return item.displayName;
}

class _SignatureBundle {
  final Uint8List? bytes;
  final String? fileId;
  final String? fileUrl;
  final DateTime? signedAt;

  const _SignatureBundle({
    this.bytes,
    this.fileId,
    this.fileUrl,
    this.signedAt,
  });
}

bool _useRightSidePanel(BuildContext context) {
  if (!_isDesktopPlatform()) return false;
  final width = MediaQuery.sizeOf(context).width;
  return width >= 980;
}

double _rightSidePanelWidth(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final target = width * 0.42;
  return target.clamp(520.0, 740.0);
}

double _rightSidePanelHeight(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  return (height * 0.96).clamp(560.0, height);
}

Future<T?> _showRightSideDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final scheme = Theme.of(dialogContext).colorScheme;
      final panelWidth = _rightSidePanelWidth(dialogContext);
      final panelHeight = _rightSidePanelHeight(dialogContext);
      final bottomInset = MediaQuery.viewInsetsOf(dialogContext).bottom;

      final radius = BorderRadius.circular(18);

      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: radius,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: panelWidth,
                height: panelHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.surfaceContainerHighest, scheme.surface],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: radius,
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.18),
                      blurRadius: 28,
                      offset: const Offset(-10, 16),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              scheme.primary.withValues(alpha: 0.06),
                              scheme.surface.withValues(alpha: 0.0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: -36,
                      right: -46,
                      child: Container(
                        width: 190,
                        height: 190,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.tertiary.withValues(alpha: 0.10),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 110,
                      left: -60,
                      child: Container(
                        width: 210,
                        height: 210,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.secondary.withValues(alpha: 0.09),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: bottomInset),
                      child: builder(dialogContext),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Route<T> _buildServiceDetailRoute<T>(Widget child) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionsBuilder: (context, animation, secondaryAnimation, routeChild) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: Tween<double>(begin: 0.92, end: 1).animate(curved),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: routeChild,
        ),
      );
    },
  );
}

class _OperationsServiceDetailPage extends StatelessWidget {
  final ServiceModel service;
  final Widget child;

  const _OperationsServiceDetailPage({
    required this.service,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final customer = service.customerName.trim().isEmpty
        ? 'Detalle de orden'
        : service.customerName.trim();
    final orderLabel = service.orderLabel.trim();
    final title = orderLabel.isEmpty ? customer : '$customer · $orderLabel';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      appBar: AppBar(
        leading: const OperationsBackButton(fallbackRoute: Routes.operaciones),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Detalle de orden',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF10233F),
              ),
            ),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.68),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFFF7FAFD), scheme.surface],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullServiceOrderEditResult {
  const _FullServiceOrderEditResult({
    required this.serviceType,
    required this.orderType,
    required this.categoryId,
    required this.categoryCode,
    required this.categoryName,
    required this.priority,
    required this.title,
    required this.description,
    required this.addressSnapshot,
    required this.orderState,
    required this.technicianId,
    required this.relatedServiceId,
    required this.surveyResult,
    required this.materialsUsed,
    required this.finalCost,
    required this.quotedAmount,
    required this.depositAmount,
    required this.tags,
  });

  final String serviceType;
  final String orderType;
  final String? categoryId;
  final String categoryCode;
  final String categoryName;
  final int priority;
  final String title;
  final String description;
  final String? addressSnapshot;
  final String orderState;
  final String? technicianId;
  final String? relatedServiceId;
  final String? surveyResult;
  final String? materialsUsed;
  final double? finalCost;
  final double? quotedAmount;
  final double? depositAmount;
  final List<String> tags;
}

Future<_FullServiceOrderEditResult?> _showOperationsServiceFullEditForm(
  BuildContext context,
  ServiceModel service,
) {
  if (_useRightSidePanel(context)) {
    return _showRightSideDialog<_FullServiceOrderEditResult>(
      context,
      builder: (dialogContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(dialogContext).bottom,
            ),
            child: _OperationsServiceFullEditForm(service: service),
          ),
        );
      },
    );
  }

  return Navigator.of(context).push<_FullServiceOrderEditResult>(
    _buildServiceDetailRoute<_FullServiceOrderEditResult>(
      _OperationsServiceFullEditPage(service: service),
    ),
  );
}

class _OperationsServiceFullEditPage extends StatelessWidget {
  const _OperationsServiceFullEditPage({required this.service});

  final ServiceModel service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      appBar: AppBar(
        leading: const BackButton(),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Editar orden',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF10233F),
              ),
            ),
            Text(
              service.orderLabel.trim().isEmpty
                  ? service.customerName.trim()
                  : service.orderLabel.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.68),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFFF7FAFD), scheme.surface],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: _OperationsServiceFullEditForm(
              service: service,
              useModalShell: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _OperationsServiceFullEditForm extends ConsumerStatefulWidget {
  const _OperationsServiceFullEditForm({
    required this.service,
    this.useModalShell = true,
  });

  final ServiceModel service;
  final bool useModalShell;

  @override
  ConsumerState<_OperationsServiceFullEditForm> createState() =>
      _OperationsServiceFullEditFormState();
}

class _OperationsServiceFullEditFormState
    extends ConsumerState<_OperationsServiceFullEditForm> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _gpsCtrl = TextEditingController();
  final _quotedCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _relatedServiceCtrl = TextEditingController();
  final _surveyResultCtrl = TextEditingController();
  final _materialsUsedCtrl = TextEditingController();
  final _finalCostCtrl = TextEditingController();

  late String _serviceType;
  late String _orderType;
  late String _categoryId;
  late int _priority;
  late String _orderState;
  String? _technicianId;
  bool _loadingCategories = false;
  bool _loadingTechnicians = false;
  List<ServiceChecklistCategoryModel> _categories = defaultCategories;
  List<TechnicianModel> _technicians = const [];

  ServiceModel get service => widget.service;

  bool get _isLevantamientoPhase {
    return _normalizedOrderType == 'levantamiento';
  }

  bool get _isWarrantyOrder => _normalizedOrderType == 'garantia';

  bool get _usesExecutionFields =>
      _normalizedOrderType == 'mantenimiento' ||
      _normalizedOrderType == 'instalacion';

  String get _normalizedOrderType => _normalizeAgendaKindValue(
    _orderType,
    fallback: service.currentPhase.trim().toLowerCase().isEmpty
        ? 'mantenimiento'
        : service.currentPhase.trim().toLowerCase(),
  );

  @override
  void initState() {
    super.initState();
    final address = _extractEditableServiceAddress(service.customerAddress);
    _orderType = _normalizeAgendaKindValue(
      service.orderType,
      fallback: service.currentPhase.trim().toLowerCase().isEmpty
          ? 'mantenimiento'
          : service.currentPhase.trim().toLowerCase(),
    );
    _serviceType = service.serviceType.trim().isEmpty
        ? _serviceTypeForAgendaKind(_orderType)
        : service.serviceType;
    _categoryId = service.categoryId ?? '';
    _priority = service.priority;
    _orderState = service.orderState.trim().isEmpty
        ? 'pending'
        : service.orderState;
    _categories = _categoriesFromAsync(ref.read(categoriesProvider));
    _technicianId = (service.technicianId ?? '').trim().isEmpty
        ? null
        : service.technicianId;
    _descriptionCtrl.text = service.description.trim() == 'Sin nota'
        ? ''
        : service.description.trim();
    _addressCtrl.text = address.addressLine;
    _gpsCtrl.text = address.gpsText;
    _quotedCtrl.text = service.quotedAmount == null
        ? ''
        : service.quotedAmount!.toStringAsFixed(2);
    _depositCtrl.text = service.depositAmount == null
        ? ''
        : service.depositAmount!.toStringAsFixed(2);
    _surveyResultCtrl.text = (service.surveyResult ?? '').trim();
    _materialsUsedCtrl.text = (service.materialsUsed ?? '').trim();
    _finalCostCtrl.text = service.finalCost == null
        ? ''
        : service.finalCost!.toStringAsFixed(2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadCategories());
      unawaited(_loadTechnicians());
    });
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _addressCtrl.dispose();
    _gpsCtrl.dispose();
    _quotedCtrl.dispose();
    _depositCtrl.dispose();
    _relatedServiceCtrl.dispose();
    _surveyResultCtrl.dispose();
    _materialsUsedCtrl.dispose();
    _finalCostCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTechnicians() async {
    if (_loadingTechnicians) return;
    setState(() => _loadingTechnicians = true);
    try {
      final items = await ref
          .read(operationsRepositoryProvider)
          .getTechnicians(silent: true);
      if (!mounted) return;
      setState(() => _technicians = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _technicians = const []);
    } finally {
      if (mounted) setState(() => _loadingTechnicians = false);
    }
  }

  Future<void> _loadCategories() async {
    if (_loadingCategories) return;
    setState(() => _loadingCategories = true);
    try {
      final items = await ref.read(categoriesProvider.future);
      if (!mounted) return;
      setState(() {
        _categories = items.isNotEmpty ? items : defaultCategories;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_categories.isEmpty) {
          _categories = defaultCategories;
        }
      });
    } finally {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  List<ServiceChecklistCategoryModel> _categoriesFromAsync(
    AsyncValue<List<ServiceChecklistCategoryModel>> value,
  ) {
    final remote = value.maybeWhen(
      data: (items) => items,
      orElse: () => const <ServiceChecklistCategoryModel>[],
    );
    return remote.isNotEmpty ? remote : defaultCategories;
  }

  ServiceChecklistCategoryModel? _resolveSelectedCategory(
    List<ServiceChecklistCategoryModel> items,
  ) {
    if (_categoryId.trim().isNotEmpty) {
      for (final item in items) {
        if (item.id == _categoryId.trim()) return item;
      }
    }
    final serviceCode = service.category.trim().toLowerCase();
    for (final item in items) {
      if (item.code.trim().toLowerCase() == serviceCode) return item;
    }
    return items.isEmpty ? null : items.first;
  }

  String? _categoryIdForSubmit(ServiceChecklistCategoryModel category) {
    final id = category.id.trim();
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuid.hasMatch(id) ? id : null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final categories = _categoriesFromAsync(ref.read(categoriesProvider));

    final selectedCategory = _resolveSelectedCategory(categories);
    if (selectedCategory == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Selecciona una categoría válida')),
      );
      return;
    }

    final description = _descriptionCtrl.text.trim();
    final snapshot = _buildEditableServiceAddressSnapshot(
      addressLine: _addressCtrl.text,
      gpsText: _gpsCtrl.text,
    );
    final quoted = double.tryParse(_quotedCtrl.text.trim());
    final deposit = double.tryParse(_depositCtrl.text.trim());
    final finalCost = double.tryParse(_finalCostCtrl.text.trim());
    final tags = [
      for (final tag in service.tags)
        if (tag.trim().toLowerCase() != 'seguro' && tag.trim().isNotEmpty)
          tag.trim(),
      if ((deposit ?? 0) > 0) 'seguro',
    ];

    final result = _FullServiceOrderEditResult(
      serviceType: _serviceType,
      orderType: _orderType,
      categoryId: _categoryIdForSubmit(selectedCategory),
      categoryCode: selectedCategory.code,
      categoryName: selectedCategory.displayName,
      priority: _priority,
      title:
          '${_agendaKindLabel(_orderType)} · ${selectedCategory.displayName}',
      description: description.isEmpty ? 'Sin nota' : description,
      addressSnapshot: snapshot,
      orderState: _orderState,
      technicianId: (_technicianId ?? '').trim().isEmpty ? null : _technicianId,
      relatedServiceId: _relatedServiceCtrl.text.trim().isEmpty
          ? null
          : _relatedServiceCtrl.text.trim(),
      surveyResult: _surveyResultCtrl.text.trim().isEmpty
          ? null
          : _surveyResultCtrl.text.trim(),
      materialsUsed: _materialsUsedCtrl.text.trim().isEmpty
          ? null
          : _materialsUsedCtrl.text.trim(),
      finalCost: finalCost,
      quotedAmount: quoted,
      depositAmount: deposit,
      tags: tags,
    );

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categories = _categories.isNotEmpty ? _categories : defaultCategories;
    final category = _resolveSelectedCategory(categories);
    final technicianIds = _technicians.map((item) => item.id).toSet();
    final effectiveTechnicianId = technicianIds.contains(_technicianId)
        ? _technicianId
        : null;

    final formBody = Form(
      key: _formKey,
      child: ListView(
        padding: widget.useModalShell
            ? const EdgeInsets.only(bottom: 10)
            : const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          CreateOrderSection(
            title: 'Cliente',
            icon: Icons.person_outline_rounded,
            subtitle:
                'El cliente se mantiene fijo para esta edicion de la orden.',
            child: CreateOrderClientCard(
              title: service.customerName.trim().isEmpty
                  ? 'Cliente'
                  : service.customerName.trim(),
              subtitle: [
                if (service.customerPhone.trim().isNotEmpty)
                  service.customerPhone.trim(),
                if (service.customerAddress.trim().isNotEmpty)
                  service.customerAddress.trim(),
              ].join(' · '),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Bloqueado',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              actions: const [],
            ),
          ),
          const SizedBox(height: 12),
          CreateOrderSection(
            title: 'Configuracion',
            icon: Icons.tune_rounded,
            subtitle:
                'Ajusta tipo, categoria, prioridad, tecnico y estado de la orden.',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _orderType,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Fase de orden',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'instalacion',
                            child: Text('Instalacion'),
                          ),
                          DropdownMenuItem(
                            value: 'mantenimiento',
                            child: Text('Mantenimiento'),
                          ),
                          DropdownMenuItem(
                            value: 'garantia',
                            child: Text('Garantia'),
                          ),
                          DropdownMenuItem(
                            value: 'levantamiento',
                            child: Text('Levantamiento'),
                          ),
                          DropdownMenuItem(
                            value: 'reserva',
                            child: Text('Reserva'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null || value.trim().isEmpty) return;
                          setState(() {
                            _orderType = value;
                            _serviceType = _serviceTypeForAgendaKind(
                              value,
                              fallback: _serviceType,
                            );
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _serviceType,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Tipo de servicio',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'installation',
                            child: Text('Instalacion'),
                          ),
                          DropdownMenuItem(
                            value: 'maintenance',
                            child: Text('Mantenimiento'),
                          ),
                          DropdownMenuItem(
                            value: 'warranty',
                            child: Text('Garantia'),
                          ),
                          DropdownMenuItem(
                            value: 'pos_support',
                            child: Text('POS soporte'),
                          ),
                          DropdownMenuItem(value: 'other', child: Text('Otro')),
                        ],
                        onChanged: (value) {
                          if (value == null || value.trim().isEmpty) return;
                          setState(() => _serviceType = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: category?.id,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: _loadingCategories
                              ? 'Categoria (cargando...)'
                              : 'Categoria',
                        ),
                        items: [
                          for (final item in categories)
                            DropdownMenuItem(
                              value: item.id,
                              child: Text(_serviceCategoryDropdownLabel(item)),
                            ),
                        ],
                        onChanged: _loadingCategories
                            ? null
                            : (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return;
                                }
                                setState(() => _categoryId = value);
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _priority,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Prioridad',
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('Alta')),
                          DropdownMenuItem(value: 2, child: Text('Media')),
                          DropdownMenuItem(value: 3, child: Text('Baja')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _priority = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _orderState,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Estado de orden',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('Pendiente'),
                          ),
                          DropdownMenuItem(
                            value: 'confirmed',
                            child: Text('Confirmada'),
                          ),
                          DropdownMenuItem(
                            value: 'assigned',
                            child: Text('Asignada'),
                          ),
                          DropdownMenuItem(
                            value: 'in_progress',
                            child: Text('En progreso'),
                          ),
                          DropdownMenuItem(
                            value: 'finalized',
                            child: Text('Finalizada'),
                          ),
                          DropdownMenuItem(
                            value: 'cancelled',
                            child: Text('Cancelada'),
                          ),
                          DropdownMenuItem(
                            value: 'rescheduled',
                            child: Text('Reagendada'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null || value.trim().isEmpty) return;
                          setState(() => _orderState = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: effectiveTechnicianId,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: _loadingTechnicians
                        ? 'Tecnico (cargando...)'
                        : 'Tecnico asignado',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sin asignar'),
                    ),
                    for (final tech in _technicians)
                      DropdownMenuItem<String?>(
                        value: tech.id,
                        child: Text(tech.name),
                      ),
                  ],
                  onChanged: _loadingTechnicians
                      ? null
                      : (value) => setState(() => _technicianId = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CreateOrderSection(
            title: 'Detalle y ubicacion',
            icon: Icons.description_outlined,
            subtitle:
                'Edita la nota operativa y la informacion de llegada del servicio.',
            child: Column(
              children: [
                TextFormField(
                  controller: _descriptionCtrl,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Nota / descripcion',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressCtrl,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Direccion',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _gpsCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'GPS o link de Maps',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CreateOrderSection(
            title: 'Montos',
            icon: Icons.payments_outlined,
            subtitle:
                'Completa cotizacion, deposito y total para mantener la orden lista para sus fases.',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quotedCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Cotizacion',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _depositCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Deposito',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _finalCostCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Monto total',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_isWarrantyOrder ||
              _isLevantamientoPhase ||
              _usesExecutionFields) ...[
            CreateOrderSection(
              title: 'Datos por fase',
              icon: Icons.assignment_outlined,
              subtitle:
                  'Estos campos se adaptan a la fase seleccionada para la orden.',
              child: Column(
                children: [
                  if (_isWarrantyOrder)
                    TextFormField(
                      controller: _relatedServiceCtrl,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Servicio relacionado',
                      ),
                    ),
                  if (_isLevantamientoPhase) ...[
                    if (_isWarrantyOrder) const SizedBox(height: 10),
                    TextFormField(
                      controller: _surveyResultCtrl,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Resultado de levantamiento',
                      ),
                    ),
                  ],
                  if (_usesExecutionFields) ...[
                    if (_isWarrantyOrder || _isLevantamientoPhase)
                      const SizedBox(height: 10),
                    TextFormField(
                      controller: _materialsUsedCtrl,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Materiales usados',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          CreateOrderFooterBar(
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar cambios'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!widget.useModalShell) {
      return formBody;
    }

    return CreateOrderModalShell(
      title: 'Editar orden de servicio',
      subtitle:
          'Actualiza la informacion principal de la orden completa desde Operaciones.',
      onClose: () => Navigator.pop(context),
      child: formBody,
    );
  }
}

class OperacionesScreen extends ConsumerStatefulWidget {
  const OperacionesScreen({super.key});

  @override
  ConsumerState<OperacionesScreen> createState() => _OperacionesScreenState();
}

class _OperacionesScreenState extends ConsumerState<OperacionesScreen>
    with WidgetsBindingObserver {
  static const double _desktopOperationsBreakpoint = kDesktopShellBreakpoint;
  static const Duration _deepLinkTimeout = Duration(seconds: 12);

  final _searchCtrl = TextEditingController();
  final _panelKey = GlobalKey<_PanelOptionsState>();
  final _desktopFilterButtonKey = GlobalKey(
    debugLabel: 'operationsDesktopFilterButton',
  );
  String? _lastAppliedDeepLinkKey;

  Future<void> _openQuickCreateFromAppBar() async {
    const title = 'Crear orden de servicio';
    const submitLabel = 'Guardar orden';
    const initialServiceType = 'maintenance';

    var orderType = 'mantenimiento';

    if (_useRightSidePanel(context)) {
      await _showRightSideDialog<void>(
        context,
        builder: (_) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return CreateOrderModalShell(
                title: title,
                subtitle:
                    'Completa los datos clave para registrar una nueva orden con una distribución más clara y profesional.',
                onClose: () => Navigator.pop(context),
                showGrip: false,
                child: _CreateReservationTab(
                  onCreate: (draft) async {
                    final ok = await _handleCreateGenericOrder(
                      draft,
                      orderType: orderType,
                    );
                    if (ok && context.mounted) Navigator.pop(context);
                  },
                  submitLabel: submitLabel,
                  initialServiceType: initialServiceType,
                  showServiceTypeField: false,
                  agendaKind: orderType,
                  showAgendaKindPicker: true,
                  onAgendaKindChanged: (value) {
                    final next = value.trim().toLowerCase();
                    if (next.isEmpty) return;
                    setDialogState(() => orderType = next);
                  },
                ),
              );
            },
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.92,
                child: CreateOrderModalShell(
                  title: title,
                  subtitle:
                      'Completa los datos clave para registrar una nueva orden con una distribución más clara y profesional.',
                  onClose: () => Navigator.pop(context),
                  child: _CreateReservationTab(
                    onCreate: (draft) async {
                      final ok = await _handleCreateGenericOrder(
                        draft,
                        orderType: orderType,
                      );
                      if (ok && context.mounted) Navigator.pop(context);
                    },
                    submitLabel: submitLabel,
                    initialServiceType: initialServiceType,
                    showServiceTypeField: false,
                    agendaKind: orderType,
                    showAgendaKindPicker: true,
                    onAgendaKindChanged: (value) {
                      final next = value.trim().toLowerCase();
                      if (next.isEmpty) return;
                      setSheetState(() => orderType = next);
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final qp = GoRouterState.of(context).uri.queryParameters;
    final customerId = (qp['customerId'] ?? '').trim();
    final serviceId = (qp['serviceId'] ?? '').trim();

    if (customerId.isEmpty && serviceId.isEmpty) return;

    final key = '$customerId|$serviceId';
    if (_lastAppliedDeepLinkKey == key) return;
    _lastAppliedDeepLinkKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_applyDeepLink(customerId: customerId, serviceId: serviceId));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      ref.read(operationsControllerProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyDeepLink({
    required String customerId,
    required String serviceId,
  }) async {
    final notifier = ref.read(operationsControllerProvider.notifier);

    try {
      if (customerId.trim().isNotEmpty) {
        await notifier.setCustomer(customerId.trim());
      }

      if (!mounted) return;

      if (serviceId.trim().isNotEmpty) {
        final targetId = serviceId.trim();

        final currentState = ref.read(operationsControllerProvider);
        ServiceModel? fromList;
        for (final item in currentState.services) {
          if (item.id.trim() == targetId) {
            fromList = item;
            break;
          }
        }

        final service =
            fromList ??
            await notifier.getOne(targetId).timeout(_deepLinkTimeout);
        if (!mounted) return;
        await _openServiceDetail(service);
      }
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'No se pudo abrir el proceso automáticamente.';
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _changeStatusWithConfirm(ServiceModel service) async {
    final statuses = const [
      'reserved',
      'survey',
      'scheduled',
      'in_progress',
      'completed',
      'warranty',
      'closed',
      'cancelled',
    ];

    String label(String raw) {
      switch (raw) {
        case 'reserved':
          return 'Reserva';
        case 'survey':
          return 'Levantamiento';
        case 'scheduled':
          return 'Servicio (agendado)';
        case 'in_progress':
          return 'Servicio (en proceso)';
        case 'warranty':
          return 'Garantía';
        case 'completed':
          return 'Finalizado';
        case 'closed':
          return 'Cerrado';
        case 'cancelled':
          return 'Cancelado';
        default:
          return raw;
      }
    }

    final picked = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Cambiar estado'),
          children: statuses
              .map(
                (s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, s),
                  child: Row(
                    children: [
                      Expanded(child: Text(label(s))),
                      if (s == service.status)
                        const Icon(Icons.check_rounded, size: 18),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );

    if (!mounted || picked == null) return;
    if (picked == service.status) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar cambio'),
          content: Text(
            'Vas a cambiar el estado de "${label(service.status)}" a "${label(picked)}".\n\n¿Seguro que deseas hacerlo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cambiar'),
            ),
          ],
        );
      },
    );
    if (!mounted || ok != true) return;

    await _changeStatus(service.id, picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Estado cambiado a ${label(picked)}')),
    );
  }

  Future<void> _openCatalogoDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.80,
          child: const CatalogoScreen(modal: true),
        ),
      ),
    );
  }

  Future<void> _openPoncheDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.60,
          child: const _PunchOnlySheet(),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildMobileAppBar({
    required AuthState authState,
    required Color gradientTop,
    required Color gradientMid,
    required Color gradientBottom,
  }) {
    return OperationsAppBar(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [gradientTop, gradientMid, gradientBottom],
        stops: const [0.0, 0.55, 1.0],
      ),
      userName: authState.user?.nombreCompleto,
      photoUrl: authState.user?.fotoPersonalUrl,
      onOpenQuickCreate: (_) => _openQuickCreateFromAppBar(),
      onOpenMap: (_) => context.push(Routes.operacionesMapaClientes),
      onOpenProfile: (_) => context.go(Routes.profile),
    );
  }

  PreferredSizeWidget _buildDesktopAppBar({
    required BuildContext context,
    required AuthState authState,
    required TextEditingController searchCtrl,
    required VoidCallback onOpenFilters,
    required VoidCallback onRefresh,
    Key? filterButtonKey,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppBar(
      toolbarHeight: 64,
      elevation: 0,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      titleSpacing: 14,
      title: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: searchCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Buscar…',
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: searchCtrl.text.trim().isNotEmpty
                      ? IconButton(
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () => searchCtrl.clear(),
                          icon: const Icon(Icons.close_rounded),
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            key: filterButtonKey,
            tooltip: 'Filtros',
            onPressed: onOpenFilters,
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Actualizar tablero',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: _openQuickCreateFromAppBar,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Nueva orden'),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Mapa clientes',
          onPressed: () => context.push(Routes.operacionesMapaClientes),
          icon: const Icon(Icons.map_outlined),
        ),
        const SizedBox(width: 8),
        _UserAvatarAction(
          userName: authState.user?.nombreCompleto,
          photoUrl: authState.user?.fotoPersonalUrl,
          onTap: () => context.go(Routes.profile),
        ),
        const SizedBox(width: 14),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  Widget _buildDesktopFabDock() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FilledButton.tonalIcon(
              onPressed: _openCatalogoDialog,
              icon: const _CatalogoFabIcon(),
              label: const Text('Catálogo'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _openPoncheDialog,
              icon: const _PoncheFabIcon(),
              label: const Text('Ponche'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileFabDock() {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset + 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surface.withValues(alpha: 0.98),
              Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.07),
                scheme.surface,
              ),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _MobileOperationsFabButton(
                tooltip: 'Catálogo',
                icon: const _CatalogoFabIcon(),
                onPressed: _openCatalogoDialog,
                accentColor: scheme.primary,
                delay: const Duration(milliseconds: 0),
              ),
              const SizedBox(height: 6),
              _MobileOperationsFabButton(
                tooltip: 'Ponchar',
                icon: const _PoncheFabIcon(),
                onPressed: _openPoncheDialog,
                accentColor: scheme.tertiary,
                delay: const Duration(milliseconds: 70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final state = ref.watch(operationsControllerProvider);
    final notifier = ref.read(operationsControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final isDesktop =
        MediaQuery.sizeOf(context).width >= _desktopOperationsBreakpoint;

    final gradientTop = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.10),
      scheme.primary,
    );
    final gradientMid = Color.alphaBlend(
      scheme.secondary.withValues(alpha: 0.16),
      scheme.primary,
    );
    final gradientBottom = Color.alphaBlend(
      scheme.tertiary.withValues(alpha: 0.18),
      scheme.primary,
    );

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: authState.user),
      appBar: isDesktop
          ? _buildDesktopAppBar(
              context: context,
              authState: authState,
              searchCtrl: _searchCtrl,
              onOpenFilters: () {
                unawaited(
                  _panelKey.currentState?._openFilters(
                    anchorKey: _desktopFilterButtonKey,
                  ),
                );
              },
              onRefresh: notifier.refresh,
              filterButtonKey: _desktopFilterButtonKey,
            )
          : _buildMobileAppBar(
              authState: authState,
              gradientTop: gradientTop,
              gradientMid: gradientMid,
              gradientBottom: gradientBottom,
            ),
      floatingActionButton: isDesktop
          ? _buildDesktopFabDock()
          : _buildMobileFabDock(),
      body: Stack(
        children: [
          _buildBoard(context, authState.user, state, notifier),
          if (state.loading && state.services.isEmpty)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBoard(
    BuildContext context,
    UserModel? currentUser,
    OperationsState state,
    OperationsController notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        children: [
          Expanded(
            child: _PanelOptions(
              key: _panelKey,
              currentUser: currentUser,
              state: state,
              searchCtrl: _searchCtrl,
              onRefresh: notifier.refresh,
              loadUsers: () => ref.read(usersRepositoryProvider).getAllUsers(),
              loadTechnicians: () =>
                  ref.read(operationsRepositoryProvider).getTechnicians(),
              onApplyRemote: (range, techId) =>
                  notifier.applyRangeAndTechnician(
                    from: range.start,
                    to: range.end,
                    technicianId: (techId ?? '').trim().isEmpty ? null : techId,
                  ),
              onOpenService: _openServiceDetail,
              onOpenEditService: _openServiceEdit,
              onChangeStatus: _changeStatusWithConfirm,
              onChangeOrderState: (serviceId, orderState) =>
                  notifier.changeOrderStateOptimistic(serviceId, orderState),
              onChangePhase: (service, phase, scheduledAt, note) =>
                  notifier.changePhaseOptimistic(
                    service.id,
                    phase,
                    scheduledAt: scheduledAt,
                    note: note,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openServiceDetail(ServiceModel service) async {
    await Navigator.of(context).push<void>(
      _buildServiceDetailRoute(
        _OperationsServiceDetailPage(
          service: service,
          child: _ServiceDetailPanel(
            service: service,
            onChangeStatus: (status) => _changeStatus(service.id, status),
            onChangeOrderState: (orderState) => ref
                .read(operationsControllerProvider.notifier)
                .changeOrderStateOptimistic(service.id, orderState),
            onSchedule: (start, end) =>
                _scheduleService(service.id, start, end),
            onCreateWarranty: () => _createWarranty(service.id),
            onAssign: (assignments) => _assignTechs(service.id, assignments),
            onToggleStep: (stepId, done) =>
                _toggleStep(service.id, stepId, done),
            onAddNote: (message) => _addNote(service.id, message),
            onUploadEvidence: () => _uploadEvidence(service.id),
          ),
        ),
      ),
    );
  }

  Future<void> _openServiceEdit(ServiceModel service) async {
    final result = await _showOperationsServiceFullEditForm(context, service);
    if (!mounted || result == null) return;

    try {
      final updated = await ref
          .read(operationsControllerProvider.notifier)
          .updateService(
            serviceId: service.id,
            serviceType: result.serviceType,
            orderType: result.orderType,
            categoryId: result.categoryId,
            category: result.categoryCode,
            priority: result.priority,
            title: result.title,
            description: result.description,
            quotedAmount: result.quotedAmount,
            depositAmount: result.depositAmount,
            addressSnapshot: result.addressSnapshot,
            warrantyParentServiceId: result.relatedServiceId,
            surveyResult: result.surveyResult,
            materialsUsed: result.materialsUsed,
            finalCost: result.finalCost,
            orderState: result.orderState,
            technicianId: result.technicianId,
            tags: result.tags,
          );
      if (!mounted) return;
      _applyOptimisticServiceRefresh(updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Orden actualizada')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error is ApiException ? error.message : '$error'),
        ),
      );
    }
  }

  // ignore: unused_element
  Future<void> _handleCreateService(_CreateServiceDraft draft) async {
    try {
      final created = await _createService(draft);

      final paymentNote = (draft.paymentNote ?? '').trim();
      if (paymentNote.isNotEmpty) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .addNote(created.id, paymentNote);
        } catch (_) {
          // No bloquea la creación.
        }
      }

      final reservationAt = draft.reservationAt;
      if (reservationAt != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .schedule(
                created.id,
                reservationAt,
                reservationAt.add(const Duration(hours: 1)),
              );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is ApiException ? e.message : 'No se pudo agendar la reserva',
              ),
            ),
          );
        }
      }

      try {
        await _postCreateUploadReferences(
          ref: ref,
          serviceId: created.id,
          referenceText: draft.referenceText,
          images: draft.referenceImages,
          video: draft.referenceVideo,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'No se pudo subir la referencia',
            ),
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reserva creada correctamente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo registrar el servicio',
          ),
        ),
      );
    }
  }

  Future<ServiceModel> _createService(
    _CreateServiceDraft draft, {
    String? orderType,
  }) {
    return ref
        .read(operationsControllerProvider.notifier)
        .createReservation(
          customerId: draft.customerId,
          serviceType: draft.serviceType,
          categoryId: draft.categoryId,
          category: draft.categoryCode,
          priority: draft.priority,
          title: draft.title,
          description: draft.description,
          addressSnapshot: draft.addressSnapshot,
          quotedAmount: draft.quotedAmount,
          depositAmount: draft.depositAmount,
          orderType: orderType,
          orderState: draft.orderState,
          technicianId: draft.technicianId,
          warrantyParentServiceId: draft.relatedServiceId,
          tags: draft.tags,
        );
  }

  void _applyOptimisticServiceRefresh(ServiceModel service) {
    ref
        .read(operationsControllerProvider.notifier)
        .applyRealtimeService(service);
    ref
        .read(techOperationsControllerProvider.notifier)
        .applyRealtimeService(service);
  }

  void _refreshCreatedServiceInBackground(ServiceModel fallback) {
    unawaited(() async {
      ServiceModel next = fallback;
      try {
        next = await ref
            .read(operationsRepositoryProvider)
            .getService(fallback.id);
      } catch (_) {
        // Si el backend todavía no termina de reconciliar, se conserva la versión creada.
      }

      if (!mounted) return;
      _applyOptimisticServiceRefresh(next);
      unawaited(
        ref
            .read(techOperationsControllerProvider.notifier)
            .refresh(silent: true),
      );
    }());
  }

  Future<bool> _handleCreateGenericOrder(
    _CreateServiceDraft draft, {
    required String orderType,
  }) async {
    final normalized = orderType.trim().isEmpty
        ? 'mantenimiento'
        : orderType.trim().toLowerCase();

    try {
      final created = await _createService(draft, orderType: normalized);
      _applyOptimisticServiceRefresh(created);

      final paymentNote = (draft.paymentNote ?? '').trim();
      if (paymentNote.isNotEmpty) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .addNote(created.id, paymentNote);
        } catch (_) {
          // No bloquea la creación.
        }
      }

      final reservationAt = draft.reservationAt;
      if (reservationAt != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .schedule(
                created.id,
                reservationAt,
                reservationAt.add(const Duration(hours: 1)),
              );
        } catch (_) {
          // No bloquea la creación.
        }

        // Si está agendada, por defecto marca la etapa como agendada.
        if (created.status.trim().toLowerCase() != 'scheduled') {
          try {
            await ref
                .read(operationsControllerProvider.notifier)
                .changeStatus(created.id, 'scheduled');
          } catch (_) {
            // No bloquea la creación.
          }
        }
      }

      try {
        await _postCreateUploadReferences(
          ref: ref,
          serviceId: created.id,
          referenceText: draft.referenceText,
          images: draft.referenceImages,
          video: draft.referenceVideo,
        );
      } catch (_) {
        // No bloquea la creación.
      }

      _refreshCreatedServiceInBackground(created);

      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden creada correctamente')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo registrar la orden',
          ),
        ),
      );
      return false;
    }
  }

  // ignore: unused_element
  Future<bool> _handleCreateFromAgenda(
    _CreateServiceDraft draft,
    String kind,
  ) async {
    final lower = kind.trim().toLowerCase();
    final targetStatus = switch (lower) {
      'levantamiento' => 'survey',
      'servicio' => 'scheduled',
      'mantenimiento' => 'scheduled',
      'instalacion' => 'scheduled',
      'garantia' => 'warranty',
      _ => null,
    };
    final successLabel = switch (lower) {
      'reserva' => 'Reserva',
      'levantamiento' => 'Levantamiento',
      'servicio' => 'Mantenimiento',
      'mantenimiento' => 'Mantenimiento',
      'instalacion' => 'Instalación',
      'garantia' => 'Garantía',
      _ => 'Servicio',
    };

    try {
      final created = await _createService(draft, orderType: lower);
      _applyOptimisticServiceRefresh(created);

      final paymentNote = (draft.paymentNote ?? '').trim();
      if (paymentNote.isNotEmpty) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .addNote(created.id, paymentNote);
        } catch (_) {
          // No bloquea la creación.
        }
      }

      final reservationAt = draft.reservationAt;
      if (reservationAt != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .schedule(
                created.id,
                reservationAt,
                reservationAt.add(const Duration(hours: 1)),
              );
        } catch (_) {
          // No bloquea la creación desde agenda.
        }
      }

      try {
        await _postCreateUploadReferences(
          ref: ref,
          serviceId: created.id,
          referenceText: draft.referenceText,
          images: draft.referenceImages,
          video: draft.referenceVideo,
        );
      } catch (_) {
        // No bloquea la creación desde agenda.
      }

      if (targetStatus != null && targetStatus != created.status) {
        await ref
            .read(operationsControllerProvider.notifier)
            .changeStatus(created.id, targetStatus);
      }
      _refreshCreatedServiceInBackground(created);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successLabel creado correctamente')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo registrar el servicio',
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _changeStatus(String serviceId, String status) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .changeStatus(serviceId, status);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _scheduleService(String id, DateTime start, DateTime end) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .schedule(id, start, end);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _createWarranty(String id) async {
    try {
      await ref.read(operationsControllerProvider.notifier).createWarranty(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _toggleStep(String id, String stepId, bool done) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .toggleStep(id, stepId, done);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _addNote(String id, String note) async {
    try {
      await ref.read(operationsControllerProvider.notifier).addNote(id, note);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _assignTechs(
    String id,
    List<Map<String, String>> assignments,
  ) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .assign(id, assignments);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _uploadEvidence(String id) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .uploadEvidence(id, result.files.first);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Evidencia subida')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }
}

class OperacionesAgendaScreen extends ConsumerStatefulWidget {
  const OperacionesAgendaScreen({super.key});

  @override
  ConsumerState<OperacionesAgendaScreen> createState() =>
      _OperacionesAgendaScreenState();
}

class _OperacionesAgendaScreenState
    extends ConsumerState<OperacionesAgendaScreen> {
  // ignore: unused_element
  String _statusLabel(String raw) {
    switch (raw) {
      case 'reserved':
        return 'Sin etapa';
      case 'survey':
        return 'Levantamiento';
      case 'scheduled':
        return 'Agendado';
      case 'in_progress':
        return 'En proceso';
      case 'warranty':
        return 'Garantía';
      case 'completed':
        return 'Finalizado';
      case 'closed':
        return 'Cerrado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return raw;
    }
  }

  // ignore: unused_element
  String _serviceTypeLabel(String raw) {
    switch (raw) {
      case 'installation':
        return 'Instalación';
      case 'maintenance':
        return 'Servicio técnico';
      case 'warranty':
        return 'Garantía';
      default:
        return raw;
    }
  }

  String _categoryLabel(String raw) {
    return localizedServiceCategoryLabel(raw);
  }

  void _applyOptimisticServiceRefresh(ServiceModel service) {
    ref
        .read(operationsControllerProvider.notifier)
        .applyRealtimeService(service);
    ref
        .read(techOperationsControllerProvider.notifier)
        .applyRealtimeService(service);
  }

  void _refreshCreatedServiceInBackground(ServiceModel fallback) {
    unawaited(() async {
      ServiceModel next = fallback;
      try {
        next = await ref
            .read(operationsRepositoryProvider)
            .getService(fallback.id);
      } catch (_) {
        // Conserva la versión recién creada si el backend aún reconcilia.
      }

      if (!mounted) return;
      _applyOptimisticServiceRefresh(next);
      unawaited(
        ref
            .read(techOperationsControllerProvider.notifier)
            .refresh(silent: true),
      );
    }());
  }

  Future<void> _openServiceDetail(ServiceModel service) async {
    await Navigator.of(context).push<void>(
      _buildServiceDetailRoute(
        _OperationsServiceDetailPage(
          service: service,
          child: _ServiceDetailPanel(
            service: service,
            onChangeStatus: (status) => _changeStatus(service.id, status),
            onChangeOrderState: (orderState) => ref
                .read(operationsControllerProvider.notifier)
                .changeOrderStateOptimistic(service.id, orderState),
            onSchedule: (start, end) =>
                _scheduleService(service.id, start, end),
            onCreateWarranty: () => _createWarranty(service.id),
            onAssign: (assignments) => _assignTechs(service.id, assignments),
            onToggleStep: (stepId, done) =>
                _toggleStep(service.id, stepId, done),
            onAddNote: (message) => _addNote(service.id, message),
            onUploadEvidence: () => _uploadEvidence(service.id),
          ),
        ),
      ),
    );
  }

  Future<void> _changeStatusWithConfirm(ServiceModel service) async {
    final statuses = const [
      'reserved',
      'survey',
      'scheduled',
      'in_progress',
      'completed',
      'warranty',
      'closed',
      'cancelled',
    ];

    String label(String raw) {
      switch (raw) {
        case 'reserved':
          return 'Reserva';
        case 'survey':
          return 'Levantamiento';
        case 'scheduled':
          return 'Servicio (agendado)';
        case 'in_progress':
          return 'Servicio (en proceso)';
        case 'warranty':
          return 'Garantía';
        case 'completed':
          return 'Finalizado';
        case 'closed':
          return 'Cerrado';
        case 'cancelled':
          return 'Cancelado';
        default:
          return raw;
      }
    }

    final picked = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Cambiar estado'),
          children: statuses
              .map(
                (s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, s),
                  child: Row(
                    children: [
                      Expanded(child: Text(label(s))),
                      if (s == service.status)
                        const Icon(Icons.check_rounded, size: 18),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );

    if (!mounted || picked == null) return;
    if (picked == service.status) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar cambio'),
          content: Text(
            'Vas a cambiar el estado de "${label(service.status)}" a "${label(picked)}".\n\n¿Seguro que deseas hacerlo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cambiar'),
            ),
          ],
        );
      },
    );
    if (!mounted || ok != true) return;

    await _changeStatus(service.id, picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Estado cambiado a ${label(picked)}')),
    );
  }

  Future<void> _changeStatus(String serviceId, String status) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .changeStatus(serviceId, status);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _scheduleService(String id, DateTime start, DateTime end) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .schedule(id, start, end);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _createWarranty(String id) async {
    try {
      await ref.read(operationsControllerProvider.notifier).createWarranty(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _toggleStep(String id, String stepId, bool done) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .toggleStep(id, stepId, done);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _addNote(String id, String note) async {
    try {
      await ref.read(operationsControllerProvider.notifier).addNote(id, note);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _assignTechs(
    String id,
    List<Map<String, String>> assignments,
  ) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .assign(id, assignments);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _uploadEvidence(String id) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .uploadEvidence(id, result.files.first);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Evidencia subida')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  // ignore: unused_element
  Future<bool> _createFromAgenda(_CreateServiceDraft draft, String kind) async {
    final lower = kind.trim().toLowerCase();
    final targetStatus = switch (lower) {
      'levantamiento' => 'survey',
      'servicio' => 'scheduled',
      'garantia' => 'warranty',
      _ => null,
    };
    final successLabel = switch (lower) {
      'reserva' => 'Reserva',
      'levantamiento' => 'Levantamiento',
      'servicio' => 'Servicio',
      'garantia' => 'Garantía',
      _ => 'Servicio',
    };

    try {
      final created = await ref
          .read(operationsControllerProvider.notifier)
          .createReservation(
            customerId: draft.customerId,
            serviceType: draft.serviceType,
            categoryId: draft.categoryId,
            category: draft.categoryCode,
            priority: draft.priority,
            title: draft.title,
            description: draft.description,
            addressSnapshot: draft.addressSnapshot,
            quotedAmount: draft.quotedAmount,
            depositAmount: draft.depositAmount,
            orderType: lower,
            orderState: draft.orderState,
            technicianId: draft.technicianId,
            warrantyParentServiceId: draft.relatedServiceId,
            tags: draft.tags,
          );
      _applyOptimisticServiceRefresh(created);

      final reservationAt = draft.reservationAt;
      if (reservationAt != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .schedule(
                created.id,
                reservationAt,
                reservationAt.add(const Duration(hours: 1)),
              );
        } catch (_) {
          // No bloquea la creación desde agenda.
        }
      }

      try {
        await _postCreateUploadReferences(
          ref: ref,
          serviceId: created.id,
          referenceText: draft.referenceText,
          images: draft.referenceImages,
          video: draft.referenceVideo,
        );
      } catch (e) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'No se pudo subir la referencia',
            ),
          ),
        );
      }

      if (targetStatus != null && targetStatus != created.status) {
        await ref
            .read(operationsControllerProvider.notifier)
            .changeStatus(created.id, targetStatus);
      }

      _refreshCreatedServiceInBackground(created);

      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successLabel creado correctamente')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo registrar el servicio',
          ),
        ),
      );
      return false;
    }
  }

  Future<bool> _createGenericFromAgenda(_CreateServiceDraft draft) async {
    const orderType = 'mantenimiento';

    try {
      final created = await ref
          .read(operationsControllerProvider.notifier)
          .createReservation(
            customerId: draft.customerId,
            serviceType: draft.serviceType,
            categoryId: draft.categoryId,
            category: draft.categoryCode,
            priority: draft.priority,
            title: draft.title,
            description: draft.description,
            addressSnapshot: draft.addressSnapshot,
            quotedAmount: draft.quotedAmount,
            depositAmount: draft.depositAmount,
            orderType: orderType,
            orderState: draft.orderState,
            technicianId: draft.technicianId,
            warrantyParentServiceId: draft.relatedServiceId,
            tags: draft.tags,
          );
      _applyOptimisticServiceRefresh(created);

      final reservationAt = draft.reservationAt;
      if (reservationAt != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .schedule(
                created.id,
                reservationAt,
                reservationAt.add(const Duration(hours: 1)),
              );
        } catch (_) {
          // No bloquea la creación desde agenda.
        }

        if (created.status.trim().toLowerCase() != 'scheduled') {
          try {
            await ref
                .read(operationsControllerProvider.notifier)
                .changeStatus(created.id, 'scheduled');
          } catch (_) {
            // No bloquea la creación desde agenda.
          }
        }
      }

      try {
        await _postCreateUploadReferences(
          ref: ref,
          serviceId: created.id,
          referenceText: draft.referenceText,
          images: draft.referenceImages,
          video: draft.referenceVideo,
        );
      } catch (e) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'No se pudo subir la referencia',
            ),
          ),
        );
      }

      _refreshCreatedServiceInBackground(created);

      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden creada correctamente')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo registrar la orden',
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _openAgendaForm() async {
    const title = 'Crear orden de servicio';
    const submitLabel = 'Guardar orden';
    const initialServiceType = 'maintenance';

    if (_useRightSidePanel(context)) {
      await _showRightSideDialog<void>(
        context,
        builder: (context) {
          return CreateOrderModalShell(
            title: title,
            subtitle:
                'Crea una orden genérica con una estructura más clara. La etapa se puede ajustar luego en Detalles.',
            onClose: () => Navigator.pop(context),
            showGrip: false,
            child: _CreateReservationTab(
              submitLabel: submitLabel,
              initialServiceType: initialServiceType,
              showServiceTypeField: false,
              onCreate: (draft) async {
                final ok = await _createGenericFromAgenda(draft);
                if (ok && context.mounted) Navigator.pop(context);
              },
            ),
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.92,
              child: StatefulBuilder(
                builder: (context, setSheetState) {
                  return CreateOrderModalShell(
                    title: title,
                    subtitle:
                        'Crea una orden genérica con una estructura más clara. La etapa se puede ajustar luego en Detalles.',
                    onClose: () => Navigator.pop(context),
                    child: _CreateReservationTab(
                      submitLabel: submitLabel,
                      initialServiceType: initialServiceType,
                      showServiceTypeField: false,
                      onCreate: (draft) async {
                        final ok = await _createGenericFromAgenda(draft);
                        if (ok && context.mounted) Navigator.pop(context);
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openHistorialDialog(List<ServiceModel> services) async {
    final items = [...services];
    items.sort((a, b) {
      final ad = a.scheduledStart ?? a.completedAt;
      final bd = b.scheduledStart ?? b.completedAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    final df = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Historial de servicios (${items.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text('Sin servicios para mostrar'),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final service = items[index];
                              final date =
                                  service.scheduledStart ?? service.completedAt;
                              final dateText = date == null
                                  ? '—'
                                  : df.format(date);
                              return ListTile(
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${service.customerName} · ${service.title}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (service.isSeguro) ...[
                                      const SizedBox(width: 8),
                                      const _SeguroBadge(),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  '$dateText · ${service.status} · ${_effectiveServiceKindLabel(service)} · P${service.priority}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(operationsControllerProvider);
    final notifier = ref.read(operationsControllerProvider.notifier);

    final scheduled =
        state.services.where((s) => s.scheduledStart != null).toList()
          ..sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Regresar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            final router = GoRouter.of(context);
            if (router.canPop()) {
              router.pop();
              return;
            }
            context.go(Routes.operaciones);
          },
        ),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Agenda',
            maxLines: 1,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Historial',
            onPressed: () => _openHistorialDialog(state.services),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Agendar',
        onPressed: _openAgendaForm,
        child: const Icon(Icons.add_rounded),
      ),
      body: state.loading && scheduled.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: notifier.refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.event_note_rounded),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Agenda de servicios',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Text('${scheduled.length}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (scheduled.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('Sin servicios agendados'),
                      ),
                    )
                  else
                    ...scheduled.map((service) {
                      final typeText = _effectiveServiceKindLabel(service);
                      final categoryText = _categoryLabel(service.category);
                      final address = service.customerAddress.trim();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openServiceDetail(service),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          service.customerName.trim().isEmpty
                                              ? 'Cliente'
                                              : service.customerName.trim(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Cambiar estado',
                                        onPressed: () =>
                                            _changeStatusWithConfirm(service),
                                        icon: const Icon(
                                          Icons.swap_horiz_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    categoryText.isEmpty
                                        ? typeText
                                        : '$typeText · $categoryText',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.place_outlined,
                                        size: 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.65),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          address.isEmpty
                                              ? 'Sin dirección'
                                              : address,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.70),
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _UserAvatarAction extends StatelessWidget {
  final String? userName;
  final String? photoUrl;
  final VoidCallback onTap;

  const _UserAvatarAction({
    required this.userName,
    required this.photoUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = getInitials((userName ?? 'Usuario').trim());
    final trimmedUrl = photoUrl?.trim() ?? '';

    Widget avatar;
    if (trimmedUrl.isNotEmpty) {
      avatar = ClipOval(
        child: Image.network(
          trimmedUrl,
          width: 34,
          height: 34,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _InitialsAvatar(initials: initials);
          },
        ),
      );
    } else {
      avatar = _InitialsAvatar(initials: initials);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Tooltip(
          message: 'Mi perfil',
          child: Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(
                color: scheme.onPrimary.withValues(alpha: 0.22),
              ),
            ),
            child: Center(child: avatar),
          ),
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String initials;

  const _InitialsAvatar({required this.initials});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: Colors.white.withValues(alpha: 0.20),
      child: Text(
        initials.isEmpty ? 'U' : initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SeguroBadge extends StatelessWidget {
  const _SeguroBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.30)),
      ),
      child: Text(
        'SEGURO',
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

bool _looksLikeValidLocationText(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  if (RegExp(r'https?://', caseSensitive: false).hasMatch(v)) return true;
  if (parseLatLngFromText(v) != null) return true;
  return false;
}

bool _isFinalizedService(ServiceModel s) {
  final orderState = s.orderState.trim().toLowerCase();
  final status = s.status.trim().toLowerCase();
  if (orderState == 'finalized') return true;
  if (status == 'completed' || status == 'closed') return true;
  return false;
}

List<String> _missingPhaseRequirements(ServiceModel s, String phase) {
  final p = phase.trim().toLowerCase();

  const requiresData = {
    'levantamiento',
    'instalacion',
    'mantenimiento',
    'garantia',
  };

  if (requiresData.contains(p)) {
    final missing = <String>[];

    if (s.customerId.trim().isEmpty) missing.add('Cliente');
    if (s.customerName.trim().isEmpty) missing.add('Nombre cliente');
    if (s.customerPhone.trim().isEmpty) missing.add('Teléfono cliente');

    final quoted = (s.quotedAmount ?? 0);
    if (quoted <= 0) missing.add('Cotización');

    if (!_looksLikeValidLocationText(s.customerAddress)) {
      missing.add('Ubicación GPS');
    }

    if (p == 'instalacion' || p == 'mantenimiento') {
      final total = (s.finalCost ?? 0);
      if (total <= 0) missing.add('Monto total');
    }

    if (p == 'garantia' && !_isFinalizedService(s)) {
      missing.add('Orden finalizada');
    }

    return missing;
  }

  return const [];
}

class _PhaseValidationPromptData {
  const _PhaseValidationPromptData({required this.missing, this.message});

  final List<String> missing;
  final String? message;
}

String _cleanPhaseValidationItem(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return text;
  final withoutPrefix = text.replaceFirst(
    RegExp(r'^Falta:\s*', caseSensitive: false),
    '',
  );
  final withoutPath = withoutPrefix.replaceFirst(RegExp(r'\s*\(.*\)$'), '');
  return withoutPath.trim();
}

_PhaseValidationPromptData? _phaseValidationPromptDataFromError(
  Object error, {
  List<String> fallbackMissing = const [],
}) {
  final missing = <String>{
    ...fallbackMissing
        .map(_cleanPhaseValidationItem)
        .where((e) => e.isNotEmpty),
  };
  String? message;

  void addRawMessage(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;

    final itemMatches = RegExp(
      r'Falta:\s*([^\(\n\r]+)',
      caseSensitive: false,
    ).allMatches(text);
    for (final match in itemMatches) {
      final item = _cleanPhaseValidationItem(match.group(0) ?? '');
      if (item.isNotEmpty) missing.add(item);
    }

    if (message == null && missing.isEmpty) {
      message = text;
    }
  }

  if (error is ApiException) {
    final raw = error.message.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final code = (decoded['code'] ?? '').toString().trim().toUpperCase();
          final rawMessage = decoded['message'];
          if (rawMessage is List) {
            for (final item in rawMessage) {
              addRawMessage(item.toString());
            }
          } else if (rawMessage != null) {
            addRawMessage(rawMessage.toString());
          }
          if (code == 'PHASE_VALIDATION' || missing.isNotEmpty) {
            return _PhaseValidationPromptData(
              missing: missing.toList(growable: false),
              message: message,
            );
          }
        }
      } catch (_) {
        addRawMessage(raw);
      }

      if (raw.toUpperCase().contains('PHASE_VALIDATION') ||
          missing.isNotEmpty) {
        return _PhaseValidationPromptData(
          missing: missing.toList(growable: false),
          message: message,
        );
      }
    }
  }

  if (missing.isEmpty) return null;
  return _PhaseValidationPromptData(
    missing: missing.toList(growable: false),
    message: message,
  );
}

Future<bool> _showPhaseValidationPrompt(
  BuildContext context, {
  required String phase,
  required _PhaseValidationPromptData data,
  required bool canEdit,
  String actionLabel = 'Editar orden',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final scheme = theme.colorScheme;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              colors: [Color(0xFFF9FBFF), Color(0xFFEFF6FF), Color(0xFFFFFFFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: const Color(0xFFD7E6F7)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x180F172A),
                blurRadius: 28,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFBFDBFE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: const Color(0xFFDBEAFE),
                      ),
                      child: const Icon(
                        Icons.edit_note_rounded,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Completa la orden antes de continuar',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF10233F),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'La fase ${phaseLabel(phase)} necesita datos obligatorios para aplicarse.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF5B6B82),
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (data.missing.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in data.missing)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFD9E7F5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 15,
                                color: Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                item,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF20344D),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ] else if ((data.message ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFD9E7F5)),
                    ),
                    child: Text(
                      data.message!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF20344D),
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF20344D),
                          side: const BorderSide(color: Color(0xFFD7E6F7)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Ahora no'),
                      ),
                    ),
                    if (canEdit) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(actionLabel),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  return result == true;
}

class _PanelOptions extends StatefulWidget {
  final UserModel? currentUser;
  final OperationsState state;
  final TextEditingController searchCtrl;
  final Future<void> Function() onRefresh;

  final Future<List<UserModel>> Function() loadUsers;
  final Future<List<TechnicianModel>> Function() loadTechnicians;
  final Future<void> Function(DateTimeRange range, String? technicianId)
  onApplyRemote;

  final void Function(ServiceModel) onOpenService;
  final void Function(ServiceModel) onOpenEditService;
  final Future<void> Function(ServiceModel service) onChangeStatus;
  final Future<void> Function(String serviceId, String orderState)
  onChangeOrderState;
  final Future<void> Function(
    ServiceModel service,
    String phase,
    DateTime scheduledAt,
    String? note,
  )
  onChangePhase;

  const _PanelOptions({
    super.key,
    required this.currentUser,
    required this.state,
    required this.searchCtrl,
    required this.onRefresh,
    required this.loadUsers,
    required this.loadTechnicians,
    required this.onApplyRemote,
    required this.onOpenService,
    required this.onOpenEditService,
    required this.onChangeStatus,
    required this.onChangeOrderState,
    required this.onChangePhase,
  });

  @override
  State<_PanelOptions> createState() => _PanelOptionsState();
}

class _PanelOptionsState extends State<_PanelOptions> {
  OperationsFilters _filters = OperationsFilters.todayDefault();
  final _searchFilterButtonKey = GlobalKey(
    debugLabel: 'operationsSearchFilterButton',
  );
  final _filtersBarButtonKey = GlobalKey(
    debugLabel: 'operationsFiltersBarButton',
  );
  final _createdByFieldKey = GlobalKey(debugLabel: 'operationsCreatedByField');
  final _technicianFieldKey = GlobalKey(
    debugLabel: 'operationsTechnicianField',
  );

  Future<List<UserModel>>? _usersFuture;
  Future<List<TechnicianModel>>? _techsFuture;

  @override
  void initState() {
    super.initState();
    _filters = OperationsFilters.todayDefault();
    widget.searchCtrl.addListener(_onQueryChange);
  }

  @override
  void didUpdateWidget(covariant _PanelOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchCtrl != widget.searchCtrl) {
      oldWidget.searchCtrl.removeListener(_onQueryChange);
      widget.searchCtrl.addListener(_onQueryChange);
    }
  }

  @override
  void dispose() {
    widget.searchCtrl.removeListener(_onQueryChange);
    super.dispose();
  }

  void _onQueryChange() {
    if (mounted) setState(() {});
  }

  String _rangeLabel(DateTimeRange r) {
    final df = DateFormat('dd/MM/yyyy', 'es');
    if (r.start.year == r.end.year &&
        r.start.month == r.end.month &&
        r.start.day == r.end.day) {
      return 'Hoy, ${df.format(r.start)}';
    }
    return '${df.format(r.start)} - ${df.format(r.end)}';
  }

  int _activeFilterCount() {
    var count = 0;
    if (_filters.status != OperationsStatusFilter.all) count++;
    if (_filters.priority != OperationsPriorityFilter.all) count++;
    if ((_filters.createdByUserId ?? '').trim().isNotEmpty) count++;
    if ((_filters.technicianId ?? '').trim().isNotEmpty) count++;
    if (_filters.datePreset != OperationsDatePreset.today) count++;
    return count;
  }

  List<OperationsFilterChipData> _buildFilterChips() {
    final chips = <OperationsFilterChipData>[
      OperationsFilterChipData(
        label: datePresetLabel(_filters.datePreset),
        icon: Icons.calendar_today_outlined,
        highlighted: _filters.datePreset != OperationsDatePreset.today,
      ),
    ];

    if (_filters.status != OperationsStatusFilter.all) {
      chips.add(
        OperationsFilterChipData(
          label: statusFilterLabel(_filters.status),
          icon: Icons.local_offer_outlined,
          highlighted: true,
        ),
      );
    }
    if (_filters.priority != OperationsPriorityFilter.all) {
      chips.add(
        OperationsFilterChipData(
          label: 'Prioridad ${priorityFilterLabel(_filters.priority)}',
          icon: Icons.priority_high_rounded,
          highlighted: true,
        ),
      );
    }
    if ((_filters.technicianId ?? '').trim().isNotEmpty) {
      chips.add(
        const OperationsFilterChipData(
          label: 'Tecnico filtrado',
          icon: Icons.engineering_outlined,
          highlighted: true,
        ),
      );
    }
    if ((_filters.createdByUserId ?? '').trim().isNotEmpty) {
      chips.add(
        const OperationsFilterChipData(
          label: 'Creador filtrado',
          icon: Icons.badge_outlined,
          highlighted: true,
        ),
      );
    }

    return chips;
  }

  // ignore: unused_element
  bool _isDefaultTodayRange(DateTimeRange r) {
    final today = OperationsFilters.todayDefault().range;
    return r.start == today.start && r.end == today.end;
  }

  // ignore: unused_element
  InputDecoration _denseDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      isDense: true,
      prefixIcon: Icon(icon),
      hintText: hint,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return CompactFilterSection(title: title, child: child);
  }

  Widget _choiceChips<T>({
    required T value,
    required List<(T, String)> items,
    required void Function(T next) onChanged,
  }) {
    return CompactFilterChoiceGroup<T>(
      value: value,
      items: items,
      onChanged: onChanged,
    );
  }

  Future<String?> _pickFromListSheet({
    required String title,
    required List<(String id, String label)> items,
    required String? selectedId,
    required GlobalKey anchorKey,
  }) {
    return showAnchoredCompactPanel<String?>(
      context,
      anchorKey: anchorKey,
      maxWidth: 380,
      builder: (context) {
        String query = '';

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;

        List<(String id, String label)> filtered() {
          final q = query.trim().toLowerCase();
          if (q.isEmpty) return items;
          return items.where((e) => e.$2.toLowerCase().contains(q)).toList();
        }

        return StatefulBuilder(
          builder: (context, setInner) {
            final list = filtered();

            return DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFD9E3EE)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.14),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: TextField(
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Buscar…',
                        filled: true,
                        fillColor: const Color(0xFFF6F9FC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (v) => setInner(() => query = v),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      children: [
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Icon(
                            Icons.all_inclusive_rounded,
                            color: scheme.primary,
                          ),
                          title: const Text(
                            'Todos',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          trailing: selectedId == null
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: scheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, null),
                        ),
                        for (final e in list)
                          ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            title: Text(
                              e.$2,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            trailing: selectedId == e.$1
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: scheme.primary,
                                  )
                                : null,
                            onTap: () => Navigator.pop(context, e.$1),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openFilters({GlobalKey? anchorKey}) async {
    _usersFuture ??= widget.loadUsers();
    _techsFuture ??= widget.loadTechnicians();

    OperationsFilters draft = _filters;
    final hasCancelled = widget.state.services.any(
      (s) => s.status.trim().toLowerCase() == 'cancelled',
    );
    final hasLowPriority = widget.state.services.any((s) => s.priority >= 3);

    final result = await showAnchoredCompactPanel<OperationsFilters>(
      context,
      anchorKey: anchorKey ?? _searchFilterButtonKey,
      maxWidth: 520,
      maxHeightFactor: 0.8,
      verticalOffset: 16,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickCustomRange() async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                initialDateRange: draft.range,
                helpText: 'Selecciona intervalo de fecha',
              );
              if (picked == null) return;
              setSheetState(() => draft = draft.withCustomRange(picked));
            }

            return CompactFilterPanelFrame(
              title: 'Filtros',
              onClose: () => Navigator.pop(context),
              onApply: () => Navigator.pop(context, draft),
              onClear: () {
                setSheetState(() => draft = OperationsFilters.todayDefault());
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _sectionCard(
                          title: 'Usuario creador',
                          child: FutureBuilder<List<UserModel>>(
                            future: _usersFuture,
                            builder: (context, snap) {
                              if (snap.connectionState !=
                                  ConnectionState.done) {
                                return const LinearProgressIndicator();
                              }
                              if (snap.hasError) {
                                return Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'No se pudieron cargar usuarios',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        setSheetState(() {
                                          _usersFuture = widget.loadUsers();
                                        });
                                      },
                                      child: const Text('Reintentar'),
                                    ),
                                  ],
                                );
                              }

                              final users =
                                  (snap.data ?? const [])
                                      .where(
                                        (u) =>
                                            (u.blocked) == false &&
                                            u.id.trim().isNotEmpty,
                                      )
                                      .toList()
                                    ..sort(
                                      (a, b) => a.nombreCompleto
                                          .toLowerCase()
                                          .compareTo(
                                            b.nombreCompleto.toLowerCase(),
                                          ),
                                    );

                              final selectedId = draft.createdByUserId;
                              final selectedLabel = selectedId == null
                                  ? 'Todos'
                                  : (users
                                            .firstWhere(
                                              (u) => u.id == selectedId,
                                              orElse: () => users.first,
                                            )
                                            .nombreCompleto)
                                        .trim();

                              return CompactFilterSelectorTile(
                                key: _createdByFieldKey,
                                icon: Icons.badge_outlined,
                                label: 'Usuario creador',
                                value: selectedLabel.isEmpty
                                    ? 'Todos'
                                    : selectedLabel,
                                onTap: () async {
                                  final items = users
                                      .map(
                                        (u) => (
                                          u.id,
                                          u.nombreCompleto.trim().isEmpty
                                              ? (u.email.trim().isEmpty
                                                    ? 'Usuario'
                                                    : u.email.trim())
                                              : u.nombreCompleto.trim(),
                                        ),
                                      )
                                      .toList(growable: false);

                                  final picked = await _pickFromListSheet(
                                    title: 'Usuario creador',
                                    items: items,
                                    selectedId: selectedId,
                                    anchorKey: _createdByFieldKey,
                                  );
                                  if (picked == null) {
                                    setSheetState(
                                      () => draft = draft.copyWith(
                                        clearCreatedBy: true,
                                      ),
                                    );
                                    return;
                                  }

                                  setSheetState(
                                    () => draft = draft.copyWith(
                                      createdByUserId: picked,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _sectionCard(
                          title: 'Técnico asignado',
                          child: FutureBuilder<List<TechnicianModel>>(
                            future: _techsFuture,
                            builder: (context, snap) {
                              if (snap.connectionState !=
                                  ConnectionState.done) {
                                return const LinearProgressIndicator();
                              }
                              if (snap.hasError) {
                                return Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'No se pudieron cargar técnicos',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        setSheetState(() {
                                          _techsFuture = widget
                                              .loadTechnicians();
                                        });
                                      },
                                      child: const Text('Reintentar'),
                                    ),
                                  ],
                                );
                              }

                              final techs =
                                  (snap.data ?? const [])
                                      .where((t) => t.id.trim().isNotEmpty)
                                      .toList()
                                    ..sort(
                                      (a, b) => a.name.toLowerCase().compareTo(
                                        b.name.toLowerCase(),
                                      ),
                                    );

                              final selectedId = draft.technicianId;
                              final selectedLabel = selectedId == null
                                  ? 'Todos'
                                  : (techs
                                            .firstWhere(
                                              (t) => t.id == selectedId,
                                              orElse: () => techs.first,
                                            )
                                            .name)
                                        .trim();

                              return CompactFilterSelectorTile(
                                key: _technicianFieldKey,
                                icon: Icons.engineering_outlined,
                                label: 'Técnico asignado',
                                value: selectedLabel.isEmpty
                                    ? 'Todos'
                                    : selectedLabel,
                                onTap: () async {
                                  final items = techs
                                      .map(
                                        (t) => (
                                          t.id,
                                          t.name.trim().isEmpty
                                              ? 'Técnico'
                                              : t.name.trim(),
                                        ),
                                      )
                                      .toList(growable: false);

                                  final picked = await _pickFromListSheet(
                                    title: 'Técnico asignado',
                                    items: items,
                                    selectedId: selectedId,
                                    anchorKey: _technicianFieldKey,
                                  );
                                  if (picked == null) {
                                    setSheetState(
                                      () => draft = draft.copyWith(
                                        clearTechnician: true,
                                      ),
                                    );
                                    return;
                                  }

                                  setSheetState(
                                    () => draft = draft.copyWith(
                                      technicianId: picked,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _sectionCard(
                    title: 'Rango de fechas',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _choiceChips<OperationsDatePreset>(
                          value: draft.datePreset,
                          items: const [
                            (OperationsDatePreset.today, 'Hoy'),
                            (OperationsDatePreset.week, 'Semana'),
                            (OperationsDatePreset.month, 'Mes'),
                            (OperationsDatePreset.custom, 'Personalizado'),
                          ],
                          onChanged: (next) {
                            setSheetState(() {
                              draft = switch (next) {
                                OperationsDatePreset.today =>
                                  draft.withTodayRange(),
                                OperationsDatePreset.week =>
                                  draft.withWeekRange(),
                                OperationsDatePreset.month =>
                                  draft.withMonthRange(),
                                OperationsDatePreset.custom => draft.copyWith(
                                  datePreset: OperationsDatePreset.custom,
                                ),
                              };
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        CompactFilterSelectorTile(
                          icon: Icons.date_range_outlined,
                          label: 'Intervalo',
                          value: _rangeLabel(draft.range),
                          onTap: draft.datePreset == OperationsDatePreset.custom
                              ? pickCustomRange
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _sectionCard(
                          title: 'Estado',
                          child: _choiceChips<OperationsStatusFilter>(
                            value: draft.status,
                            items: [
                              (OperationsStatusFilter.all, 'Todos'),
                              (OperationsStatusFilter.pending, 'Pendientes'),
                              (OperationsStatusFilter.inProgress, 'En proceso'),
                              (OperationsStatusFilter.completed, 'Completadas'),
                              if (hasCancelled)
                                (
                                  OperationsStatusFilter.cancelled,
                                  'Canceladas',
                                ),
                            ],
                            onChanged: (next) => setSheetState(
                              () => draft = draft.copyWith(status: next),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _sectionCard(
                          title: 'Prioridad',
                          child: _choiceChips<OperationsPriorityFilter>(
                            value: draft.priority,
                            items: [
                              (OperationsPriorityFilter.all, 'Todas'),
                              (OperationsPriorityFilter.high, 'Alta'),
                              (OperationsPriorityFilter.normal, 'Normal'),
                              if (hasLowPriority)
                                (OperationsPriorityFilter.low, 'Baja'),
                            ],
                            onChanged: (next) => setSheetState(
                              () => draft = draft.copyWith(priority: next),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;

    final before = _filters;
    setState(() => _filters = result);

    // Optimiza el fetch remoto: solo cuando cambian rango o técnico.
    final beforeTech = (before.technicianId ?? '').trim();
    final nextTech = (result.technicianId ?? '').trim();
    final shouldFetchRemote =
        before.range != result.range || beforeTech != nextTech;

    if (shouldFetchRemote) {
      await widget.onApplyRemote(result.range, result.technicianId);
    }
  }

  // ignore: unused_element
  String _statusLabel(String raw) {
    switch (raw) {
      case 'reserved':
        return 'Pendiente';
      case 'survey':
        return 'Levantamiento';
      case 'scheduled':
        return 'Agendado';
      case 'in_progress':
        return 'En proceso';
      case 'warranty':
        return 'Garantía';
      case 'completed':
        return 'Completado';
      case 'closed':
        return 'Cerrado';
      default:
        return raw;
    }
  }

  // ignore: unused_element
  String _typeLabel(String raw) {
    switch (raw) {
      case 'installation':
        return 'Instalación';
      case 'maintenance':
        return 'Mantenimiento';
      case 'warranty':
        return 'Garantía';
      case 'pos_support':
        return 'Soporte POS';
      default:
        return raw;
    }
  }

  String _categoryLabel(String raw) {
    return localizedServiceCategoryLabel(raw);
  }

  // ignore: unused_element
  String _techLabel(ServiceModel s) {
    if (s.assignments.isEmpty) return 'Sin asignar';
    final tech = s.assignments
        .where((a) => a.role == 'technician')
        .cast<ServiceAssignmentModel?>()
        .firstOrNull;
    return (tech ?? s.assignments.first).userName;
  }

  Future<void> _pickAndChangeOrderState(ServiceModel service) async {
    final current =
        ((service.adminStatus ?? '').trim().isNotEmpty
                ? service.adminStatus
                : (service.orderState.trim().isNotEmpty
                      ? service.orderState
                      : service.status))
            .toString()
            .trim()
            .toLowerCase();
    final picked = await StatusPickerSheet.show(context, current: current);
    if (!mounted || picked == null) return;

    final next = picked.trim().toLowerCase();
    if (next.isEmpty || next == current) return;

    try {
      await widget.onChangeOrderState(service.id, next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Estado: ${StatusPickerSheet.label(next)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo cambiar el estado',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final range = _filters.range;
    final isDesktop =
        MediaQuery.sizeOf(context).width >=
        _OperacionesScreenState._desktopOperationsBreakpoint;

    String? effectiveAdminStatus(ServiceModel s) {
      final raw = (s.adminStatus ?? '').trim().toLowerCase();
      return raw.isEmpty ? null : raw;
    }

    ops.ServiceStatus effectiveLegacyStatus(ServiceModel s) {
      final raw = s.orderState.trim().isNotEmpty ? s.orderState : s.status;
      return ops.parseStatus(raw);
    }

    bool inRange(ServiceModel s) {
      final scheduled = s.scheduledStart;
      if (scheduled == null) return false;
      return !scheduled.isBefore(range.start) && !scheduled.isAfter(range.end);
    }

    final window = widget.state.services.where(inRange).toList()
      ..sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));

    bool isPendingByAdmin(String st) {
      switch (st) {
        case 'pendiente':
        case 'confirmada':
        case 'asignada':
        case 'reagendada':
          return true;
        default:
          return false;
      }
    }

    bool isInProgressByAdmin(String st) {
      switch (st) {
        case 'en_camino':
        case 'en_proceso':
          return true;
        default:
          return false;
      }
    }

    bool isCompletedByAdmin(String st) {
      switch (st) {
        case 'finalizada':
        case 'cerrada':
          return true;
        default:
          return false;
      }
    }

    bool isCancelledByAdmin(String st) => st == 'cancelada';

    bool isPendingByLegacy(ops.ServiceStatus st) {
      switch (st) {
        case ops.ServiceStatus.reserved:
        case ops.ServiceStatus.survey:
        case ops.ServiceStatus.scheduled:
        case ops.ServiceStatus.warranty:
          return true;
        default:
          return false;
      }
    }

    bool isInProgressByLegacy(ops.ServiceStatus st) =>
        st == ops.ServiceStatus.inProgress;

    bool isCompletedByLegacy(ops.ServiceStatus st) {
      switch (st) {
        case ops.ServiceStatus.completed:
        case ops.ServiceStatus.closed:
          return true;
        default:
          return false;
      }
    }

    final query = widget.searchCtrl.text.trim().toLowerCase();
    bool matchesQuery(ServiceModel s) {
      if (query.isEmpty) return true;
      final h = '${s.customerName} ${s.customerPhone} ${s.title}'.toLowerCase();
      return h.contains(query);
    }

    bool matchesStatus(ServiceModel s) {
      final adminSt = effectiveAdminStatus(s);
      final legacySt = effectiveLegacyStatus(s);
      switch (_filters.status) {
        case OperationsStatusFilter.all:
          return true;
        case OperationsStatusFilter.pending:
          return adminSt != null
              ? isPendingByAdmin(adminSt)
              : isPendingByLegacy(legacySt);
        case OperationsStatusFilter.inProgress:
          return adminSt != null
              ? isInProgressByAdmin(adminSt)
              : isInProgressByLegacy(legacySt);
        case OperationsStatusFilter.completed:
          return adminSt != null
              ? isCompletedByAdmin(adminSt)
              : isCompletedByLegacy(legacySt);
        case OperationsStatusFilter.cancelled:
          return adminSt != null
              ? isCancelledByAdmin(adminSt)
              : legacySt == ops.ServiceStatus.cancelled;
      }
    }

    bool matchesPriority(ServiceModel s) {
      switch (_filters.priority) {
        case OperationsPriorityFilter.all:
          return true;
        case OperationsPriorityFilter.high:
          return s.priority <= 1;
        case OperationsPriorityFilter.normal:
          return s.priority == 2;
        case OperationsPriorityFilter.low:
          return s.priority >= 3;
      }
    }

    bool matchesTechnician(ServiceModel s) {
      final techId = (_filters.technicianId ?? '').trim();
      if (techId.isEmpty) return true;
      if ((s.technicianId ?? '').trim() == techId) return true;
      return s.assignments.any((a) => a.userId == techId);
    }

    bool matchesCreator(ServiceModel s) {
      final createdBy = (_filters.createdByUserId ?? '').trim();
      if (createdBy.isEmpty) return true;
      return s.createdByUserId.trim() == createdBy;
    }

    // Orden requerido:
    // a) lista original (window ya está recortada por rango)
    // b) filtros
    // c) búsqueda
    final filteredOrders = window
        .where(
          (s) =>
              matchesStatus(s) &&
              matchesPriority(s) &&
              matchesTechnician(s) &&
              matchesCreator(s),
        )
        .toList(growable: false);

    DateTime? sortStamp(ServiceModel s) {
      return s.createdAt ?? s.scheduledStart ?? s.completedAt;
    }

    final visibleOrders =
        filteredOrders.where(matchesQuery).toList(growable: true)..sort((a, b) {
          final ad = sortStamp(a);
          final bd = sortStamp(b);
          if (ad == null && bd == null) {
            // Stable-ish fallback.
            return b.id.compareTo(a.id);
          }
          if (ad == null) return 1;
          if (bd == null) return -1;
          final cmp = bd.compareTo(ad);
          if (cmp != 0) return cmp;
          return b.id.compareTo(a.id);
        });

    bool isPendingService(ServiceModel s) {
      final adminSt = effectiveAdminStatus(s);
      if (adminSt != null) return isPendingByAdmin(adminSt);
      return isPendingByLegacy(effectiveLegacyStatus(s));
    }

    bool isInProgressService(ServiceModel s) {
      final adminSt = effectiveAdminStatus(s);
      if (adminSt != null) return isInProgressByAdmin(adminSt);
      return isInProgressByLegacy(effectiveLegacyStatus(s));
    }

    bool isCompletedService(ServiceModel s) {
      final adminSt = effectiveAdminStatus(s);
      if (adminSt != null) return isCompletedByAdmin(adminSt);
      return isCompletedByLegacy(effectiveLegacyStatus(s));
    }

    int pendingCount(List<ServiceModel> list) =>
        list.where(isPendingService).length;
    int inProgressCount(List<ServiceModel> list) =>
        list.where(isInProgressService).length;
    int completedCount(List<ServiceModel> list) =>
        list.where(isCompletedService).length;

    final pendientesCount = pendingCount(visibleOrders);
    final procesoCount = inProgressCount(visibleOrders);
    final completadasCount = completedCount(visibleOrders);

    final atrasadas = visibleOrders.where((s) {
      if (isCompletedService(s)) return false;
      final due = s.scheduledStart;
      if (due == null) return false;
      return due.isBefore(now);
    }).length;

    assert(() {
      final rawStatuses = visibleOrders
          .map((s) => '${s.status}|${s.orderState}')
          .toSet()
          .toList(growable: false);
      debugPrint(
        '[operations] totalOrders=${widget.state.services.length} window=${window.length} filtered=${filteredOrders.length} visible=${visibleOrders.length} pend=$pendientesCount prog=$procesoCount comp=$completadasCount late=$atrasadas statuses=$rawStatuses',
      );
      return true;
    }());

    if (isDesktop) {
      return _buildDesktopLayout(
        theme: theme,
        range: range,
        visibleOrders: visibleOrders,
        pendientesCount: pendientesCount,
        procesoCount: procesoCount,
        completadasCount: completadasCount,
        atrasadas: atrasadas,
      );
    }

    return _buildMobileLayout(
      theme: theme,
      range: range,
      visibleOrders: visibleOrders,
      pendientesCount: pendientesCount,
      procesoCount: procesoCount,
      completadasCount: completadasCount,
      atrasadas: atrasadas,
    );
  }

  Widget _buildMobileLayout({
    required ThemeData theme,
    required DateTimeRange range,
    required List<ServiceModel> visibleOrders,
    required int pendientesCount,
    required int procesoCount,
    required int completadasCount,
    required int atrasadas,
  }) {
    final filterCount = _activeFilterCount();
    final metrics = [
      OperationsMetricItem(
        label: 'Pendientes',
        value: '$pendientesCount',
        caption: atrasadas > 0 ? '$atrasadas atrasadas' : 'En ventana',
        icon: Icons.error_outline,
        tint: theme.colorScheme.error,
      ),
      OperationsMetricItem(
        label: 'En proceso',
        value: '$procesoCount',
        caption: 'Trabajo activo',
        icon: Icons.play_circle_outline,
        tint: theme.colorScheme.tertiary,
      ),
      OperationsMetricItem(
        label: 'Completadas',
        value: '$completadasCount',
        caption: 'Cierre del periodo',
        icon: Icons.check_circle_outline,
        tint: theme.colorScheme.primary,
      ),
      OperationsMetricItem(
        label: 'Visibles',
        value: '${visibleOrders.length}',
        caption: _rangeLabel(range),
        icon: Icons.view_agenda_outlined,
        tint: theme.colorScheme.secondary,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchBarWidget(
          controller: widget.searchCtrl,
          filterButtonKey: _searchFilterButtonKey,
          onOpenFilters: () => _openFilters(anchorKey: _searchFilterButtonKey),
          onSubmitted: (_) => setState(() {}),
          hintText: 'Buscar cliente, orden o tecnico',
        ),
        const SizedBox(height: 6),
        FiltersBar(
          chips: _buildFilterChips(),
          activeCount: filterCount,
          filterButtonKey: _filtersBarButtonKey,
          onOpenFilters: () => _openFilters(anchorKey: _filtersBarButtonKey),
          onRefresh: () {
            unawaited(widget.onRefresh());
          },
        ),
        const SizedBox(height: 8),
        MetricsRow(items: metrics),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ordenes de servicio',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${visibleOrders.length} visibles · ${_rangeLabel(range)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (filterCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$filterCount filtros',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: visibleOrders.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 4),
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.inbox_outlined,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Sin servicios para mostrar con los filtros actuales.',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 2, bottom: 72),
                    itemCount: visibleOrders.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == visibleOrders.length - 1 ? 0 : 8,
                        ),
                        child: _buildServiceAgendaTile(visibleOrders[index]),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout({
    required ThemeData theme,
    required DateTimeRange range,
    required List<ServiceModel> visibleOrders,
    required int pendientesCount,
    required int procesoCount,
    required int completadasCount,
    required int atrasadas,
  }) {
    final pendingOrders = visibleOrders
        .where((service) {
          final raw = service.orderState.trim().isNotEmpty
              ? service.orderState
              : service.status;
          final status = ops.parseStatus(raw);
          return status == ops.ServiceStatus.reserved ||
              status == ops.ServiceStatus.survey ||
              status == ops.ServiceStatus.scheduled ||
              status == ops.ServiceStatus.warranty;
        })
        .toList(growable: false);

    final inProgressOrders = visibleOrders
        .where((service) {
          final raw = service.orderState.trim().isNotEmpty
              ? service.orderState
              : service.status;
          return ops.parseStatus(raw) == ops.ServiceStatus.inProgress;
        })
        .toList(growable: false);

    final completedOrders = visibleOrders
        .where((service) {
          final raw = service.orderState.trim().isNotEmpty
              ? service.orderState
              : service.status;
          final status = ops.parseStatus(raw);
          return status == ops.ServiceStatus.completed ||
              status == ops.ServiceStatus.closed;
        })
        .toList(growable: false);

    Widget controlOperativoCompact() {
      Widget kpi({
        required String label,
        required String value,
        required Color tint,
      }) {
        return Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tint.withValues(alpha: 0.14)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
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
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.circle, size: 10, color: tint),
                ],
              ),
            ),
          ),
        );
      }

      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              kpi(
                label: 'Visibles',
                value: '${visibleOrders.length}',
                tint: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 10),
              kpi(
                label: 'Atrasadas',
                value: '$atrasadas',
                tint: atrasadas > 0
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surfaceContainerLowest,
                theme.colorScheme.surface,
                theme.colorScheme.primary.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _OperationsDesktopMetricCard(
                        label: 'Pendientes',
                        value: pendientesCount,
                        icon: Icons.error_outline,
                        tint: theme.colorScheme.error,
                        caption: atrasadas > 0
                            ? '$atrasadas atrasadas'
                            : 'Sin atraso',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _OperationsDesktopMetricCard(
                        label: 'En proceso',
                        value: procesoCount,
                        icon: Icons.play_circle_outline,
                        tint: theme.colorScheme.tertiary,
                        caption: 'Atención activa',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _OperationsDesktopMetricCard(
                        label: 'Completadas',
                        value: completadasCount,
                        icon: Icons.check_circle_outline,
                        tint: theme.colorScheme.primary,
                        caption: 'Servicios cerrados',
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(width: 220, child: controlOperativoCompact()),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _OperationsDesktopColumn(
                  title: 'Pendientes',
                  count: pendingOrders.length,
                  tint: theme.colorScheme.error,
                  emptyLabel: 'No hay servicios pendientes.',
                  children: [
                    for (final service in pendingOrders)
                      _buildServiceAgendaTile(service),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OperationsDesktopColumn(
                  title: 'En proceso',
                  count: inProgressOrders.length,
                  tint: theme.colorScheme.tertiary,
                  emptyLabel: 'No hay servicios en proceso.',
                  children: [
                    for (final service in inProgressOrders)
                      _buildServiceAgendaTile(service),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OperationsDesktopColumn(
                  title: 'Completadas',
                  count: completedOrders.length,
                  tint: theme.colorScheme.primary,
                  emptyLabel: 'No hay servicios completados.',
                  children: [
                    for (final service in completedOrders)
                      _buildServiceAgendaTile(service),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  String _statusFilterLabel(OperationsStatusFilter value) {
    switch (value) {
      case OperationsStatusFilter.all:
        return 'Todos';
      case OperationsStatusFilter.pending:
        return 'Pendientes';
      case OperationsStatusFilter.inProgress:
        return 'En proceso';
      case OperationsStatusFilter.completed:
        return 'Completadas';
      case OperationsStatusFilter.cancelled:
        return 'Canceladas';
    }
  }

  // ignore: unused_element
  String _priorityFilterLabel(OperationsPriorityFilter value) {
    switch (value) {
      case OperationsPriorityFilter.all:
        return 'Todas';
      case OperationsPriorityFilter.high:
        return 'Alta';
      case OperationsPriorityFilter.normal:
        return 'Normal';
      case OperationsPriorityFilter.low:
        return 'Baja';
    }
  }

  Widget _buildServiceAgendaTile(ServiceModel s) {
    final type = _effectiveServiceKindLabel(s);
    final category = _categoryLabel(s.category);
    final subtitle = category.isEmpty ? type : '$type · $category';
    final tech = _techLabel(s);

    final scheduled = s.scheduledStart;
    final scheduledText = scheduled == null
        ? null
        : DateFormat('EEE dd/MM h:mm a', 'es_DO').format(scheduled);

    final perms = OperationsPermissions(user: widget.currentUser, service: s);
    final canChangePhase = perms.canChangePhase;
    final canEdit = perms.canCritical;

    return ServiceAgendaCard(
      service: s,
      subtitle: subtitle,
      technicianText: tech,
      scheduledText: scheduledText,
      onView: () => widget.onOpenService(s),
      onChangeState: () => _pickAndChangeOrderState(s),
      onChangePhase: !canChangePhase
          ? null
          : () {
              unawaited(() async {
                final draft = await ServiceActionsSheet.pickChangePhaseDraft(
                  context,
                  current: s.currentPhase,
                  initialScheduledAt: s.scheduledStart,
                );
                if (!mounted || draft == null) return;

                final next = (draft['phase'] ?? '').trim();
                final scheduledAtRaw = (draft['scheduledAt'] ?? '').trim();
                if (next.isEmpty) return;

                final scheduledAt = DateTime.tryParse(scheduledAtRaw);
                if (scheduledAt == null) return;

                final missing = _missingPhaseRequirements(s, next);
                if (missing.isNotEmpty) {
                  final goEdit = await _showPhaseValidationPrompt(
                    context,
                    phase: next,
                    data: _PhaseValidationPromptData(missing: missing),
                    canEdit: canEdit,
                  );
                  if (!mounted) return;
                  if (goEdit) {
                    widget.onOpenEditService(s);
                  }
                  return;
                }

                try {
                  await widget.onChangePhase(
                    s,
                    next,
                    scheduledAt,
                    draft['note'],
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fase: ${phaseLabel(next)}')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  final prompt = _phaseValidationPromptDataFromError(e);
                  if (prompt != null) {
                    final goEdit = await _showPhaseValidationPrompt(
                      context,
                      phase: next,
                      data: prompt,
                      canEdit: canEdit,
                    );
                    if (!mounted) return;
                    if (goEdit) {
                      widget.onOpenEditService(s);
                    }
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e is ApiException ? e.message : '$e'),
                    ),
                  );
                }
              }());
            },
    );
  }
}

class _OperationsDesktopMetricCard extends StatelessWidget {
  const _OperationsDesktopMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    required this.caption,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color tint;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: tint, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$value',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OperationsDesktopColumn extends StatelessWidget {
  const _OperationsDesktopColumn({
    required this.title,
    required this.count,
    required this.tint,
    required this.emptyLabel,
    required this.children,
  });

  final String title;
  final int count;
  final Color tint;
  final String emptyLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border(
                bottom: BorderSide(color: tint.withValues(alpha: 0.18)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: tint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: children.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        emptyLabel,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: children.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => children[index],
                  ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _OperationsDesktopInfoRow extends StatelessWidget {
  const _OperationsDesktopInfoRow({
    required this.label,
    required this.value,
    // ignore: unused_element_parameter
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: emphasize ? theme.colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _OperationsDesktopLegendRow extends StatelessWidget {
  const _OperationsDesktopLegendRow({
    required this.icon,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: tint, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _OperationsDesktopBadge extends StatelessWidget {
  const _OperationsDesktopBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ignore: unused_element
class _ReservaScreen extends StatelessWidget {
  final Future<void> Function(_CreateServiceDraft draft) onCreate;

  const _ReservaScreen({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OperationsBackButton(fallbackRoute: Routes.operaciones),
        title: const Text('Nueva reserva'),
      ),
      body: _CreateReservationTab(onCreate: onCreate),
    );
  }
}

class _ServiceDetailPanel extends ConsumerStatefulWidget {
  final ServiceModel service;
  final Future<void> Function(String status) onChangeStatus;
  final Future<void> Function(String orderState) onChangeOrderState;
  final Future<void> Function(DateTime start, DateTime end) onSchedule;
  final Future<void> Function() onCreateWarranty;
  final Future<void> Function(List<Map<String, String>> assignments) onAssign;
  final Future<void> Function(String stepId, bool done) onToggleStep;
  final Future<void> Function(String message) onAddNote;
  final Future<void> Function() onUploadEvidence;

  const _ServiceDetailPanel({
    required this.service,
    required this.onChangeStatus,
    required this.onChangeOrderState,
    required this.onSchedule,
    required this.onCreateWarranty,
    required this.onAssign,
    required this.onToggleStep,
    required this.onAddNote,
    required this.onUploadEvidence,
  });

  @override
  ConsumerState<_ServiceDetailPanel> createState() =>
      _ServiceDetailPanelState();
}

class _ServiceDetailPanelState extends ConsumerState<_ServiceDetailPanel> {
  final _noteCtrl = TextEditingController();

  late ServiceModel _service;

  List<ServicePhaseHistoryModel> _phaseHistory = const [];
  bool _phaseHistoryLoading = false;
  String? _phaseHistoryError;

  Future<List<ServiceMediaModel>>? _referenceMediaFuture;
  Future<ServiceExecutionBundleModel>? _executionBundleFuture;
  String? _lastReferenceText;

  @override
  void initState() {
    super.initState();
    _service = widget.service;
    _loadPhaseHistory();
    _primeReferenceFuture(widget.service);
    _primeExecutionBundle(widget.service);
    unawaited(_refreshServiceDetail());
  }

  @override
  void didUpdateWidget(covariant _ServiceDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service.id != widget.service.id) {
      _service = widget.service;
      _phaseHistory = const [];
      _phaseHistoryError = null;
      _phaseHistoryLoading = false;
      _loadPhaseHistory();
      _primeReferenceFuture(widget.service);
      _primeExecutionBundle(widget.service);
    }
  }

  void _primeReferenceFuture(ServiceModel service) {
    final refText = _extractLatestReferenceText(service);
    _lastReferenceText = refText;
    _referenceMediaFuture = _loadReferenceMedia(service.id);
  }

  void _primeExecutionBundle(ServiceModel service) {
    _executionBundleFuture = _loadExecutionBundle(service.id);
  }

  Future<void> _refreshServiceDetail({bool silent = true}) async {
    try {
      final fresh = await ref
          .read(operationsRepositoryProvider)
          .getService(widget.service.id);
      if (!mounted) return;
      setState(() {
        _service = fresh;
        _primeReferenceFuture(fresh);
        _primeExecutionBundle(fresh);
      });
      debugPrint(
        'Evidences: ${fresh.evidences.map((file) => '${file.id}:${file.fileType}').toList(growable: false)}',
      );
    } catch (e) {
      if (silent || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<List<ServiceMediaModel>> _loadReferenceMedia(String serviceId) {
    return ref
        .read(storageRepositoryProvider)
        .listByService(serviceId: serviceId);
  }

  Future<ServiceExecutionBundleModel> _loadExecutionBundle(String serviceId) {
    return ref
        .read(operationsRepositoryProvider)
        .getExecutionReport(serviceId: serviceId);
  }

  String? _extractLatestReferenceText(ServiceModel service) {
    for (var i = service.updates.length - 1; i >= 0; i--) {
      final msg = service.updates[i].message.trim();
      if (!msg.startsWith('[REF]')) continue;
      final rest = msg.substring('[REF]'.length).trim();
      if (rest.isEmpty) continue;
      return rest;
    }
    return null;
  }

  Future<void> _loadPhaseHistory() async {
    final serviceId = _service.id.trim();
    if (serviceId.isEmpty) return;

    setState(() {
      _phaseHistoryLoading = true;
      _phaseHistoryError = null;
    });

    try {
      final items = await ref
          .read(operationsRepositoryProvider)
          .listServicePhases(serviceId);
      if (!mounted) return;
      setState(() {
        _phaseHistory = items;
        _phaseHistoryLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phaseHistoryLoading = false;
        _phaseHistoryError = e is ApiException
            ? e.message
            : 'No se pudo cargar historial de fases';
      });
    }
  }

  ServiceFileModel? _findClosingFile(ServiceModel service, String? fileId) {
    final id = (fileId ?? '').trim();
    if (id.isEmpty) return null;
    try {
      return service.files.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  ServiceFileModel? _findLatestFileByType(ServiceModel service, String type) {
    final t = type.trim().toLowerCase();
    final candidates = service.files
        .where((f) => f.fileType.trim().toLowerCase() == t)
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    return candidates.first;
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final uri = Uri.tryParse(url.trim());
    final scheme = (uri?.scheme ?? '').toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw ApiException('Archivo remoto no disponible para descarga');
    }

    final dio = ref.read(dioProvider);
    final res = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data;
    if (data == null) return Uint8List(0);
    return Uint8List.fromList(data);
  }

  Future<void> _openPdfBytesPreview({
    required String fileName,
    required Future<Uint8List> Function() loadBytes,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServiceReportPdfScreen(
          fileName: fileName,
          loadBytes: loadBytes,
          currentUser: ref.read(authStateProvider).user,
        ),
      ),
    );
  }

  Future<CotizacionModel?> _loadLatestQuote(String phone) async {
    final repo = ref.read(cotizacionesRepositoryProvider);
    final items = await repo.list(customerPhone: phone, take: 40);
    if (items.isEmpty) return null;
    final sorted = [...items];
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.first;
  }

  Future<_SignatureBundle> _loadSignatureBundle(ServiceModel service) async {
    final latest = _findLatestFileByType(service, 'client_signature');
    if (latest == null) return const _SignatureBundle();
    final url = latest.fileUrl.trim();
    if (url.isEmpty) return const _SignatureBundle();

    try {
      final bytes = await _downloadBytes(url);
      return _SignatureBundle(
        bytes: bytes,
        fileId: latest.id.trim().isEmpty ? null : latest.id.trim(),
        fileUrl: url,
        signedAt: latest.createdAt,
      );
    } catch (_) {
      return _SignatureBundle(
        bytes: null,
        fileId: latest.id.trim().isEmpty ? null : latest.id.trim(),
        fileUrl: url,
        signedAt: latest.createdAt,
      );
    }
  }

  bool _hasDownloadableUrl(ServiceFileModel? file) {
    if (file == null) return false;
    final uri = Uri.tryParse(file.fileUrl.trim());
    final scheme = (uri?.scheme ?? '').toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  Future<bool> _tryOpenStoredPdf({
    required String fileName,
    required ServiceFileModel? file,
  }) async {
    if (!_hasDownloadableUrl(file)) return false;

    try {
      final bytes = await _downloadBytes(file!.fileUrl.trim());
      await _openPdfBytesPreview(
        fileName: fileName,
        loadBytes: () async => bytes,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onInvoicePressed(ServiceModel service) async {
    final custom = _findLatestFileByType(service, 'service_invoice_custom');
    if (await _tryOpenStoredPdf(
      fileName: 'Factura-${service.orderLabel}.pdf',
      file: custom,
    )) {
      return;
    }

    final invoiceFile = _findClosingFile(
      service,
      service.closing?.invoiceFinalFileId,
    );
    if (await _tryOpenStoredPdf(
      fileName: 'Factura-${service.orderLabel}.pdf',
      file: invoiceFile,
    )) {
      return;
    }

    CotizacionModel? quote;
    try {
      final phone = service.customerPhone.trim();
      quote = phone.isEmpty ? null : await _loadLatestQuote(phone);
    } catch (_) {
      quote = null;
    }

    CompanySettings? company;
    try {
      company = await ref.read(companySettingsProvider.future);
    } catch (_) {
      company = null;
    }

    final sig = await _loadSignatureBundle(service);

    await _openPdfBytesPreview(
      fileName: 'Factura-${service.orderLabel}.pdf',
      loadBytes: () => ServicePdfExporter.buildInvoicePdfBytes(
        service,
        cotizacion: quote,
        company: company,
        clientSignaturePngBytes: sig.bytes,
        clientSignatureFileId: sig.fileId,
        clientSignatureFileUrl: sig.fileUrl,
        clientSignedAt: sig.signedAt,
      ),
    );
  }

  Future<void> _onWarrantyPressed(ServiceModel service) async {
    final custom = _findLatestFileByType(service, 'service_warranty_custom');
    if (await _tryOpenStoredPdf(
      fileName: 'Carta-Garantia-${service.orderLabel}.pdf',
      file: custom,
    )) {
      return;
    }

    final warrantyFile = _findClosingFile(
      service,
      service.closing?.warrantyFinalFileId,
    );
    if (await _tryOpenStoredPdf(
      fileName: 'Carta-Garantia-${service.orderLabel}.pdf',
      file: warrantyFile,
    )) {
      return;
    }

    CotizacionModel? quote;
    try {
      final phone = service.customerPhone.trim();
      quote = phone.isEmpty ? null : await _loadLatestQuote(phone);
    } catch (_) {
      quote = null;
    }

    CompanySettings? company;
    try {
      company = await ref.read(companySettingsProvider.future);
    } catch (_) {
      company = null;
    }

    final sig = await _loadSignatureBundle(service);

    await _openPdfBytesPreview(
      fileName: 'Carta-Garantia-${service.orderLabel}.pdf',
      loadBytes: () => ServicePdfExporter.buildWarrantyLetterBytes(
        service,
        cotizacion: quote,
        company: company,
        clientSignaturePngBytes: sig.bytes,
        clientSignatureFileId: sig.fileId,
        clientSignatureFileUrl: sig.fileUrl,
        clientSignedAt: sig.signedAt,
      ),
    );
  }

  String _statusLabel(String raw) {
    switch (raw) {
      case 'reserved':
        return 'Reserva';
      case 'survey':
        return 'Levantamiento';
      case 'scheduled':
        return 'Servicio (agendado)';
      case 'in_progress':
        return 'Servicio (en proceso)';
      case 'warranty':
        return 'Garantía';
      case 'completed':
        return 'Finalizado';
      case 'closed':
        return 'Cerrado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return raw;
    }
  }

  String _categoryLabel(String raw) {
    return localizedServiceCategoryLabel(raw);
  }

  String _orderTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'reserva':
        return 'Reserva';
      case 'instalacion':
        return 'Instalación';
      case 'mantenimiento':
      case 'servicio':
        return 'Mantenimiento';
      case 'garantia':
        return 'Garantía';
      case 'levantamiento':
        return 'Levantamiento';
      default:
        return raw;
    }
  }

  ({Color background, Color foreground}) _orderStateTone(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'pending':
      case 'pendiente':
        return (
          background: const Color(0xFFFFF1DB),
          foreground: const Color(0xFF9A5800),
        );
      case 'in_progress':
      case 'en_progreso':
      case 'en proceso':
        return (
          background: const Color(0xFFE9F5FF),
          foreground: const Color(0xFF145DA0),
        );
      case 'completed':
      case 'finalizado':
      case 'closed':
      case 'cerrado':
        return (
          background: const Color(0xFFE8F7EE),
          foreground: const Color(0xFF18794E),
        );
      case 'cancelled':
      case 'cancelado':
        return (
          background: const Color(0xFFFCE8E8),
          foreground: const Color(0xFFB42318),
        );
      default:
        return (
          background: const Color(0xFFEEF3FF),
          foreground: const Color(0xFF304E9A),
        );
    }
  }

  String _effectiveOrderState(ServiceModel s) {
    final raw = s.orderState.trim().toLowerCase();
    return raw.isEmpty ? 'pendiente' : raw;
  }

  bool _looksLikeVideoFile(ServiceFileModel file) {
    final mime = (file.mimeType ?? '').trim().toLowerCase();
    if (mime.startsWith('video/')) return true;

    final type = file.fileType.trim().toLowerCase();
    if (type.contains('video')) return true;

    final url = file.fileUrl.trim().toLowerCase();
    return url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.m4v') ||
        url.endsWith('.webm') ||
        url.contains('.mp4?') ||
        url.contains('.mov?') ||
        url.contains('.webm?');
  }

  bool _looksLikeImageFile(ServiceFileModel file) {
    if (_looksLikeVideoFile(file)) return false;
    final mime = (file.mimeType ?? '').trim().toLowerCase();
    if (mime.startsWith('image/')) return true;

    final url = file.fileUrl.trim().toLowerCase();
    return url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.png') ||
        url.endsWith('.webp') ||
        url.endsWith('.heic') ||
        url.contains('.jpg?') ||
        url.contains('.jpeg?') ||
        url.contains('.png?') ||
        url.contains('.webp?');
  }

  bool _isVisibleEvidenceFile(ServiceFileModel file) {
    final type = file.fileType.trim().toLowerCase();
    final mime = (file.mimeType ?? type).trim().toLowerCase();
    if (type.isEmpty) return true;
    if (type.contains('invoice') ||
        type.contains('warranty') ||
        mime.contains('pdf') ||
        type.contains('signature')) {
      return false;
    }
    return true;
  }

  List<OrderInfoItem> _phaseSpecificItems(
    ServiceModel service,
    ServiceExecutionBundleModel? bundle,
    DateFormat dateFormat,
  ) {
    final items = <OrderInfoItem>[];
    final normalizedOrderType = _normalizeAgendaKindValue(
      service.orderType,
      fallback: service.currentPhase.trim().toLowerCase().isEmpty
          ? 'mantenimiento'
          : service.currentPhase.trim().toLowerCase(),
    );

    if ((service.surveyResult ?? '').trim().isNotEmpty) {
      items.add(
        OrderInfoItem(
          icon: Icons.rule_folder_outlined,
          label: 'Resultado de levantamiento',
          value: service.surveyResult!.trim(),
        ),
      );
    }

    if ((service.materialsUsed ?? '').trim().isNotEmpty) {
      items.add(
        OrderInfoItem(
          icon: Icons.inventory_2_outlined,
          label: normalizedOrderType == 'instalacion'
              ? 'Materiales usados'
              : 'Trabajo y materiales',
          value: service.materialsUsed!.trim(),
        ),
      );
    }

    if (service.finalCost != null) {
      items.add(
        OrderInfoItem(
          icon: Icons.price_check_outlined,
          label: 'Costo final de ejecución',
          value: 'RD\$${service.finalCost!.toStringAsFixed(2)}',
        ),
      );
    }

    final report = bundle?.report;
    if (report != null) {
      if (report.arrivedAt != null) {
        items.add(
          OrderInfoItem(
            icon: Icons.login_outlined,
            label: 'Llegada técnica',
            value: dateFormat.format(report.arrivedAt!),
          ),
        );
      }
      if (report.startedAt != null) {
        items.add(
          OrderInfoItem(
            icon: Icons.play_circle_outline,
            label: 'Inicio técnico',
            value: dateFormat.format(report.startedAt!),
          ),
        );
      }
      if (report.finishedAt != null) {
        items.add(
          OrderInfoItem(
            icon: Icons.task_alt_outlined,
            label: 'Fin técnico',
            value: dateFormat.format(report.finishedAt!),
          ),
        );
      }
      if ((report.notes ?? '').trim().isNotEmpty) {
        items.add(
          OrderInfoItem(
            icon: Icons.sticky_note_2_outlined,
            label: 'Notas del técnico',
            value: report.notes!.trim(),
          ),
        );
      }

      final phaseSpecificData =
          report.phaseSpecificData ?? const <String, dynamic>{};
      const phaseFieldLabels = <String, String>{
        'equipmentInstalled': 'Equipos instalados',
        'cableMetersUsed': 'Metros de cable usados',
        'maintenancePerformed': 'Mantenimiento realizado',
        'equipmentCondition': 'Condición de equipos',
        'failureDetected': 'Falla detectada',
        'partsReplaced': 'Piezas reemplazadas',
        'equipmentRequired': 'Equipos requeridos',
        'estimatedMaterials': 'Materiales estimados',
      };

      for (final entry in phaseSpecificData.entries) {
        if (entry.key == 'clientSignature') continue;
        final value = (entry.value ?? '').toString().trim();
        if (value.isEmpty) continue;
        items.add(
          OrderInfoItem(
            icon: Icons.assignment_turned_in_outlined,
            label: phaseFieldLabels[entry.key] ?? entry.key,
            value: value,
          ),
        );
      }
    }

    return items;
  }

  String _serviceFileTypeLabel(ServiceFileModel file) {
    if (_looksLikeVideoFile(file)) return 'Video';
    if (_looksLikeImageFile(file)) return 'Imagen';

    final type = file.fileType.trim().toLowerCase();
    if (type.contains('evidence')) return 'Evidencia';
    return 'Archivo';
  }

  String _serviceFileTitle(ServiceFileModel file) {
    final caption = (file.caption ?? '').trim();
    if (caption.isNotEmpty) return caption;
    final type = file.fileType.trim();
    if (type.isNotEmpty) return type;
    return 'Adjunto';
  }

  Future<void> _openServiceFile(ServiceFileModel file) async {
    final uri = Uri.tryParse(file.fileUrl.trim());
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Archivo no disponible')));
      return;
    }
    await safeOpenUrl(context, uri, copiedMessage: 'Enlace copiado');
  }

  String _activityMessage(ServiceUpdateModel update) {
    final message = update.message.trim();
    if (message.startsWith('[REF]')) return 'Referencia del cliente registrada';
    if (message.startsWith('[PAGO]')) return 'Estado de pago actualizado';
    if (message.isNotEmpty) return message;
    final type = update.type.trim();
    return type.isEmpty ? 'Movimiento registrado' : type;
  }

  bool _isVisibleActivity(ServiceUpdateModel update) {
    final message = update.message.trim();
    if (message.isEmpty) return true;
    return !message.startsWith('[REF]');
  }

  Future<void> _setStatusWithConfirm(
    String targetStatus, {
    bool closePanel = true,
  }) async {
    final service = _service;
    if (targetStatus == service.status) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar cambio'),
          content: Text(
            'Vas a cambiar la etapa de "${_statusLabel(service.status)}" a "${_statusLabel(targetStatus)}".\n\n¿Seguro que deseas hacerlo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (!mounted || ok != true) return;

    await widget.onChangeStatus(targetStatus);
    if (!mounted) return;

    setState(() {
      _service = _service.copyWith(status: targetStatus);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Etapa: ${_statusLabel(targetStatus)}')),
    );

    if (closePanel) {
      // Mantiene el comportamiento anterior cuando se cambia desde Acciones.
      Navigator.pop(context);
    }
  }

  Future<void> _pickScheduleFlow(ServiceModel service) async {
    final now = DateTime.now();
    final startInitial = service.scheduledStart ?? now;
    final start = await _pickDateTime(
      helpText: 'Selecciona inicio',
      initial: startInitial,
    );
    if (!mounted) return;
    if (start == null) return;

    final endInitial =
        service.scheduledEnd ?? start.add(const Duration(hours: 2));
    final end = await _pickDateTime(
      helpText: 'Selecciona fin',
      initial: endInitial,
    );
    if (!mounted) return;
    if (end == null) return;

    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El fin debe ser posterior al inicio')),
      );
      return;
    }

    await widget.onSchedule(start, end);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Agenda actualizada')));

    Navigator.pop(context);
  }

  Future<void> _assignTechsFlow() async {
    final ids = await _askTechIds(context);
    if (ids == null || ids.isEmpty) return;
    await widget.onAssign(
      ids
          .map((id) => <String, String>{'userId': id, 'role': 'assistant'})
          .toList(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Técnicos asignados')));
  }

  Future<DateTime?> _pickDateTime({
    required String helpText,
    required DateTime initial,
  }) async {
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      initialDate: DateTime(initial.year, initial.month, initial.day),
      helpText: helpText,
    );
    if (!mounted || pickedDate == null) return null;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted || pickedTime == null) return null;

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Future<void> _deleteWithConfirm(ServiceModel service) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar servicio'),
          content: Text(
            'Vas a eliminar "${service.title.trim().isEmpty ? 'Servicio' : service.title.trim()}".\n\nEsta acción no se puede deshacer. ¿Seguro que deseas hacerlo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (!mounted || ok != true) return;

    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .deleteService(service.id);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Servicio eliminado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opsState = ref.watch(operationsControllerProvider);
    ServiceModel service = _service;
    for (final s in opsState.services) {
      if (s.id == _service.id) {
        service = s;
        break;
      }
    }
    final dateFormat = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');

    final auth = ref.watch(authStateProvider);
    final user = auth.user;

    final perms = OperationsPermissions(user: user, service: service);
    final canOperate = perms.canOperate;
    final canDelete = perms.canDelete;
    final canEdit = perms.canCritical;
    final allowedStatusTargets = perms.allowedNextStatuses();

    final typeText = _effectiveServiceKindLabel(service);
    final categoryText = _categoryLabel(service.category);
    final descText = service.description.trim();
    final customerName = service.customerName.trim().isEmpty
        ? 'Cliente'
        : service.customerName.trim();
    final customerPhone = service.customerPhone.trim();
    final addressText = service.customerAddress.trim();

    final techNames = service.assignments
        .map((a) => a.userName.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    final tags = service.tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    String money(double? v) {
      if (v == null) return '—';
      final safe = v.isNaN ? 0.0 : v;
      return 'RD\$${safe.toStringAsFixed(2)}';
    }

    final payment = _extractPaymentInfo(service);

    final referenceText = _extractLatestReferenceText(service);
    if (_referenceMediaFuture == null || _lastReferenceText != referenceText) {
      _lastReferenceText = referenceText;
      _referenceMediaFuture = _loadReferenceMedia(service.id);
    }

    final statusChipValue = _effectiveOrderState(service);

    final location = buildServiceLocationInfo(addressOrText: addressText);
    final executionBundleFuture =
        _executionBundleFuture ?? _loadExecutionBundle(service.id);

    Future<void> editFlow() async {
      final messenger = ScaffoldMessenger.of(context);

      if (!canEdit) {
        final reason = perms.criticalDeniedReason ?? 'No autorizado';
        messenger.showSnackBar(SnackBar(content: Text(reason)));
        return;
      }

      final result = await _showOperationsServiceFullEditForm(context, service);

      if (!mounted || result == null) return;

      try {
        final updated = await ref
            .read(operationsControllerProvider.notifier)
            .updateService(
              serviceId: service.id,
              serviceType: result.serviceType,
              orderType: result.orderType,
              categoryId: result.categoryId,
              category: result.categoryCode,
              priority: result.priority,
              title: result.title,
              description: result.description,
              quotedAmount: result.quotedAmount,
              depositAmount: result.depositAmount,
              addressSnapshot: result.addressSnapshot,
              warrantyParentServiceId: result.relatedServiceId,
              surveyResult: result.surveyResult,
              materialsUsed: result.materialsUsed,
              finalCost: result.finalCost,
              orderState: result.orderState,
              technicianId: result.technicianId,
              tags: result.tags,
            );
        if (!mounted) return;
        setState(() => _service = updated);
        messenger.showSnackBar(
          const SnackBar(content: Text('Orden actualizada')),
        );
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : '$e')),
        );
      }
    }

    Future<void> openActions() async {
      final messenger = ScaffoldMessenger.of(context);

      await ServiceActionsSheet.show(
        context,
        service: service,
        canOperate: canOperate,
        operateDeniedReason: perms.operateDeniedReason,
        canEdit: canEdit,
        editDeniedReason: perms.criticalDeniedReason,
        canChangePhase: perms.canChangePhase,
        changePhaseDeniedReason: perms.changePhaseDeniedReason,
        canChangeAdminPhase: perms.canChangeAdminPhase,
        changeAdminPhaseDeniedReason: perms.changeAdminPhaseDeniedReason,
        onChangeAdminPhase: (adminPhase) async {
          try {
            final updated = await ref
                .read(operationsControllerProvider.notifier)
                .changeAdminPhaseOptimistic(service.id, adminPhase);

            if (!mounted) return;
            setState(() => _service = updated);
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Fase administrativa: ${adminPhaseLabel(updated.adminPhase ?? adminPhase)}',
                ),
              ),
            );
          } catch (e) {
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(e is ApiException ? e.message : '$e')),
            );
          }
        },
        onChangePhase: (phase, scheduledAt, note) async {
          final missing = _missingPhaseRequirements(service, phase);
          if (missing.isNotEmpty) {
            final goEdit = await _showPhaseValidationPrompt(
              this.context,
              phase: phase,
              data: _PhaseValidationPromptData(missing: missing),
              canEdit: canEdit,
              actionLabel: 'Editar datos',
            );
            if (!mounted) return;
            if (goEdit == true) {
              await editFlow();
            }
            return;
          }
          try {
            final updated = await ref
                .read(operationsControllerProvider.notifier)
                .changePhaseOptimistic(
                  service.id,
                  phase,
                  scheduledAt: scheduledAt,
                  note: note,
                );

            if (!mounted) return;
            setState(() => _service = updated);
            await _loadPhaseHistory();
            if (!mounted) return;

            messenger.showSnackBar(
              SnackBar(
                content: Text('Fase: ${phaseLabel(updated.currentPhase)}'),
              ),
            );

            final nextPhase = updated.currentPhase.trim().toLowerCase();
            final currentOrderState = updated.orderState.trim().toLowerCase();
            if (nextPhase == 'instalacion' && currentOrderState == 'pending') {
              if (!context.mounted) return;
              final applySuggested = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Sugerencia'),
                    content: const Text(
                      'Esta fase normalmente usa el estado de orden "En progreso". ¿Deseas aplicarlo también?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('No'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Aplicar'),
                      ),
                    ],
                  );
                },
              );

              if (!mounted || applySuggested != true) return;
              await widget.onChangeOrderState('in_progress');
              if (!mounted) return;
              setState(() {
                _service = _service.copyWith(orderState: 'in_progress');
              });
            }
          } catch (e) {
            if (!mounted) return;
            final prompt = _phaseValidationPromptDataFromError(e);
            if (prompt != null) {
              final goEdit = await _showPhaseValidationPrompt(
                this.context,
                phase: phase,
                data: prompt,
                canEdit: canEdit,
                actionLabel: 'Editar datos',
              );
              if (!mounted) return;
              if (goEdit) {
                await editFlow();
              }
              return;
            }
            messenger.showSnackBar(
              SnackBar(content: Text(e is ApiException ? e.message : '$e')),
            );
          }
        },
        allowedStatusTargets: allowedStatusTargets,
        canDelete: canDelete,
        deleteDeniedReason: perms.criticalDeniedReason,
        onEdit: editFlow,
        onChangeStatus: (status) => _setStatusWithConfirm(status),
        onPickSchedule: () => _pickScheduleFlow(service),
        onAssignTechs: _assignTechsFlow,
        onCreateWarranty: widget.onCreateWarranty,
        onDelete: () => _deleteWithConfirm(service),
        onAddNote: (message) async {
          await widget.onAddNote(message);
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(content: Text('Marcado en historial')),
          );
        },
        onMarkPendingBy: (reason) async {
          await widget.onAddNote('Pendiente por: $reason');
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(content: Text('Marcado como pendiente')),
          );
        },
        onUploadEvidence: () async {
          await widget.onUploadEvidence();
          await _refreshServiceDetail(silent: false);
        },
      );
    }

    final statusTone = _orderStateTone(statusChipValue);
    final canOpenQuote = customerPhone.isNotEmpty;

    final visibleUpdates = service.updates
        .where(_isVisibleActivity)
        .toList(growable: false);
    final recentEntries = visibleUpdates.reversed
        .take(4)
        .map((update) {
          final metaDate = update.createdAt == null
              ? '-'
              : dateFormat.format(update.createdAt!);
          return OrderNoteEntry(
            message: _activityMessage(update),
            meta: '${update.changedBy} · $metaDate',
          );
        })
        .toList(growable: false);

    String invoiceStatus() {
      final c = service.closing;
      if (c == null) return 'No generada';
      if ((c.invoiceFinalFileId ?? '').isNotEmpty) return 'Final';
      if ((c.invoiceApprovedFileId ?? '').isNotEmpty) return 'Aprobada';
      if ((c.invoiceDraftFileId ?? '').isNotEmpty) {
        return 'Pendiente aprobación';
      }
      return 'En proceso';
    }

    String warrantyStatus() {
      final c = service.closing;
      if (c == null) return 'No generada';
      if ((c.warrantyFinalFileId ?? '').isNotEmpty) return 'Final';
      if ((c.warrantyApprovedFileId ?? '').isNotEmpty) return 'Aprobada';
      if ((c.warrantyDraftFileId ?? '').isNotEmpty) {
        return 'Pendiente aprobación';
      }
      return 'En proceso';
    }

    String signatureStatus() {
      final s = service.closing?.signatureStatus.toUpperCase().trim() ?? '';
      if (s == 'SIGNED') return 'Firmada';
      if (s == 'SKIPPED') return 'No firmada';
      if (s == 'PENDING') return 'Pendiente';
      return s.isEmpty ? 'N/D' : s;
    }

    final primaryInfoItems = <OrderInfoItem>[
      OrderInfoItem(
        icon: Icons.assignment_outlined,
        label: 'Orden',
        value: service.orderLabel,
        caption: _orderTypeLabel(service.orderType),
      ),
      OrderInfoItem(
        icon: Icons.flag_outlined,
        label: 'Fase actual',
        value: phaseLabel(service.currentPhase),
      ),
      OrderInfoItem(
        icon: Icons.task_alt_outlined,
        label: 'Estado',
        value: StatusPickerSheet.label(statusChipValue),
        caption: canOperate ? 'Gestionable desde Otros' : null,
      ),
      OrderInfoItem(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Pago',
        value: _paymentStatusLabel(payment.status),
        caption: payment.method == null
            ? null
            : _paymentMethodLabel(payment.method!),
      ),
      if (service.quotedAmount != null)
        OrderInfoItem(
          icon: Icons.request_quote_outlined,
          label: 'Cotizado',
          value: money(service.quotedAmount),
        ),
      if (service.depositAmount != null)
        OrderInfoItem(
          icon: Icons.savings_outlined,
          label: 'Abono',
          value: money(service.depositAmount),
        ),
      if (service.finalCost != null)
        OrderInfoItem(
          icon: Icons.price_check_outlined,
          label: 'Costo final',
          value: money(service.finalCost),
        ),
      OrderInfoItem(
        icon: Icons.receipt_long_outlined,
        label: 'Factura',
        value: invoiceStatus(),
      ),
      OrderInfoItem(
        icon: Icons.verified_outlined,
        label: 'Garantía',
        value: warrantyStatus(),
      ),
      OrderInfoItem(
        icon: Icons.draw_outlined,
        label: 'Firma cliente',
        value: signatureStatus(),
      ),
    ];

    final serviceInfoItems = <OrderInfoItem>[
      OrderInfoItem(
        icon: Icons.miscellaneous_services_outlined,
        label: 'Tipo de servicio',
        value: typeText,
      ),
      if (categoryText.trim().isNotEmpty)
        OrderInfoItem(
          icon: Icons.category_outlined,
          label: 'Categoría',
          value: categoryText,
        ),
      if (service.createdAt != null)
        OrderInfoItem(
          icon: Icons.event_available_outlined,
          label: 'Creada',
          value: dateFormat.format(service.createdAt!),
        ),
      if (service.scheduledStart != null)
        OrderInfoItem(
          icon: Icons.schedule_outlined,
          label: 'Inicio',
          value: dateFormat.format(service.scheduledStart!),
        ),
      if (service.scheduledEnd != null)
        OrderInfoItem(
          icon: Icons.update_outlined,
          label: 'Fin',
          value: dateFormat.format(service.scheduledEnd!),
        ),
      if (service.completedAt != null)
        OrderInfoItem(
          icon: Icons.task_alt_outlined,
          label: 'Completado',
          value: dateFormat.format(service.completedAt!),
        ),
      if (techNames.isNotEmpty)
        OrderInfoItem(
          icon: Icons.engineering_outlined,
          label: 'Técnico asignado',
          value: techNames.join(', '),
        ),
      if (location.canOpenMaps || addressText.isNotEmpty)
        OrderInfoItem(
          icon: Icons.location_on_outlined,
          label: 'Ubicación',
          value: location.label,
          caption: location.canOpenMaps ? 'Disponible para abrir' : null,
        ),
      if (service.createdByName.trim().isNotEmpty)
        OrderInfoItem(
          icon: Icons.person_outline_rounded,
          label: 'Creado por',
          value: service.createdByName.trim(),
        ),
      if (tags.isNotEmpty)
        OrderInfoItem(
          icon: Icons.sell_outlined,
          label: 'Etiquetas',
          value: tags.join(', '),
        ),
    ];

    Future<void> handleHeaderAction(OrderActionsMenuAction action) async {
      switch (action) {
        case OrderActionsMenuAction.call:
          final phone = customerPhone.trim();
          if (phone.isEmpty) return;
          await safeOpenUrl(
            this.context,
            Uri.parse('tel:$phone'),
            copiedMessage: 'Número copiado',
          );
          return;
        case OrderActionsMenuAction.location:
          final uri = location.mapsUri;
          if (uri == null) return;
          await safeOpenUrl(this.context, uri, copiedMessage: 'Link copiado');
          return;
        case OrderActionsMenuAction.quote:
          if (!canOpenQuote) return;
          final uri = Uri(
            path: Routes.cotizacionesHistorial,
            queryParameters: {'customerPhone': customerPhone, 'pick': '0'},
          );
          if (!mounted) return;
          this.context.go(uri.toString());
          return;
        case OrderActionsMenuAction.invoice:
          await _onInvoicePressed(service);
          return;
        case OrderActionsMenuAction.warranty:
          await _onWarrantyPressed(service);
          return;
        case OrderActionsMenuAction.others:
          await openActions();
          return;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OrderHeader(
          customerName: customerName,
          orderLabel: customerPhone.isEmpty
              ? service.orderLabel
              : '${service.orderLabel} · $customerPhone',
          statusLabel: StatusPickerSheet.label(statusChipValue),
          statusBackground: statusTone.background,
          statusForeground: statusTone.foreground,
          priorityLabel: service.priority > 0 ? 'P${service.priority}' : null,
          categoryLabel: categoryText.trim().isEmpty ? null : categoryText,
          serviceTypeLabel: typeText.trim().isEmpty ? null : typeText,
          actionsMenu: OrderActionsMenu(
            canCall: customerPhone.isNotEmpty,
            canOpenLocation: location.canOpenMaps,
            canOpenQuote: canOpenQuote,
            canOpenInvoice: true,
            canOpenWarranty: true,
            onSelected: handleHeaderAction,
          ),
        ),
        if (canEdit) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: editFlow,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar orden'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        OrderInfoSection(
          title: 'Información principal de la orden',
          icon: Icons.space_dashboard_outlined,
          items: primaryInfoItems,
        ),
        const SizedBox(height: 12),
        OrderDocumentsSection(
          items: [
            OrderDocumentActionItem(
              icon: Icons.receipt_long_outlined,
              title: 'Factura',
              status: invoiceStatus(),
              caption:
                  'Abre la factura final si existe; si no, genera una versión actualizada con los datos del servicio.',
              onPressed: () {
                unawaited(_onInvoicePressed(service));
              },
            ),
            OrderDocumentActionItem(
              icon: Icons.verified_outlined,
              title: 'Carta de garantía',
              status: warrantyStatus(),
              caption:
                  'Abre la carta final guardada o genera la vista actual desde la información de la orden.',
              onPressed: () {
                unawaited(_onWarrantyPressed(service));
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<ServiceExecutionBundleModel>(
          future: executionBundleFuture,
          builder: (context, snapshot) {
            final items = _phaseSpecificItems(
              service,
              snapshot.data,
              dateFormat,
            );
            if (items.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              children: [
                OrderInfoSection(
                  title: 'Detalles según fase y ejecución',
                  icon: Icons.fact_check_outlined,
                  items: items,
                ),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
        FutureBuilder<List<ServiceMediaModel>>(
          future: _referenceMediaFuture,
          builder: (context, snap) {
            final visibleFiles = service.evidences
                .where(_isVisibleEvidenceFile)
                .toList(growable: false);
            final fileItems = visibleFiles
                .map(
                  (file) => OrderEvidenceItem(
                    id: file.id,
                    title: _serviceFileTitle(file),
                    url: file.fileUrl,
                    typeLabel: _serviceFileTypeLabel(file),
                    meta: file.createdAt == null
                        ? null
                        : dateFormat.format(file.createdAt!),
                    isImage: _looksLikeImageFile(file),
                    isVideo: _looksLikeVideoFile(file),
                  ),
                )
                .toList(growable: false);
            final evidenceItems = fileItems;

            debugPrint(
              'Evidences: ${service.evidences.map((file) => '${file.id}:${file.fileType}').toList(growable: false)}',
            );

            return EvidenceGallery(
              referenceText: referenceText,
              items: evidenceItems,
              onOpenItem: (item) async {
                final file = visibleFiles
                    .where((f) => f.id == item.id)
                    .firstOrNull;
                if (file != null) {
                  await _openServiceFile(file);
                }
              },
            );
          },
        ),
        const SizedBox(height: 12),
        NotesSection(
          note: descText.isEmpty ? null : descText,
          controller: _noteCtrl,
          recentEntries: recentEntries,
          onSave: () async {
            final note = _noteCtrl.text.trim();
            if (note.isEmpty) return;
            try {
              await widget.onAddNote(note);
              if (!mounted) return;
              _noteCtrl.clear();
              ScaffoldMessenger.of(
                this.context,
              ).showSnackBar(const SnackBar(content: Text('Nota guardada')));
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(content: Text(e is ApiException ? e.message : '$e')),
              );
            }
          },
        ),
        const SizedBox(height: 12),
        OrderInfoSection(
          title: 'Información del servicio',
          icon: Icons.widgets_outlined,
          items: serviceInfoItems,
        ),
        const SizedBox(height: 12),
        ChecklistSection(
          steps: service.steps,
          formatDate: (value) => value == null ? '-' : dateFormat.format(value),
        ),
        const SizedBox(height: 12),
        PhaseTimeline(
          isLoading: _phaseHistoryLoading,
          errorText: _phaseHistoryError,
          items: _phaseHistory,
          formatDate: (value) => value == null ? '-' : dateFormat.format(value),
          phaseLabelBuilder: phaseLabel,
        ),
      ],
    );
  }

  Future<List<String>?> _askTechIds(BuildContext context) async {
    final ctrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Asignar técnicos'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              hintText: 'UUID1, UUID2, UUID3',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Asignar'),
            ),
          ],
        ),
      );
      if (ok != true) return null;

      final value = ctrl.text.trim();
      if (value.isEmpty) return null;
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    } finally {
      ctrl.dispose();
    }
  }

  // ignore: unused_element
  Future<String?> _askReason(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Motivo pendiente'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          minLines: 2,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final text = ctrl.text;
    ctrl.dispose();
    return ok == true ? text : null;
  }

  // ignore: unused_element
  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _VideoReferenceViewer extends StatefulWidget {
  final String url;

  const _VideoReferenceViewer({required this.url});

  @override
  State<_VideoReferenceViewer> createState() => _VideoReferenceViewerState();
}

class _VideoReferenceViewerState extends State<_VideoReferenceViewer> {
  VideoPlayerController? _controller;
  Future<void>? _init;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url.trim());
    if (uri == null) return;
    final c = VideoPlayerController.networkUrl(uri);
    _controller = c;
    _init = c.initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || _init == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Video inválido'),
      );
    }

    return FutureBuilder<void>(
      future: _init,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No se pudo cargar el video'),
          );
        }

        final aspect = controller.value.aspectRatio;
        final safeAspect = (aspect.isFinite && aspect > 0) ? aspect : (16 / 9);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: safeAspect,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: VideoPlayer(controller),
                    ),
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            if (!mounted) return;
                            setState(() {
                              if (controller.value.isPlaying) {
                                controller.pause();
                              } else {
                                controller.play();
                              }
                            });
                          },
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surface.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outline.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Icon(
                                controller.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ],
        );
      },
    );
  }
}

class _LocalReferenceVideoViewer extends StatefulWidget {
  final PlatformFile file;

  const _LocalReferenceVideoViewer({required this.file});

  @override
  State<_LocalReferenceVideoViewer> createState() =>
      _LocalReferenceVideoViewerState();
}

class _LocalReferenceVideoViewerState
    extends State<_LocalReferenceVideoViewer> {
  VideoPlayerController? _controller;
  Future<void>? _init;

  @override
  void initState() {
    super.initState();
    final controller = createVideoPreviewController(
      path: widget.file.path,
      bytes: widget.file.bytes,
      fileName: widget.file.name,
    );
    if (controller == null) return;

    controller.setLooping(false);
    _controller = controller;
    _init = controller.initialize().then((_) async {
      try {
        await controller.seekTo(const Duration(milliseconds: 1));
      } catch (_) {
        // ignore
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = _controller;
    final init = _init;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.file.name.trim().isEmpty
              ? 'Video de referencia'
              : widget.file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: (controller == null || init == null)
            ? const Center(
                child: Text(
                  'Video inválido',
                  style: TextStyle(color: Colors.white),
                ),
              )
            : FutureBuilder<void>(
                future: init,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snap.hasError || !controller.value.isInitialized) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No se pudo cargar el video.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  }

                  final aspect = controller.value.aspectRatio == 0
                      ? (16 / 9)
                      : controller.value.aspectRatio;

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: aspect,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    if (controller.value.isPlaying) {
                                      controller.pause();
                                    } else {
                                      controller.play();
                                    }
                                  });
                                },
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    VideoPlayer(controller),
                                    if (!controller.value.isPlaying)
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: scheme.surface.withValues(
                                            alpha: 0.88,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 34,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _PaymentInfo {
  final String status;
  final double? amount;
  final String? method;

  const _PaymentInfo({required this.status, this.amount, this.method});
}

String _buildReferenceNote(String text) {
  final t = text.trim();
  return '[REF] $t';
}

bool _isVideoFile(PlatformFile file) {
  String extOf(PlatformFile f) {
    final direct = (f.extension ?? '').trim();
    if (direct.isNotEmpty) return direct;
    final name = f.name.trim();
    final i = name.lastIndexOf('.');
    if (i < 0) return '';
    return name.substring(i + 1);
  }

  final ext = extOf(file).trim().toLowerCase();
  return ext == 'mp4' ||
      ext == 'mov' ||
      ext == 'm4v' ||
      ext == 'avi' ||
      ext == 'mkv' ||
      ext == 'webm' ||
      ext == '3gp';
}

String _guessMimeTypeForPlatformFile(PlatformFile file) {
  String extOf(PlatformFile f) {
    final direct = (f.extension ?? '').trim();
    if (direct.isNotEmpty) return direct;
    final name = f.name.trim();
    final i = name.lastIndexOf('.');
    if (i < 0) return '';
    return name.substring(i + 1);
  }

  final ext = extOf(file).trim().toLowerCase();
  if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
  if (ext == 'png') return 'image/png';
  if (ext == 'webp') return 'image/webp';
  if (ext == 'heic') return 'image/heic';
  if (ext == 'heif') return 'image/heif';
  if (ext == 'mp4') return 'video/mp4';
  if (ext == 'mov') return 'video/quicktime';
  if (ext == 'm4v') return 'video/x-m4v';
  if (ext == 'webm') return 'video/webm';
  if (ext == '3gp') return 'video/3gpp';
  return 'application/octet-stream';
}

Future<void> _uploadPlatformFileDirectToStorage({
  required WidgetRef ref,
  required String serviceId,
  required PlatformFile file,
  required String caption,
}) async {
  final mimeType = _guessMimeTypeForPlatformFile(file);
  final kind = _isVideoFile(file) || mimeType.startsWith('video/')
      ? 'video_evidence'
      : 'evidence_final';

  final storage = ref.read(storageRepositoryProvider);
  final presign = await storage.presign(
    serviceId: serviceId,
    fileName: file.name,
    contentType: mimeType,
    fileSize: file.size,
    kind: kind,
  );

  await storage.uploadToPresignedUrl(
    uploadUrl: presign.uploadUrl,
    bytes: file.bytes,
    stream: kIsWeb ? null : file.readStream,
    contentType: mimeType,
    contentLength: file.size,
  );

  await storage.confirm(
    serviceId: serviceId,
    objectKey: presign.objectKey,
    publicUrl: presign.publicUrl,
    fileName: file.name,
    mimeType: mimeType,
    fileSize: file.size,
    kind: kind,
    caption: caption.trim().isEmpty ? null : caption.trim(),
  );
}

Future<void> _postCreateUploadReferences({
  required WidgetRef ref,
  required String serviceId,
  required String referenceText,
  required List<PlatformFile> images,
  PlatformFile? video,
}) async {
  final text = referenceText.trim();
  final hasMedia = images.isNotEmpty || video != null;
  if (text.isEmpty && !hasMedia) return;

  if (text.isNotEmpty) {
    // Guardar texto cuando exista, aunque no haya medios.
    try {
      await ref
          .read(operationsRepositoryProvider)
          .addUpdate(
            serviceId: serviceId,
            type: 'note',
            message: _buildReferenceNote(text),
          );
    } catch (_) {
      // No bloquea la creación.
    }
  }

  for (final img in images) {
    await _uploadPlatformFileDirectToStorage(
      ref: ref,
      serviceId: serviceId,
      file: img,
      caption: text,
    );
  }

  if (video != null) {
    await _uploadPlatformFileDirectToStorage(
      ref: ref,
      serviceId: serviceId,
      file: video,
      caption: text,
    );
  }

  await ref.read(operationsControllerProvider.notifier).refresh();
}

String _buildPaymentNote({
  required String status,
  double? amount,
  String? method,
}) {
  final normalizedStatus = status.trim().toLowerCase().isEmpty
      ? 'pendiente'
      : status.trim().toLowerCase();
  final parts = <String>['[PAGO]', 'estado=$normalizedStatus'];
  if (normalizedStatus == 'pagado') {
    if (amount != null) {
      final safe = amount.isNaN ? 0.0 : amount;
      parts.add('monto=${safe.toStringAsFixed(2)}');
    }
    final m = (method ?? '').trim().toLowerCase();
    if (m.isNotEmpty) parts.add('metodo=$m');
  }
  return parts.join(' ');
}

_PaymentInfo _extractPaymentInfo(ServiceModel service) {
  final updates = service.updates;

  Map<String, String> parseKv(String raw) {
    final tokens = raw.split(RegExp(r'\s+'));
    final out = <String, String>{};
    for (final token in tokens) {
      final i = token.indexOf('=');
      if (i <= 0) continue;
      final k = token.substring(0, i).trim().toLowerCase();
      final v = token.substring(i + 1).trim();
      if (k.isEmpty || v.isEmpty) continue;
      out[k] = v;
    }
    return out;
  }

  for (var i = updates.length - 1; i >= 0; i--) {
    final msg = updates[i].message.trim();
    if (!msg.startsWith('[PAGO]')) continue;
    final rest = msg.substring('[PAGO]'.length).trim();
    final kv = parseKv(rest);

    final status = (kv['estado'] ?? kv['status'] ?? 'pendiente')
        .trim()
        .toLowerCase();
    final method = (kv['metodo'] ?? kv['method'])?.trim().toLowerCase();
    final amountRaw = kv['monto'] ?? kv['amount'];
    final amount = amountRaw == null ? null : double.tryParse(amountRaw);

    return _PaymentInfo(
      status: status.isEmpty ? 'pendiente' : status,
      amount: amount,
      method: method == null || method.isEmpty ? null : method,
    );
  }

  return const _PaymentInfo(status: 'pendiente');
}

String _paymentStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'pagado':
      return 'Pagado';
    case 'pendiente':
      return 'Pendiente';
    default:
      return status.trim().isEmpty ? 'Pendiente' : status;
  }
}

String _paymentMethodLabel(String method) {
  switch (method.trim().toLowerCase()) {
    case 'efectivo':
      return 'Efectivo';
    case 'transferencia':
      return 'Transferencia';
    case 'tarjeta':
      return 'Tarjeta';
    default:
      return method.trim().isEmpty ? '—' : method;
  }
}

class OperacionesHistorialBody extends ConsumerStatefulWidget {
  const OperacionesHistorialBody({super.key});

  @override
  ConsumerState<OperacionesHistorialBody> createState() =>
      OperacionesHistorialBodyState();
}

class OperacionesHistorialBodyState
    extends ConsumerState<OperacionesHistorialBody> {
  bool _loading = false;
  String? _error;
  List<ServiceModel> _items = const [];
  String _query = '';

  static const int _pageSize = 120;
  static const int _maxPages = 25;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(operationsRepositoryProvider);

      Future<List<ServiceModel>> listAllByStatus(String status) async {
        final all = <ServiceModel>[];
        for (var page = 1; page <= _maxPages; page++) {
          final res = await repo.listServices(
            status: status,
            page: page,
            pageSize: _pageSize,
          );
          all.addAll(res.items);
          if (res.items.length < _pageSize) break;
        }
        return all;
      }

      final results = await Future.wait([
        listAllByStatus('completed'),
        listAllByStatus('closed'),
      ]);

      final completed = results[0];
      final closed = results[1];

      final byId = <String, ServiceModel>{
        for (final item in completed) item.id: item,
        for (final item in closed) item.id: item,
      };

      DateTime? lastUpdateAt(ServiceModel s) {
        final dates = s.updates
            .map((u) => u.createdAt)
            .whereType<DateTime>()
            .toList();
        if (dates.isEmpty) return null;
        dates.sort();
        return dates.last;
      }

      final merged = byId.values.toList()
        ..sort((a, b) {
          final ad = lastUpdateAt(a) ?? a.completedAt;
          final bd = lastUpdateAt(b) ?? b.completedAt;
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });

      if (!mounted) return;
      setState(() {
        _items = merged;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'No se pudo cargar historial';
      });
    }
  }

  String _statusLabel(String raw) {
    switch (raw) {
      case 'completed':
        return 'Finalizada';
      case 'closed':
        return 'Cerrada';
      case 'cancelled':
        return 'Cancelada';
      default:
        return raw;
    }
  }

  // ignore: unused_element
  String _typeLabel(String raw) {
    switch (raw) {
      case 'installation':
        return 'Instalación';
      case 'maintenance':
        return 'Servicio técnico';
      case 'warranty':
        return 'Garantía';
      case 'pos_support':
        return 'Soporte POS';
      case 'other':
        return 'Otro';
      default:
        return raw;
    }
  }

  IconData _typeIcon(String raw) {
    switch (raw) {
      case 'installation':
        return Icons.handyman_outlined;
      case 'maintenance':
        return Icons.build_circle_outlined;
      case 'warranty':
        return Icons.verified_outlined;
      case 'pos_support':
        return Icons.point_of_sale_outlined;
      default:
        return Icons.work_outline;
    }
  }

  DateTime? _lastUpdateAt(ServiceModel s) {
    final dates = s.updates
        .map((u) => u.createdAt)
        .whereType<DateTime>()
        .toList();
    if (dates.isEmpty) return null;
    dates.sort();
    return dates.last;
  }

  Future<void> _openDetail(ServiceModel service) async {
    final theme = Theme.of(context);
    final df = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
    final updates = [...service.updates]
      ..sort((a, b) {
        final ad = a.createdAt;
        final bd = b.createdAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

    if (_useRightSidePanel(context)) {
      await _showRightSideDialog<void>(
        context,
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        service.customerName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${service.customerPhone} · ${service.customerAddress}'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(context, 'Estado', _statusLabel(service.status)),
                    _pill(context, 'Tipo', _effectiveServiceKindLabel(service)),
                    _pill(context, 'Prioridad', 'P${service.priority}'),
                    if (service.isSeguro) _pill(context, 'SEGURO', 'Sí'),
                    _pill(context, 'Último', () {
                      final last =
                          _lastUpdateAt(service) ?? service.completedAt;
                      return last == null ? '—' : df.format(last);
                    }()),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  service.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Historial de proceso',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: updates.isEmpty
                      ? Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Sin actualizaciones registradas para este servicio.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: updates.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final u = updates[index];
                            final stamp = u.createdAt == null
                                ? '—'
                                : df.format(u.createdAt!);
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      u.message,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text('$stamp · ${u.changedBy}'),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.85,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    service.customerName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${service.customerPhone} · ${service.customerAddress}'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pill(context, 'Estado', _statusLabel(service.status)),
                      _pill(
                        context,
                        'Tipo',
                        _effectiveServiceKindLabel(service),
                      ),
                      _pill(context, 'Prioridad', 'P${service.priority}'),
                      if (service.isSeguro) _pill(context, 'SEGURO', 'Sí'),
                      _pill(context, 'Último', () {
                        final last =
                            _lastUpdateAt(service) ?? service.completedAt;
                        return last == null ? '—' : df.format(last);
                      }()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    service.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Historial de proceso',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: updates.isEmpty
                        ? Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Sin actualizaciones registradas para este servicio.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: updates.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final u = updates[index];
                              final stamp = u.createdAt == null
                                  ? '—'
                                  : df.format(u.createdAt!);
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        u.message,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text('$stamp · ${u.changedBy}'),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pill(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Text('$label: $value'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _items
        : _items.where((s) {
            final haystack = '${s.customerName} ${s.customerPhone} ${s.title}'
                .toLowerCase();
            return haystack.contains(query);
          }).toList();

    final df = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Historial por cliente',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar cliente o teléfono',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          if (_error != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!)),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (!_loading && _error == null && filtered.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Sin historial para mostrar.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filtered.map((service) {
              final last = _lastUpdateAt(service) ?? service.completedAt;
              final dateText = last == null ? '—' : df.format(last);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(_typeIcon(service.serviceType)),
                    title: Text(
                      '${service.customerName} · ${service.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_statusLabel(service.status)} · ${_effectiveServiceKindLabel(service)} · P${service.priority}\nÚltimo: $dateText',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openDetail(service),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _AgendaTab extends StatelessWidget {
  final List<ServiceModel> services;
  final void Function(ServiceModel) onOpenService;
  final Future<bool> Function(_CreateServiceDraft draft, String kind)
  onCreateFromAgenda;

  const _AgendaTab({
    required this.services,
    required this.onOpenService,
    required this.onCreateFromAgenda,
  });

  @override
  Widget build(BuildContext context) {
    final scheduled =
        services.where((item) => item.scheduledStart != null).toList()
          ..sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));
    final dateFormat = DateFormat('EEE dd/MM h:mm a', 'es_DO');
    final isCompact = MediaQuery.sizeOf(context).width < 420;

    Widget headerCard() {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Agenda de Servicios',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openHistorialDialog(context),
                    icon: const Icon(Icons.history),
                    label: const Text('Historial'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Registrar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _quickCreateButton(
                    context,
                    label: 'Orden',
                    icon: Icons.add_task_rounded,
                    kind: 'mantenimiento',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      children: [
        headerCard(),
        const SizedBox(height: 10),
        if (scheduled.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('Sin servicios agendados en el rango seleccionado'),
            ),
          )
        else
          ...scheduled.map((service) {
            final techs = service.assignments.map((a) => a.userName).join(', ');
            final subtitle =
                '${dateFormat.format(service.scheduledStart!)} · ${service.status}\n'
                '${techs.isEmpty ? 'Sin técnicos' : techs}'
                '${isCompact ? '\n${_effectiveServiceKindLabel(service)} · P${service.priority}' : ''}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  dense: isCompact,
                  isThreeLine: true,
                  onTap: () => onOpenService(service),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${service.customerName} · ${service.title}',
                          maxLines: isCompact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (service.isSeguro) ...[
                        const SizedBox(width: 8),
                        const _SeguroBadge(),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    subtitle,
                    maxLines: isCompact ? 3 : 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isCompact
                      ? null
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_effectiveServiceKindLabel(service)),
                            Text('P${service.priority}'),
                          ],
                        ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _quickCreateButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required String kind,
  }) {
    return OutlinedButton.icon(
      onPressed: () => _openCreateSheet(context, kind),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Future<void> _openCreateSheet(BuildContext context, String kind) async {
    const title = 'Crear orden de servicio';
    const submitLabel = 'Guardar orden';
    const initialServiceType = 'maintenance';

    var selectedKind = _normalizeAgendaKindValue(kind);

    if (_useRightSidePanel(context)) {
      await _showRightSideDialog<void>(
        context,
        builder: (_) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return CreateOrderModalShell(
                title: title,
                subtitle:
                    'Configura la etapa de la orden y completa el formulario con una estructura más clara y profesional.',
                onClose: () => Navigator.pop(context),
                showGrip: false,
                headerAccessory: DropdownButtonFormField<String>(
                  key: ValueKey('agenda-create-kind-$selectedKind'),
                  initialValue: _normalizeAgendaKindValue(selectedKind),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Fase de orden',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'reserva', child: Text('Reserva')),
                    DropdownMenuItem(
                      value: 'instalacion',
                      child: Text('Instalación'),
                    ),
                    DropdownMenuItem(
                      value: 'mantenimiento',
                      child: Text('Mantenimiento'),
                    ),
                    DropdownMenuItem(
                      value: 'garantia',
                      child: Text('Garantía'),
                    ),
                    DropdownMenuItem(
                      value: 'levantamiento',
                      child: Text('Levantamiento'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => selectedKind = value);
                  },
                ),
                child: _CreateReservationTab(
                  onCreate: (draft) async {
                    final ok = await onCreateFromAgenda(draft, selectedKind);
                    if (ok && context.mounted) Navigator.pop(context);
                  },
                  submitLabel: submitLabel,
                  initialServiceType: initialServiceType,
                  showServiceTypeField: false,
                ),
              );
            },
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.92,
                child: CreateOrderModalShell(
                  title: title,
                  subtitle:
                      'Configura la etapa de la orden y completa el formulario con una estructura más clara y profesional.',
                  onClose: () => Navigator.pop(context),
                  headerAccessory: DropdownButtonFormField<String>(
                    key: ValueKey('agenda-create-kind-$selectedKind'),
                    initialValue: _normalizeAgendaKindValue(selectedKind),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Fase de orden',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'reserva',
                        child: Text('Reserva'),
                      ),
                      DropdownMenuItem(
                        value: 'instalacion',
                        child: Text('Instalación'),
                      ),
                      DropdownMenuItem(
                        value: 'mantenimiento',
                        child: Text('Mantenimiento'),
                      ),
                      DropdownMenuItem(
                        value: 'garantia',
                        child: Text('Garantía'),
                      ),
                      DropdownMenuItem(
                        value: 'levantamiento',
                        child: Text('Levantamiento'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() => selectedKind = value);
                    },
                  ),
                  child: _CreateReservationTab(
                    onCreate: (draft) async {
                      final ok = await onCreateFromAgenda(draft, selectedKind);
                      if (ok && context.mounted) Navigator.pop(context);
                    },
                    submitLabel: submitLabel,
                    initialServiceType: initialServiceType,
                    showServiceTypeField: false,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openHistorialDialog(BuildContext context) async {
    final items = [...services];
    items.sort((a, b) {
      final ad = a.scheduledStart ?? a.completedAt;
      final bd = b.scheduledStart ?? b.completedAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    final df = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Historial de servicios (${items.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text('Sin servicios para mostrar'),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final service = items[index];
                              final date =
                                  service.scheduledStart ?? service.completedAt;
                              final dateText = date == null
                                  ? '—'
                                  : df.format(date);
                              return ListTile(
                                title: Text(
                                  '${service.customerName} · ${service.title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '$dateText · ${service.status} · ${_effectiveServiceKindLabel(service)} · P${service.priority}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  onOpenService(service);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CreateServiceDraft {
  final String customerId;
  final String serviceType;
  final String? categoryId;
  final String categoryCode;
  final int priority;
  final DateTime? reservationAt;
  final String title;
  final String description;
  final String? addressSnapshot;
  final String orderState;
  final String? technicianId;
  final String? relatedServiceId;
  final double? quotedAmount;
  final double? depositAmount;
  final String? paymentNote;
  final List<String> tags;
  final String referenceText;
  final List<PlatformFile> referenceImages;
  final PlatformFile? referenceVideo;

  _CreateServiceDraft({
    required this.customerId,
    required this.serviceType,
    required this.categoryId,
    required this.categoryCode,
    required this.priority,
    this.reservationAt,
    required this.title,
    required this.description,
    required this.orderState,
    this.technicianId,
    this.addressSnapshot,
    this.relatedServiceId,
    this.quotedAmount,
    this.depositAmount,
    this.paymentNote,
    this.tags = const [],
    required this.referenceText,
    this.referenceImages = const [],
    this.referenceVideo,
  });
}

class _CreateReservationTab extends ConsumerStatefulWidget {
  final Future<void> Function(_CreateServiceDraft draft) onCreate;
  final String submitLabel;
  final String initialServiceType;
  final bool showServiceTypeField;
  final String? agendaKind;
  final bool showAgendaKindPicker;
  final ValueChanged<String>? onAgendaKindChanged;

  const _CreateReservationTab({
    // ignore: unused_element_parameter
    super.key,
    required this.onCreate,
    this.submitLabel = 'Guardar reserva',
    this.initialServiceType = 'installation',
    this.showServiceTypeField = true,
    this.agendaKind,
    this.showAgendaKindPicker = false,
    this.onAgendaKindChanged,
  });

  @override
  ConsumerState<_CreateReservationTab> createState() =>
      _CreateReservationTabState();
}

class _CreateReservationTabState extends ConsumerState<_CreateReservationTab> {
  final _formKey = GlobalKey<FormState>();
  final _searchClientCtrl = TextEditingController();
  final _reservationDateCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _referenceTextCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _gpsCtrl = TextEditingController();
  final _quotedCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _paidAmountCtrl = TextEditingController();
  final _relatedServiceCtrl = TextEditingController();
  final _gpsPointNotifier = ValueNotifier<LatLng?>(null);
  final _resolvingGpsNotifier = ValueNotifier<bool>(false);

  late String _serviceType;
  late String _categoryId;
  late int _priority;
  late String _orderState;
  String? _technicianId;
  bool _priorityTouched = false;
  bool _loadingTechnicians = false;
  List<TechnicianModel> _technicians = const [];
  String? _customerId;
  String? _customerName;
  String? _customerPhone;
  DateTime? _reservationAt;
  bool _checkingCotizaciones = false;
  bool _hasCotizaciones = false;
  CotizacionModel? _selectedCotizacion;

  String _paymentStatus = 'pendiente';
  String _paymentMethod = 'efectivo';

  String _cotizacionesRouteForSelectedClient() {
    final id = (_customerId ?? '').trim();
    final name = (_customerName ?? '').trim();
    final phone = (_customerPhone ?? '').trim();

    final params = <String, String>{
      // Cuando se abre Cotizaciones desde Agenda, al guardar debe regresar.
      'popOnSave': '1',
    };
    if (id.isNotEmpty) params['customerId'] = id;
    if (name.isNotEmpty) params['customerName'] = name;
    if (phone.isNotEmpty) params['customerPhone'] = phone;

    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '${Routes.cotizaciones}?$q';
  }

  Timer? _gpsResolveDebounce;
  int _gpsResolveSeq = 0;
  List<PlatformFile> _referenceImages = const [];
  PlatformFile? _referenceVideo;
  VideoPlayerController? _referenceVideoPreviewCtrl;
  Future<void>? _referenceVideoPreviewInit;
  Object? _referenceVideoPreviewError;
  bool _saving = false;
  bool _readyToRenderForm = false;

  bool get _isAgendaReserva {
    final k = _normalizeAgendaKindValue(widget.agendaKind);
    return k == 'reserva';
  }

  String? _requiredPriceValidator(String? _) {
    final raw = _quotedCtrl.text.trim();
    if (raw.isEmpty) return 'La cotizacion es obligatoria';
    final value = double.tryParse(raw);
    if (value == null || value <= 0) {
      return 'La cotizacion debe ser mayor que cero';
    }
    return null;
  }

  LatLng? get _gpsPoint => _gpsPointNotifier.value;
  bool get _resolvingGps => _resolvingGpsNotifier.value;

  bool _sameLatLng(LatLng? a, LatLng? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.latitude == b.latitude && a.longitude == b.longitude;
  }

  void _setGpsPoint(LatLng? value) {
    if (_sameLatLng(_gpsPointNotifier.value, value)) return;
    _gpsPointNotifier.value = value;
  }

  void _setResolvingGps(bool value) {
    if (_resolvingGpsNotifier.value == value) return;
    _resolvingGpsNotifier.value = value;
  }

  T? _safeDropdownValue<T>(T? currentValue, List<DropdownMenuItem<T>> items) {
    for (final item in items) {
      if (item.value == currentValue) return currentValue;
    }
    return null;
  }

  void _showDeferredSnackBar(String message) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void initState() {
    super.initState();
    _serviceType = widget.initialServiceType;
    _categoryId = '';
    _priority = 1;
    _orderState = 'pendiente';
    _applyDefaultsForKind(widget.agendaKind, kindChanged: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _readyToRenderForm = true);
      unawaited(_loadTechnicians());
    });
  }

  @override
  void didUpdateWidget(covariant _CreateReservationTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKind = (oldWidget.agendaKind ?? '').trim().toLowerCase();
    final newKind = (widget.agendaKind ?? '').trim().toLowerCase();
    if (oldKind != newKind) {
      _applyDefaultsForKind(widget.agendaKind, kindChanged: true);
    }

    if (!widget.showServiceTypeField &&
        oldWidget.initialServiceType != widget.initialServiceType) {
      final next = widget.initialServiceType;
      if (_serviceType != next) {
        setState(() => _serviceType = next);
      }
    }
  }

  @override
  void dispose() {
    _searchClientCtrl.dispose();
    _reservationDateCtrl.dispose();
    _descriptionCtrl.dispose();
    _referenceTextCtrl.dispose();
    _addressCtrl.dispose();
    _gpsCtrl.dispose();
    _gpsResolveDebounce?.cancel();
    _quotedCtrl.dispose();
    _depositCtrl.dispose();
    _paidAmountCtrl.dispose();
    _relatedServiceCtrl.dispose();
    _gpsPointNotifier.dispose();
    _resolvingGpsNotifier.dispose();
    _referenceVideoPreviewCtrl?.dispose();
    super.dispose();
  }

  void _clearReferenceVideoPreview() {
    final ctrl = _referenceVideoPreviewCtrl;
    _referenceVideoPreviewCtrl = null;
    _referenceVideoPreviewInit = null;
    _referenceVideoPreviewError = null;
    ctrl?.dispose();
  }

  Future<void> _prepareReferenceVideoPreview({
    StateSetter? setSheetState,
  }) async {
    _clearReferenceVideoPreview();
    if (!mounted) return;
    if (kIsWeb) {
      try {
        setSheetState?.call(() {});
      } catch (_) {}
      return;
    }

    final f = _referenceVideo;
    final path = (f?.path ?? '').trim();
    if (path.isEmpty) {
      try {
        setSheetState?.call(() {});
      } catch (_) {}
      return;
    }

    final ctrl = createVideoPreviewController(
      path: path,
      bytes: f?.bytes,
      fileName: f?.name,
    );
    if (ctrl == null) {
      try {
        setSheetState?.call(() {});
      } catch (_) {}
      return;
    }
    ctrl.setLooping(false);

    final init = ctrl.initialize();
    setState(() {
      _referenceVideoPreviewCtrl = ctrl;
      _referenceVideoPreviewInit = init;
      _referenceVideoPreviewError = null;
    });

    try {
      await init;
      if (!mounted) return;
      try {
        setSheetState?.call(() {});
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() => _referenceVideoPreviewError = e);
      try {
        setSheetState?.call(() {});
      } catch (_) {}
    }
  }

  void _applyDefaultsForKind(String? kind, {required bool kindChanged}) {
    final lower = (kind ?? '').trim().toLowerCase();

    final hasTech = (_technicianId ?? '').trim().isNotEmpty;
    final nextState = hasTech ? 'asignada' : 'pendiente';

    final nextPriority = (!_priorityTouched && lower == 'garantia')
        ? 1
        : _priority;

    if (!mounted) {
      _orderState = nextState;
      _priority = nextPriority;
      return;
    }

    setState(() {
      _orderState = nextState;
      _priority = nextPriority;
      if (!widget.showServiceTypeField || kindChanged) {
        _serviceType = _serviceTypeForAgendaKind(lower, fallback: _serviceType);
      }
    });
  }

  Future<void> _loadTechnicians() async {
    if (_loadingTechnicians) return;
    setState(() => _loadingTechnicians = true);
    try {
      final items = await ref
          .read(operationsRepositoryProvider)
          .getTechnicians(silent: true);
      if (!mounted) return;
      setState(() {
        _technicians = items;
        final hasSelectedTechnician = items.any(
          (technician) => technician.id == _technicianId,
        );
        if (!hasSelectedTechnician) {
          _technicianId = null;
        }
      });
    } catch (_) {
      // Silencioso: el formulario funciona igual sin dropdown.
    } finally {
      if (mounted) setState(() => _loadingTechnicians = false);
    }
  }

  String _defaultCategoryId(List<ServiceChecklistCategoryModel> items) {
    for (final item in items) {
      if (item.code.trim().toLowerCase() == 'cameras') return item.id;
    }
    return items.first.id;
  }

  String? _categoryIdForSubmit(ServiceChecklistCategoryModel category) {
    final id = category.id.trim();
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuid.hasMatch(id) ? id : null;
  }

  ServiceChecklistCategoryModel? get _selectedCategory {
    final selectedId = _categoryId.trim();
    final categories = ref
        .read(categoriesProvider)
        .maybeWhen(
          data: (items) => items,
          orElse: () => const <ServiceChecklistCategoryModel>[],
        );
    final safeCategories = categories.isNotEmpty
        ? categories
        : defaultCategories;
    for (final item in safeCategories) {
      if (item.id == selectedId) return item;
    }
    return null;
  }

  bool _looksLikeHttpUrl(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    final uri = Uri.tryParse(v);
    if (uri == null) return false;
    return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  LatLng? _extractLatLngByRegex(String text) {
    final patterns = <RegExp>[
      RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)'),
      RegExp(r'center=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)'),
      RegExp(r'll=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)'),
      RegExp(r'q=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)'),
      // Google Maps place URLs often include coords as: ...!3dLAT!4dLNG...
      RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)'),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(text);
      if (m == null) continue;
      final lat = double.tryParse(m.group(1) ?? '');
      final lng = double.tryParse(m.group(2) ?? '');
      if (lat == null || lng == null) continue;
      return LatLng(lat, lng);
    }
    return null;
  }

  String? _extractGoogleMapsUrlFromHtml(String html) {
    final candidates = <RegExp>[
      RegExp(r'https?://www\.google\.com/maps[^\"\s<]+'),
      RegExp(r'https?://maps\.google\.com/\?[^\"\s<]+'),
      RegExp(r'https?://google\.com/maps[^\"\s<]+'),
    ];
    for (final re in candidates) {
      final m = re.firstMatch(html);
      if (m == null) continue;
      return m.group(0);
    }
    return null;
  }

  Future<LatLng?> _resolveLatLngFromText(String value) async {
    final direct = parseLatLngFromText(value);
    if (direct != null) return direct;

    if (!_looksLikeHttpUrl(value)) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return null;

    try {
      final dio = Dio(
        BaseOptions(
          followRedirects: true,
          maxRedirects: 8,
          connectTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s >= 200 && s < 500,
        ),
      );

      final response = await dio.getUri(uri);
      final resolvedUrl = response.realUri.toString();

      final fromResolvedUrl = parseLatLngFromText(resolvedUrl);
      if (fromResolvedUrl != null) return fromResolvedUrl;

      final fromResolvedUrlRegex = _extractLatLngByRegex(resolvedUrl);
      if (fromResolvedUrlRegex != null) return fromResolvedUrlRegex;

      final body = response.data?.toString() ?? '';
      final fromBody = _extractLatLngByRegex(body);
      if (fromBody != null) return fromBody;

      final embeddedMapsUrl = _extractGoogleMapsUrlFromHtml(body);
      if (embeddedMapsUrl != null) {
        final fromEmbeddedUrl = parseLatLngFromText(embeddedMapsUrl);
        if (fromEmbeddedUrl != null) return fromEmbeddedUrl;

        final fromEmbeddedUrlRegex = _extractLatLngByRegex(embeddedMapsUrl);
        if (fromEmbeddedUrlRegex != null) return fromEmbeddedUrlRegex;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _resolveAndSetGpsPoint(
    String raw, {
    bool showSnackOnFail = false,
  }) async {
    final text = raw.trim();
    if (text.isEmpty) {
      _setResolvingGps(false);
      _setGpsPoint(null);
      return;
    }

    final seq = ++_gpsResolveSeq;
    _setResolvingGps(true);

    final point = await _resolveLatLngFromText(text);

    if (!mounted) return;
    if (seq != _gpsResolveSeq) return;

    _setResolvingGps(false);
    if (point != null) {
      _setGpsPoint(point);
    }

    if (point == null && showSnackOnFail) {
      _showDeferredSnackBar(
        'No pude detectar coordenadas. Prueba pegar un link que incluya lat,lng (o pega "lat,lng" directamente).',
      );
    }
  }

  void _openGpsFullScreen(LatLng point) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => _AgendaGpsFullMapScreen(
          point: point,
          title: _customerName ?? 'Ubicación',
        ),
      ),
    );
  }

  String _serviceTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'installation':
        return 'Instalación';
      case 'maintenance':
        return 'Mantenimiento';
      case 'warranty':
        return 'Garantía';
      case 'pos_support':
        return 'Soporte POS';
      default:
        return 'Servicio';
    }
  }

  Future<void> _pickReferenceImages() async {
    await _pickReferenceImagesForSheet();
  }

  Future<void> _pickReferenceImagesForSheet({
    StateSetter? setSheetState,
  }) async {
    final lockParentWindow =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);

    FocusManager.instance.primaryFocus?.unfocus();

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withReadStream: false,
        withData: kIsWeb,
        lockParentWindow: lockParentWindow,
      );
    } catch (_) {
      // Fallback: some platforms/devices can fail with the built-in filters.
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowMultiple: true,
          allowedExtensions: const [
            'jpg',
            'jpeg',
            'png',
            'webp',
            'heic',
            'heif',
          ],
          withReadStream: false,
          withData: kIsWeb,
          lockParentWindow: lockParentWindow,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('No se pudo abrir el selector: $e')),
        );
        return;
      }
    }

    if (result == null || result.files.isEmpty) return;

    final next = <PlatformFile>[];
    for (final f in result.files) {
      if ((f.name).trim().isEmpty) continue;
      next.add(f);
    }
    if (next.isEmpty) return;

    if (!mounted) return;
    setState(() {
      final combined = [..._referenceImages, ...next];
      final seen = <String>{};
      _referenceImages = combined
          .where((f) => seen.add((f.path ?? f.name).trim()))
          .toList(growable: false);
    });

    try {
      setSheetState?.call(() {});
    } catch (_) {
      // Sheet was likely closed while awaiting the picker.
    }
  }

  Future<void> _pickReferenceVideo() async {
    await _pickReferenceVideoForSheet();
  }

  Future<void> _pickReferenceVideoForSheet({StateSetter? setSheetState}) async {
    final lockParentWindow =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);

    FocusManager.instance.primaryFocus?.unfocus();

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withReadStream: false,
        withData: kIsWeb,
        lockParentWindow: lockParentWindow,
      );
    } catch (_) {
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const [
            'mp4',
            'mov',
            'm4v',
            'avi',
            'mkv',
            'webm',
            '3gp',
          ],
          withReadStream: false,
          withData: kIsWeb,
          lockParentWindow: lockParentWindow,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('No se pudo abrir el selector: $e')),
        );
        return;
      }
    }

    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;
    setState(() => _referenceVideo = result!.files.first);

    unawaited(_prepareReferenceVideoPreview(setSheetState: setSheetState));

    try {
      setSheetState?.call(() {});
    } catch (_) {
      // Sheet was likely closed while awaiting the picker.
    }
  }

  ImageProvider? _referenceImageProvider(PlatformFile file) {
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return MemoryImage(bytes);
    }

    final path = (file.path ?? '').trim();
    if (path.isEmpty) return null;
    return localFileImageProvider(path);
  }

  void _openReferenceImageFullScreen(PlatformFile file) {
    final provider = _referenceImageProvider(file);
    if (provider == null) return;

    FullScreenImageViewer.show(
      context,
      image: provider,
      title: file.name.trim().isEmpty ? 'Foto de referencia' : file.name,
    );
  }

  void _openReferenceVideoFullScreen() {
    final file = _referenceVideo;
    if (file == null) return;

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _LocalReferenceVideoViewer(file: file),
      ),
    );
  }

  void _removeReferenceImageAt(int index, {StateSetter? setSheetState}) {
    if (index < 0 || index >= _referenceImages.length) return;
    setState(() {
      final next = [..._referenceImages];
      next.removeAt(index);
      _referenceImages = next;
    });

    try {
      setSheetState?.call(() {});
    } catch (_) {
      // Sheet was likely closed.
    }
  }

  Widget _buildReferenceVideoPreview() {
    final ctrl = _referenceVideoPreviewCtrl;
    final init = _referenceVideoPreviewInit;
    if (_referenceVideo == null) return const SizedBox.shrink();

    if (kIsWeb) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Vista previa no disponible en web (por ahora).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    if (_referenceVideoPreviewError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'No se pudo cargar la vista previa del video.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    if (ctrl == null || init == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 186,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: FutureBuilder<void>(
              future: init,
              builder: (context, snap) {
                final initialized =
                    snap.connectionState == ConnectionState.done &&
                    ctrl.value.isInitialized;
                if (!initialized) {
                  return const SizedBox(
                    width: 186,
                    height: 112,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                final aspect = ctrl.value.aspectRatio == 0
                    ? (16 / 9)
                    : ctrl.value.aspectRatio;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openReferenceVideoFullScreen,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: aspect,
                          child: VideoPlayer(ctrl),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.20),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: 0.86),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fullscreen_rounded, size: 18),
                              SizedBox(width: 4),
                              Text('Abrir'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pasteGpsFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (text.isEmpty) return;

    _gpsResolveDebounce?.cancel();
    final parsed = parseLatLngFromText(text);
    _gpsCtrl.text = text;
    _setGpsPoint(parsed);
    _setResolvingGps(false);

    if (parsed == null) {
      await _resolveAndSetGpsPoint(text, showSnackOnFail: true);
    }
  }

  Future<void> _openGpsInApp() async {
    final point = _gpsPoint ?? parseLatLngFromText(_gpsCtrl.text);
    if (point != null) {
      _openGpsFullScreen(point);
      return;
    }

    await _resolveAndSetGpsPoint(_gpsCtrl.text, showSnackOnFail: true);
    final resolved = _gpsPoint;
    if (!mounted) return;
    if (resolved != null) {
      _openGpsFullScreen(resolved);
      return;
    }

    final raw = _gpsCtrl.text.trim();
    final info = buildServiceLocationInfo(
      addressOrText: raw,
      mapsUrl: _looksLikeHttpUrl(raw) ? raw : null,
    );
    if (info.canOpenMaps) {
      await safeOpenUrl(context, info.mapsUri!, copiedMessage: 'Link copiado');
      return;
    }

    _showDeferredSnackBar('No se pudo abrir la ubicación');
  }

  Future<void> _openGpsDestinationFromInput() async {
    final point = _gpsPoint ?? parseLatLngFromText(_gpsCtrl.text);
    if (point != null) {
      await _openBestNavigation(context, point);
      return;
    }

    await _resolveAndSetGpsPoint(_gpsCtrl.text, showSnackOnFail: false);
    final resolved = _gpsPoint;
    if (!mounted) return;
    if (resolved != null) {
      await _openBestNavigation(context, resolved);
      return;
    }

    final raw = _gpsCtrl.text.trim();
    final info = buildServiceLocationInfo(
      addressOrText: raw,
      mapsUrl: _looksLikeHttpUrl(raw) ? raw : null,
    );
    if (info.canOpenMaps) {
      await safeOpenUrl(context, info.mapsUri!, copiedMessage: 'Link copiado');
      return;
    }

    _showDeferredSnackBar('No se pudo detectar una ubicación válida');
  }

  String? _buildAddressSnapshot() {
    final address = _addressCtrl.text.trim();
    final gpsText = _gpsCtrl.text.trim();
    final point = _gpsPoint ?? parseLatLngFromText(_gpsCtrl.text);

    final hasAddress = address.isNotEmpty;
    final hasPoint = point != null;
    final hasGpsText = gpsText.isNotEmpty;

    if (!hasAddress && !hasPoint) return null;
    if (!hasPoint) {
      if (!hasAddress && !hasGpsText) return null;
      if (!hasGpsText) return address;

      final isUrl = RegExp(
        r'https?://',
        caseSensitive: false,
      ).hasMatch(gpsText);
      final lines = <String>[];
      if (hasAddress) lines.add(address);
      lines.add(isUrl ? 'MAPS: $gpsText' : 'GPS: $gpsText');
      return lines.join('\n');
    }

    final gpsLine = 'GPS: ${formatLatLng(point)}';
    final mapsLine = 'MAPS: ${buildGoogleMapsSearchUrl(point)}';

    final lines = <String>[];
    if (hasAddress) lines.add(address);
    lines.add(gpsLine);
    lines.add(mapsLine);
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final categoriesValue = ref.watch(categoriesProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final categories = categoriesValue.maybeWhen(
          data: (items) => items,
          orElse: () => const <ServiceChecklistCategoryModel>[],
        );
        final safeCategories = categories.isNotEmpty
            ? categories
            : defaultCategories;
        // ignore: avoid_print
        print('Usando fallback: ${categories.isEmpty}');
        final hasSelectedCategory = safeCategories.any(
          (item) => item.id == _categoryId,
        );
        final selectedCategory = hasSelectedCategory
            ? safeCategories.firstWhere((item) => item.id == _categoryId)
            : null;
        if (safeCategories.isNotEmpty && !hasSelectedCategory) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _categoryId = _defaultCategoryId(safeCategories));
          });
        }

        if (!_readyToRenderForm) {
          return _CreateReservationWarmup(
            usingFallbackCategories: categories.isEmpty,
          );
        }

        final isCompact = constraints.maxWidth < 430;
        final isWide = constraints.maxWidth >= 520;
        final formPadding = isCompact ? 10.0 : (isWide ? 12.0 : 14.0);
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final formTheme = theme.copyWith(
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: scheme.surface,
            isDense: false,
            alignLabelWithHint: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            helperMaxLines: 3,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: scheme.primary, width: 1.4),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: scheme.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: scheme.error, width: 1.4),
            ),
            labelStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            floatingLabelStyle: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
            helperStyle: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.25,
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.55),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        );

        String money(double value) => NumberFormat.currency(
          locale: 'es_DO',
          symbol: 'RD\$',
        ).format(value);

        Widget buildLocationFields(Widget addressField) {
          return ValueListenableBuilder<TextEditingValue>(
            valueListenable: _gpsCtrl,
            builder: (context, gpsValue, _) {
              final gpsText = gpsValue.text.trim();
              return ValueListenableBuilder<LatLng?>(
                valueListenable: _gpsPointNotifier,
                builder: (context, gpsPoint, __) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _resolvingGpsNotifier,
                    builder: (context, resolvingGps, ___) {
                      final gpsField = TextFormField(
                        controller: _gpsCtrl,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: 'Ubicación GPS (WhatsApp/Maps)',
                          helperText: resolvingGps
                              ? 'Detectando ubicación desde el link...'
                              : (gpsPoint == null
                                    ? 'Pega un link de Google Maps o "lat,lng"'
                                    : 'Detectado: ${formatLatLng(gpsPoint)}'),
                          suffixIcon: SizedBox(
                            width: 96,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: _pasteGpsFromClipboard,
                                  icon: const Icon(Icons.content_paste_rounded),
                                ),
                                IconButton(
                                  onPressed: gpsText.isEmpty
                                      ? null
                                      : _openGpsInApp,
                                  icon: const Icon(Icons.map_outlined),
                                ),
                              ],
                            ),
                          ),
                        ),
                        onChanged: (value) {
                          final text = value.trim();
                          _gpsResolveDebounce?.cancel();
                          if (text.isEmpty) {
                            _setResolvingGps(false);
                            _setGpsPoint(null);
                            return;
                          }

                          final parsed = parseLatLngFromText(text);
                          _setGpsPoint(parsed);
                          if (parsed != null) {
                            _setResolvingGps(false);
                            return;
                          }

                          if (!_looksLikeHttpUrl(text)) {
                            _setResolvingGps(false);
                            return;
                          }

                          _gpsResolveDebounce = Timer(
                            const Duration(milliseconds: 650),
                            () => _resolveAndSetGpsPoint(text),
                          );
                        },
                      );

                      return Column(
                        children: [
                          if (isWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: addressField),
                                const SizedBox(width: 10),
                                Expanded(child: gpsField),
                              ],
                            )
                          else ...[
                            addressField,
                            const SizedBox(height: 10),
                            gpsField,
                          ],
                          if (gpsText.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _GpsMapPreviewCard(
                              point: gpsPoint,
                              mapsUrl: gpsText,
                              onOpen: () {
                                unawaited(_openGpsInApp());
                              },
                              onNavigate: () {
                                unawaited(_openGpsDestinationFromInput());
                              },
                            ),
                          ],
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        }

        final agendaKindItems = const [
          DropdownMenuItem(value: 'reserva', child: Text('Reserva')),
          DropdownMenuItem(value: 'instalacion', child: Text('Instalación')),
          DropdownMenuItem(
            value: 'mantenimiento',
            child: Text('Mantenimiento'),
          ),
          DropdownMenuItem(value: 'garantia', child: Text('Garantía')),
          DropdownMenuItem(
            value: 'levantamiento',
            child: Text('Levantamiento'),
          ),
        ];
        final safeAgendaKind =
            _safeDropdownValue<String>(
              _normalizeAgendaKindValue(widget.agendaKind),
              agendaKindItems,
            ) ??
            'reserva';
        final priorityItems = const [
          DropdownMenuItem(value: 1, child: Text('Alta')),
          DropdownMenuItem(value: 2, child: Text('Media')),
          DropdownMenuItem(value: 3, child: Text('Baja')),
        ];
        final safePriority =
            _safeDropdownValue<int>(_priority, priorityItems) ?? 1;
        final serviceTypeItems = const [
          DropdownMenuItem(value: 'installation', child: Text('Instalación')),
          DropdownMenuItem(value: 'maintenance', child: Text('Mantenimiento')),
          DropdownMenuItem(value: 'warranty', child: Text('Garantía')),
          DropdownMenuItem(value: 'pos_support', child: Text('Soporte POS')),
          DropdownMenuItem(value: 'other', child: Text('Otro')),
        ];
        final safeServiceType =
            _safeDropdownValue<String>(_serviceType, serviceTypeItems) ??
            'installation';
        final orderStateItems = const [
          DropdownMenuItem(value: 'pendiente', child: Text('Pendiente')),
          DropdownMenuItem(value: 'confirmada', child: Text('Confirmada')),
          DropdownMenuItem(value: 'asignada', child: Text('Asignada')),
          DropdownMenuItem(value: 'en_camino', child: Text('En camino')),
          DropdownMenuItem(value: 'en_proceso', child: Text('En proceso')),
          DropdownMenuItem(value: 'finalizada', child: Text('Finalizada')),
          DropdownMenuItem(value: 'cancelada', child: Text('Cancelada')),
          DropdownMenuItem(value: 'reagendada', child: Text('Reagendada')),
          DropdownMenuItem(value: 'cerrada', child: Text('Cerrada')),
        ];
        final safeOrderState =
            _safeDropdownValue<String>(_orderState, orderStateItems) ??
            'pendiente';
        final technicianItems = [
          const DropdownMenuItem(value: '', child: Text('Sin asignar')),
          ..._technicians.map(
            (t) => DropdownMenuItem(value: t.id, child: Text(t.name)),
          ),
        ];
        final safeTechnicianId =
            _safeDropdownValue<String>(_technicianId ?? '', technicianItems) ??
            '';
        final paymentStatusItems = const [
          DropdownMenuItem(value: 'pendiente', child: Text('Pendiente')),
          DropdownMenuItem(value: 'pagado', child: Text('Pagado')),
        ];
        final safePaymentStatus =
            _safeDropdownValue<String>(_paymentStatus, paymentStatusItems) ??
            'pendiente';
        final paymentMethodItems = const [
          DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
          DropdownMenuItem(
            value: 'transferencia',
            child: Text('Transferencia'),
          ),
          DropdownMenuItem(value: 'tarjeta', child: Text('Tarjeta')),
        ];
        final safePaymentMethod =
            _safeDropdownValue<String>(_paymentMethod, paymentMethodItems) ??
            'efectivo';

        final agendaKindPicker = DropdownButtonFormField<String>(
          key: ValueKey(
            'create-kind-${_normalizeAgendaKindValue(widget.agendaKind)}',
          ),
          initialValue: safeAgendaKind,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Fase de orden',
          ),
          items: agendaKindItems,
          onChanged: widget.onAgendaKindChanged == null
              ? null
              : (value) {
                  final next = (value ?? '').trim().toLowerCase();
                  if (next.isEmpty) return;
                  widget.onAgendaKindChanged?.call(next);
                },
        );

        final reservationField = TextFormField(
          controller: _reservationDateCtrl,
          readOnly: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Fecha y hora',
            suffixIcon: Icon(Icons.schedule_outlined),
          ),
          validator: (_) {
            return _reservationAt == null ? 'Requerido' : null;
          },
          onTap: _pickReservationDate,
        );

        final priorityField = DropdownButtonFormField<int>(
          initialValue: safePriority,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Prioridad',
          ),
          items: priorityItems,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _priority = value;
                _priorityTouched = true;
              });
            }
          },
        );

        final addressField = TextFormField(
          controller: _addressCtrl,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Dirección (ciudad/sector)',
            helperText: 'Ej: Higüey, Otra Banda, Miches',
          ),
        );

        final serviceTypeField = DropdownButtonFormField<String>(
          initialValue: safeServiceType,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Tipo de servicio',
          ),
          items: serviceTypeItems,
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _serviceType = value;
              if (value == 'installation') _priority = 1;
            });
          },
        );

        final selectedCategoryId = hasSelectedCategory ? _categoryId : null;

        final categoryField = DropdownButtonFormField<String>(
          initialValue: selectedCategoryId,
          isExpanded: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Categoría',
            helperText: categoriesValue.when(
              data: (_) => categories.isEmpty
                  ? 'Usando categorías base.'
                  : selectedCategory?.code,
              loading: () => 'Usando categorías base mientras carga...',
              error: (_, __) => 'Usando categorías base.',
            ),
          ),
          items: safeCategories
              .map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(_serviceCategoryDropdownLabel(item)),
                ),
              )
              .toList(growable: false),
          validator: (_) {
            if (_categoryId.trim().isEmpty) return 'Requerido';
            return null;
          },
          onChanged: (value) {
            if (value != null) setState(() => _categoryId = value);
          },
        );

        final orderStateField = DropdownButtonFormField<String>(
          key: ValueKey('orderState-$_orderState'),
          initialValue: safeOrderState,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Estado (auto)',
            helperText: 'Se calcula automáticamente al asignar técnico.',
          ),
          items: orderStateItems,
          onChanged: null,
        );

        final technicianField = DropdownButtonFormField<String>(
          key: ValueKey('technician-${_technicianId ?? ''}'),
          initialValue: safeTechnicianId,
          isExpanded: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Técnico asignado',
            helperText: _loadingTechnicians
                ? 'Cargando técnicos...'
                : (_technicians.isEmpty
                      ? 'No tienes técnicos registrados. Puedes guardar sin asignar.'
                      : null),
          ),
          items: technicianItems,
          onChanged: _loadingTechnicians
              ? null
              : (value) {
                  if (value == null || value.trim().isEmpty) {
                    setState(() => _technicianId = null);
                  } else {
                    setState(() => _technicianId = value);
                  }

                  _applyDefaultsForKind(widget.agendaKind, kindChanged: false);
                },
        );

        return Theme(
          data: formTheme,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.all(formPadding),
              children: [
                CreateOrderSection(
                  title: 'Datos principales',
                  icon: Icons.auto_awesome_mosaic_outlined,
                  subtitle:
                      'Define el contexto base de la orden para completar el resto del formulario con claridad.',
                  child: Column(
                    children: [
                      if (widget.showAgendaKindPicker) ...[
                        agendaKindPicker,
                        const SizedBox(height: 12),
                      ],
                      if (isWide)
                        Row(
                          children: [
                            Expanded(child: reservationField),
                            const SizedBox(width: 10),
                            Expanded(child: priorityField),
                          ],
                        )
                      else ...[
                        reservationField,
                        const SizedBox(height: 10),
                        priorityField,
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                CreateOrderSection(
                  title: 'Cliente',
                  icon: Icons.person_outline_rounded,
                  subtitle:
                      'Selecciona el cliente y administra su contexto comercial antes de guardar la orden.',
                  child: Column(
                    children: [
                      CreateOrderClientCard(
                        title: _customerName ?? 'Sin cliente seleccionado',
                        subtitle: _customerName == null
                            ? 'Selecciona un cliente para completar teléfono, dirección y cotización.'
                            : [
                                if ((_customerPhone ?? '').trim().isNotEmpty)
                                  _customerPhone!.trim(),
                                if ((_addressCtrl.text).trim().isNotEmpty)
                                  _addressCtrl.text.trim(),
                              ].join(' · '),
                        trailing: _checkingCotizaciones
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : (_hasCotizaciones
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.primary.withValues(
                                          alpha: 0.10,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        'Cotización',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    )
                                  : null),
                        actions: [
                          FilledButton.tonalIcon(
                            onPressed: _openClientPicker,
                            icon: const Icon(Icons.person_search_outlined),
                            label: const Text('Cliente'),
                          ),
                          OutlinedButton.icon(
                            onPressed: (_customerId ?? '').trim().isEmpty
                                ? null
                                : () async {
                                    final id = _customerId!;
                                    await context.push(Routes.clienteEdit(id));
                                    if (!mounted) return;
                                    await _openClientPicker();
                                  },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Editar'),
                          ),
                          if (_customerName != null &&
                              !_checkingCotizaciones &&
                              _hasCotizaciones)
                            OutlinedButton.icon(
                              onPressed: () {
                                final phone = (_customerPhone ?? '').trim();
                                if (phone.isEmpty) return;
                                context.push(
                                  '${Routes.cotizacionesHistorial}?customerPhone=${Uri.encodeQueryComponent(phone)}&pick=0',
                                );
                              },
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: const Text('Ver cotizaciones'),
                            ),
                        ],
                      ),
                      if (_customerName != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Cotización',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedCotizacion == null
                                    ? (_hasCotizaciones
                                          ? 'Selecciona una cotización existente o crea una nueva para completar el precio vendido.'
                                          : 'Este cliente todavía no tiene cotizaciones guardadas.')
                                    : 'Seleccionada: ${money(_selectedCotizacion!.total)} · ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(_selectedCotizacion!.createdAt)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed:
                                        (_customerPhone ?? '').trim().isEmpty
                                        ? null
                                        : () async {
                                            final picked =
                                                await _openCotizacionPickerDialog();
                                            if (!mounted || picked == null) {
                                              return;
                                            }
                                            setState(() {
                                              _selectedCotizacion = picked;
                                              _quotedCtrl.text = picked.total
                                                  .toStringAsFixed(2);
                                            });
                                          },
                                    icon: const Icon(Icons.fact_check_outlined),
                                    label: const Text('Seleccionar'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await context.push(
                                        _cotizacionesRouteForSelectedClient(),
                                      );
                                      if (!mounted) return;
                                      await _checkCotizacionesForSelectedClient();
                                      final picked =
                                          await _openCotizacionPickerDialog();
                                      if (!mounted || picked == null) return;
                                      setState(() {
                                        _selectedCotizacion = picked;
                                        _quotedCtrl.text = picked.total
                                            .toStringAsFixed(2);
                                      });
                                    },
                                    icon: const Icon(Icons.add_box_outlined),
                                    label: const Text('Crear'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                CreateOrderSection(
                  title: 'Programación',
                  icon: Icons.event_available_outlined,
                  subtitle:
                      'Controla el estado operativo de la orden y asigna el técnico responsable.',
                  child: Column(
                    children: [
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: orderStateField),
                            const SizedBox(width: 10),
                            Expanded(child: technicianField),
                          ],
                        )
                      else ...[
                        orderStateField,
                        const SizedBox(height: 10),
                        technicianField,
                      ],
                      if (!_loadingTechnicians && _technicians.isEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'No tienes técnicos registrados. Puedes guardar sin asignar o crear uno ahora.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: _saving
                                    ? null
                                    : () => context.push(Routes.users),
                                icon: const Icon(
                                  Icons.person_add_alt_1_outlined,
                                ),
                                label: const Text('Crear técnico'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                CreateOrderSection(
                  title: 'Clasificación del servicio',
                  icon: Icons.category_outlined,
                  subtitle:
                      'Clasifica correctamente la orden para que el flujo operativo quede bien definido.',
                  child: Column(
                    children: [
                      if (widget.showServiceTypeField) ...[
                        if (isWide)
                          Row(
                            children: [
                              Expanded(child: serviceTypeField),
                              const SizedBox(width: 10),
                              Expanded(child: categoryField),
                            ],
                          )
                        else ...[
                          serviceTypeField,
                          const SizedBox(height: 10),
                          categoryField,
                        ],
                      ] else
                        categoryField,
                      Builder(
                        builder: (context) {
                          final kind = (widget.agendaKind ?? '')
                              .trim()
                              .toLowerCase();
                          if (kind == 'garantia') {
                            return Column(
                              children: [
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _relatedServiceCtrl,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    labelText:
                                        'Orden anterior / Servicio relacionado (opcional)',
                                  ),
                                ),
                              ],
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                CreateOrderSection(
                  title: 'Referencias del cliente',
                  icon: Icons.perm_media_outlined,
                  subtitle:
                      'Agrega el contexto visual y descriptivo que el técnico necesita antes de salir a la visita.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _referenceTextCtrl,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Texto de referencia (opcional)',
                          helperText:
                              'Ej: “Casa azul, portón negro, al lado del colmado”.',
                        ),
                        validator: (_) => null,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _pickReferenceImages,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Agregar fotos'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _pickReferenceVideo,
                            icon: const Icon(Icons.videocam_outlined),
                            label: Text(
                              _referenceVideo == null
                                  ? 'Agregar video'
                                  : 'Cambiar video',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                (_referenceImages.isEmpty &&
                                    _referenceVideo == null)
                                ? null
                                : () {
                                    setState(() {
                                      _referenceImages = const [];
                                      _referenceVideo = null;
                                    });
                                    _clearReferenceVideoPreview();
                                  },
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: const Text('Quitar todo'),
                          ),
                        ],
                      ),
                      if (_referenceImages.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Fotos seleccionadas: ${_referenceImages.length}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(_referenceImages.length, (
                              index,
                            ) {
                              final f = _referenceImages[index];
                              return Padding(
                                padding: EdgeInsets.only(
                                  right: index == _referenceImages.length - 1
                                      ? 0
                                      : 8,
                                ),
                                child: Stack(
                                  children: [
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () =>
                                            _openReferenceImageFullScreen(f),
                                        borderRadius: BorderRadius.circular(14),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          child: Container(
                                            width: 76,
                                            height: 76,
                                            decoration: BoxDecoration(
                                              color: scheme
                                                  .surfaceContainerHighest,
                                              border: Border.all(
                                                color: scheme.outline
                                                    .withValues(alpha: 0.25),
                                              ),
                                            ),
                                            child:
                                                (f.bytes != null &&
                                                    f.bytes!.isNotEmpty)
                                                ? Image.memory(
                                                    f.bytes!,
                                                    fit: BoxFit.cover,
                                                  )
                                                : ((f.path ?? '')
                                                      .trim()
                                                      .isNotEmpty)
                                                ? localFileImage(
                                                    path: f.path!.trim(),
                                                    fit: BoxFit.cover,
                                                  )
                                                : Center(
                                                    child: Icon(
                                                      Icons.image_outlined,
                                                      color: scheme.onSurface
                                                          .withValues(
                                                            alpha: 0.65,
                                                          ),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: InkWell(
                                        onTap: () =>
                                            _removeReferenceImageAt(index),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: scheme.surface.withValues(
                                              alpha: 0.92,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: scheme.outline.withValues(
                                                alpha: 0.25,
                                              ),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.close_rounded,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                      if (_referenceVideo != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.videocam_outlined, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Video: ${_referenceVideo!.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() => _referenceVideo = null);
                                _clearReferenceVideoPreview();
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        _buildReferenceVideoPreview(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                CreateOrderSection(
                  title: 'Ubicación',
                  icon: Icons.place_outlined,
                  subtitle:
                      'Completa la dirección y el enlace GPS para que el técnico llegue con precisión.',
                  child: buildLocationFields(addressField),
                ),
                const SizedBox(height: 12),
                CreateOrderSection(
                  title: 'Notas y observaciones',
                  icon: Icons.notes_rounded,
                  subtitle:
                      'Agrega el contexto operativo o comercial que no debe perderse en la ejecución.',
                  child: TextFormField(
                    controller: _descriptionCtrl,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Nota (opcional)',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                CreateOrderSection(
                  title: 'Datos económicos',
                  icon: Icons.payments_outlined,
                  subtitle:
                      'Completa el valor comercial y el estado de cobro sin afectar la lógica actual del formulario.',
                  child: Column(
                    children: [
                      if (isCompact) ...[
                        TextFormField(
                          controller: _quotedCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Precio vendido',
                          ),
                          validator: _requiredPriceValidator,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _depositCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Abono (señal)',
                            helperText: 'Si hay abono, se marca como SEGURO',
                          ),
                        ),
                      ] else
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _quotedCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  labelText: 'Precio vendido',
                                ),
                                validator: _requiredPriceValidator,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _depositCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  labelText: 'Abono (señal)',
                                  helperText:
                                      'Si hay abono, se marca como SEGURO',
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: safePaymentStatus,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Estado de pago',
                        ),
                        items: paymentStatusItems,
                        onChanged: (value) {
                          final next = (value ?? 'pendiente')
                              .trim()
                              .toLowerCase();
                          setState(() {
                            _paymentStatus = next;
                            if (next != 'pagado') _paidAmountCtrl.clear();
                          });
                        },
                      ),
                      if (_paymentStatus == 'pagado') ...[
                        const SizedBox(height: 10),
                        if (isCompact) ...[
                          TextFormField(
                            controller: _paidAmountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Monto pagado',
                            ),
                            validator: (value) {
                              if (_paymentStatus != 'pagado') return null;
                              final raw = (value ?? '').trim();
                              if (raw.isEmpty) return 'Requerido';
                              final parsed = double.tryParse(raw);
                              if (parsed == null || parsed <= 0) {
                                return 'Requerido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: safePaymentMethod,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Método de pago',
                            ),
                            items: paymentMethodItems,
                            onChanged: (value) {
                              setState(
                                () => _paymentMethod = (value ?? 'efectivo')
                                    .trim()
                                    .toLowerCase(),
                              );
                            },
                          ),
                        ] else
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _paidAmountCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    labelText: 'Monto pagado',
                                  ),
                                  validator: (value) {
                                    if (_paymentStatus != 'pagado') return null;
                                    final raw = (value ?? '').trim();
                                    if (raw.isEmpty) return 'Requerido';
                                    final parsed = double.tryParse(raw);
                                    if (parsed == null || parsed <= 0) {
                                      return 'Requerido';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: safePaymentMethod,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    labelText: 'Método de pago',
                                  ),
                                  items: paymentMethodItems,
                                  onChanged: (value) {
                                    setState(
                                      () =>
                                          _paymentMethod = (value ?? 'efectivo')
                                              .trim()
                                              .toLowerCase(),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                CreateOrderFooterBar(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Revisa los datos principales antes de guardar. Las validaciones y el flujo actual se mantienen sin cambios.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          elevation: 1,
                          shadowColor: scheme.primary.withValues(alpha: 0.25),
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _saving ? 'Guardando...' : widget.submitLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openClientPicker() async {
    final selected = await _openClientPickerDialog();
    if (!mounted || selected == null) return;
    setState(() {
      _customerId = selected.id;
      _customerName = selected.nombre;
      _customerPhone = selected.telefono;
      _addressCtrl.text = selected.direccion ?? '';
      _selectedCotizacion = null;
      _hasCotizaciones = false;
    });

    // Evita arrastrar precio/cotización de un cliente anterior.
    _quotedCtrl.clear();

    await _checkCotizacionesForSelectedClient();
  }

  Future<void> _pickReservationDate() async {
    final now = DateTime.now();
    final initial = _reservationAt ?? now;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (!mounted || pickedDate == null) return;

    final initialTimeSource = _reservationAt ?? DateTime.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialTimeSource),
    );
    if (!mounted || pickedTime == null) return;

    final next = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      _reservationAt = next;
      _reservationDateCtrl.text = DateFormat(
        'dd/MM/yyyy h:mm a',
        'es_DO',
      ).format(next);
    });
  }

  Future<CotizacionModel?> _openCotizacionPickerDialog() async {
    final phone = (_customerPhone ?? '').trim();
    if (phone.isEmpty) return null;

    return showDialog<CotizacionModel>(
      context: context,
      builder: (context) {
        var loading = true;
        String? error;
        List<CotizacionModel> items = const [];
        var didInit = false;

        String money(double value) => NumberFormat.currency(
          locale: 'es_DO',
          symbol: 'RD\$',
        ).format(value);

        Future<void> load(StateSetter setDialogState) async {
          setDialogState(() {
            loading = true;
            error = null;
          });
          try {
            final rows = await ref
                .read(cotizacionesRepositoryProvider)
                .list(customerPhone: phone);
            if (!context.mounted) return;
            setDialogState(() {
              items = rows;
              loading = false;
            });
          } catch (e) {
            if (!context.mounted) return;
            setDialogState(() {
              error = e is ApiException ? e.message : '$e';
              loading = false;
            });
          }
        }

        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                if (!didInit) {
                  didInit = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    load(setDialogState);
                  });
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Seleccionar cotización',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Cliente: ${_customerName ?? '—'} · $phone',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: loading
                                ? null
                                : () => load(setDialogState),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Recargar'),
                          ),
                        ],
                      ),
                      if (loading) const LinearProgressIndicator(),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: items.isEmpty
                            ? const Center(
                                child: Text('No hay cotizaciones para mostrar'),
                              )
                            : ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return ListTile(
                                    title: Text(
                                      money(item.total),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      DateFormat(
                                        'dd/MM/yyyy h:mm a',
                                        'es_DO',
                                      ).format(item.createdAt),
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () => Navigator.pop(context, item),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(context);
                          context.push(_cotizacionesRouteForSelectedClient());
                        },
                        icon: const Icon(Icons.add_box_outlined),
                        label: const Text('Crear nueva cotización'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _checkCotizacionesForSelectedClient() async {
    final phone = (_customerPhone ?? '').trim();
    if (phone.isEmpty) {
      if (!mounted) return;
      setState(() {
        _hasCotizaciones = false;
        _checkingCotizaciones = false;
        _selectedCotizacion = null;
      });
      return;
    }

    setState(() => _checkingCotizaciones = true);
    try {
      final rows = await ref
          .read(cotizacionesRepositoryProvider)
          .list(customerPhone: phone, take: 1);
      if (!mounted) return;
      final latest = rows.isEmpty ? null : rows.first;
      setState(() {
        _hasCotizaciones = latest != null;

        // Por defecto, toma el precio vendido del total de la última cotización.
        // No pisa si el usuario ya escribió un precio.
        if (latest != null && _selectedCotizacion == null) {
          _selectedCotizacion = latest;
          if (_quotedCtrl.text.trim().isEmpty) {
            _quotedCtrl.text = latest.total.toStringAsFixed(2);
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasCotizaciones = false);
    } finally {
      if (mounted) setState(() => _checkingCotizaciones = false);
    }
  }

  Future<ClienteModel?> _openClientPickerDialog() async {
    return showDialog<ClienteModel>(
      context: context,
      builder: (context) {
        final queryCtrl = TextEditingController(text: _searchClientCtrl.text);
        var loading = false;
        var items = <ClienteModel>[];
        var didInitLoad = false;

        Future<void> runSearch(StateSetter setDialogState) async {
          final query = queryCtrl.text.trim();
          setDialogState(() => loading = true);
          try {
            final results = await ref
                .read(operationsControllerProvider.notifier)
                .searchClients(query);
            if (!context.mounted) return;
            setDialogState(() => items = results);
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e is ApiException ? e.message : '$e')),
            );
          } finally {
            if (context.mounted) setDialogState(() => loading = false);
          }
        }

        Future<void> addNewClient(StateSetter setDialogState) async {
          final created = await _promptNewClientDialog();
          if (!context.mounted || created == null) return;
          Navigator.pop(context, created);
        }

        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                if (!didInitLoad) {
                  didInitLoad = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    runSearch(setDialogState);
                  });
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Cliente',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: queryCtrl,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Buscar cliente',
                              ),
                              onSubmitted: (_) => runSearch(setDialogState),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: loading
                                ? null
                                : () => runSearch(setDialogState),
                            icon: const Icon(Icons.search),
                            label: const Text('Buscar'),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: loading
                              ? null
                              : () => addNewClient(setDialogState),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Agregar cliente'),
                        ),
                      ),
                      if (loading) const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Expanded(
                        child: items.isEmpty
                            ? const Center(
                                child: Text('Sin clientes para mostrar'),
                              )
                            : ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return ListTile(
                                    title: Text(item.nombre),
                                    subtitle: Text(item.telefono),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () => Navigator.pop(context, item),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<ClienteModel?> _promptNewClientDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (ok != true) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      return null;
    }

    try {
      final created = await ref
          .read(operationsControllerProvider.notifier)
          .createQuickClient(
            nombre: nameCtrl.text.trim(),
            telefono: phoneCtrl.text.trim(),
          );
      return created;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
      return null;
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
    }
  }

  Future<void> _save() async {
    if (_customerId == null || _customerId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un cliente primero')),
      );
      return;
    }

    final selectedCategory = _selectedCategory;
    if (selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La categoría es requerida')),
      );
      return;
    }

    if (_priority < 1 || _priority > 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La prioridad es requerida')),
      );
      return;
    }

    if (_isAgendaReserva) {
      final phone = (_customerPhone ?? '').trim();
      if (phone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El cliente debe tener teléfono')),
        );
        return;
      }

      if (_selectedCotizacion == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona o crea una cotización')),
        );
        return;
      }
    }

    if (!_formKey.currentState!.validate()) return;

    final quoted = double.tryParse(_quotedCtrl.text.trim());
    final deposit = double.tryParse(_depositCtrl.text.trim());
    if (quoted == null || quoted <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La cotizacion es obligatoria para crear la orden'),
        ),
      );
      return;
    }

    if ((deposit ?? 0) > 0) {
      if (deposit! > quoted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El abono no puede ser mayor que el precio vendido'),
          ),
        );
        return;
      }
    }

    final tags = <String>[];
    if ((deposit ?? 0) > 0) tags.add('seguro');

    String? paymentNote;
    if (_paymentStatus.trim().toLowerCase() == 'pagado') {
      final paidAmount = double.tryParse(_paidAmountCtrl.text.trim());
      if (paidAmount == null || paidAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El monto pagado es requerido')),
        );
        return;
      }

      final method = _paymentMethod.trim().toLowerCase();
      if (method.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El método de pago es requerido')),
        );
        return;
      }

      paymentNote = _buildPaymentNote(
        status: 'pagado',
        amount: paidAmount,
        method: method,
      );
    }

    setState(() => _saving = true);
    try {
      final gpsText = _gpsCtrl.text.trim();
      if (gpsText.isNotEmpty && _gpsPoint == null && !_resolvingGps) {
        _setResolvingGps(true);
        try {
          final point = await _resolveLatLngFromText(gpsText);
          if (!mounted) return;
          _setResolvingGps(false);
          if (point != null) {
            _setGpsPoint(point);
          }
        } catch (_) {
          if (!mounted) return;
          _setResolvingGps(false);
        }
      }

      final title =
          '${widget.showServiceTypeField ? _serviceTypeLabel(_serviceType) : _agendaKindLabel(widget.agendaKind)} · ${selectedCategory.displayName}';
      final note = _descriptionCtrl.text.trim();
      final description = note.isEmpty ? 'Sin nota' : note;
      final reservationAt = _reservationAt;

      await widget.onCreate(
        _CreateServiceDraft(
          customerId: _customerId!,
          serviceType: _serviceType,
          categoryId: _categoryIdForSubmit(selectedCategory),
          categoryCode: selectedCategory.code,
          priority: _priority,
          reservationAt: reservationAt,
          title: title,
          description: description,
          orderState: _orderState,
          technicianId: _technicianId,
          addressSnapshot: _buildAddressSnapshot(),
          relatedServiceId: _relatedServiceCtrl.text.trim().isEmpty
              ? null
              : _relatedServiceCtrl.text.trim(),
          quotedAmount: quoted,
          depositAmount: deposit,
          paymentNote: paymentNote,
          tags: tags,
          referenceText: _referenceTextCtrl.text.trim(),
          referenceImages: _referenceImages,
          referenceVideo: _referenceVideo,
        ),
      );
      if (!mounted) return;
      _formKey.currentState!.reset();
      _reservationDateCtrl.clear();
      _reservationAt = null;
      _descriptionCtrl.clear();
      _referenceTextCtrl.clear();
      _addressCtrl.clear();
      _gpsCtrl.clear();
      _gpsResolveDebounce?.cancel();
      _setGpsPoint(null);
      _setResolvingGps(false);
      _referenceImages = const [];
      _referenceVideo = null;
      _orderState = 'pendiente';
      _technicianId = null;
      _priorityTouched = false;
      _relatedServiceCtrl.clear();
      _quotedCtrl.clear();
      _depositCtrl.clear();
      _paidAmountCtrl.clear();
      setState(() {
        _paymentStatus = 'pendiente';
        _paymentMethod = 'efectivo';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // _createQuickClient() eliminado: ahora se maneja desde el diálogo de Cliente.
}

class _CreateReservationWarmup extends StatelessWidget {
  final bool usingFallbackCategories;

  const _CreateReservationWarmup({required this.usingFallbackCategories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget line({double height = 18, double? width}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    Widget block({double height = 56}) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Abriendo formulario...',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                usingFallbackCategories
                    ? 'Cargando categorías y técnicos en segundo plano para abrir el formulario de inmediato.'
                    : 'Preparando campos y catálogos en segundo plano para que puedas empezar enseguida.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 3),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(width: 120),
              const SizedBox(height: 10),
              line(width: 220),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(width: 180, child: block()),
                  SizedBox(width: 180, child: block()),
                  SizedBox(width: 180, child: block()),
                ],
              ),
              const SizedBox(height: 14),
              block(height: 110),
              const SizedBox(height: 10),
              block(height: 110),
            ],
          ),
        ),
      ],
    );
  }
}

class _PunchOnlySheet extends ConsumerWidget {
  const _PunchOnlySheet();

  static IconData _iconFor(PunchType type) {
    return switch (type) {
      PunchType.entradaLabor => Icons.login,
      PunchType.salidaLabor => Icons.exit_to_app,
      PunchType.salidaPermiso => Icons.meeting_room_outlined,
      PunchType.entradaPermiso => Icons.door_back_door,
      PunchType.salidaAlmuerzo => Icons.fastfood,
      PunchType.entradaAlmuerzo => Icons.restaurant,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(punchControllerProvider);
    final notifier = ref.read(punchControllerProvider.notifier);
    final theme = Theme.of(context);

    Future<void> handlePunch(PunchType type) async {
      if (state.creating) return;
      try {
        await notifier.register(type);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ponche "${type.label}" registrado')),
        );
        Navigator.of(context).pop();
      } catch (e) {
        if (!context.mounted) return;
        final message = e is ApiException ? e.message : 'No se pudo ponchar';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }

    return Material(
      color: theme.colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ponchado rápido',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: state.creating
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
            Text(
              '¿Qué deseas registrar?',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            if (state.error != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.error!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ListTileTheme(
                  dense: true,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                    itemCount: PunchType.values.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final type = PunchType.values[index];
                      return ListTile(
                        enabled: !state.creating,
                        leading: Icon(
                          _iconFor(type),
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(type.label),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: state.creating ? null : () => handlePunch(type),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (state.creating)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogoFabIcon extends StatelessWidget {
  const _CatalogoFabIcon();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = IconTheme.of(context).color ?? scheme.onPrimary;
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 24, color: color),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.onPrimary.withValues(alpha: 0.18),
                border: Border.all(
                  color: scheme.onPrimary.withValues(alpha: 0.28),
                  width: 1,
                ),
              ),
              child: Center(
                child: Icon(Icons.search_rounded, size: 12, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileOperationsFabButton extends StatelessWidget {
  const _MobileOperationsFabButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.accentColor,
    required this.delay,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback onPressed;
  final Color accentColor;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final staggerStart = (delay.inMilliseconds / 420).clamp(0.0, 0.75);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final eased = Interval(
          staggerStart,
          1,
          curve: Curves.easeOutCubic,
        ).transform(value);
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, (1 - eased) * 10),
            child: Transform.scale(scale: 0.96 + (0.04 * eased), child: child),
          ),
        );
      },
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      accentColor.withValues(alpha: 0.14),
                      scheme.surfaceContainerHighest,
                    ),
                    Color.alphaBlend(
                      accentColor.withValues(alpha: 0.06),
                      scheme.surface,
                    ),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accentColor.withValues(alpha: 0.24)),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Center(child: icon),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PoncheFabIcon extends StatelessWidget {
  const _PoncheFabIcon();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = IconTheme.of(context).color ?? scheme.onPrimary;
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(Icons.meeting_room_outlined, size: 24, color: color),
          Positioned(
            right: -2,
            bottom: -3,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.onPrimary.withValues(alpha: 0.18),
                border: Border.all(
                  color: scheme.onPrimary.withValues(alpha: 0.28),
                  width: 1,
                ),
              ),
              child: Center(
                child: Transform.rotate(
                  angle: -0.12,
                  child: Icon(Icons.touch_app_outlined, size: 12, color: color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsMapPreviewCard extends StatelessWidget {
  final LatLng? point;
  final String? mapsUrl;
  final VoidCallback onOpen;
  final VoidCallback onNavigate;

  const _GpsMapPreviewCard({
    required this.point,
    required this.mapsUrl,
    required this.onOpen,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 170,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: point != null
                    ? InkWell(
                        onTap: onOpen,
                        child: IgnorePointer(
                          ignoring: true,
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: point!,
                              initialZoom: 15,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none,
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'fulltech_app',
                                tileProvider: NetworkTileProvider(),
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    width: 50,
                                    height: 50,
                                    point: point!,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Icon(
                                          Icons.location_on,
                                          color: scheme.onSurface.withValues(
                                            alpha: 0.35,
                                          ),
                                          size: 50,
                                        ),
                                        Icon(
                                          Icons.location_on,
                                          color: scheme.primary,
                                          size: 46,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : MapPreview(mapsUrl: (mapsUrl ?? '').trim(), height: 170),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  point != null ? Icons.open_in_full : Icons.link_rounded,
                  size: 16,
                  color: scheme.onSurface.withValues(alpha: 0.70),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    point != null
                        ? 'Ver mapa en pantalla completa'
                        : 'Ubicación detectada desde el enlace',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface.withValues(alpha: 0.80),
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onNavigate,
                  icon: const Icon(Icons.directions_outlined, size: 18),
                  label: const Text('Ir'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              point != null
                  ? formatLatLng(point!)
                  : ((mapsUrl ?? '').trim().isEmpty
                        ? 'Ubicación disponible'
                        : (mapsUrl ?? '').trim()),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openBestNavigation(BuildContext context, LatLng point) async {
  final dest = '${point.latitude},${point.longitude}';
  final googleDirectionsUrl = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeQueryComponent(dest)}&travelmode=driving',
  );

  final wazeAppUrl = Uri.parse('waze://?ll=$dest&navigate=yes');

  Future<bool> safeLaunch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {
      // Fall through to OS-level launch.
    }
    return openUrlWithOs(uri);
  }

  void showFail(String appName) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('No se pudo abrir $appName')));
  }

  final platform = defaultTargetPlatform;
  final isDesktop =
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS;

  // Desktop UX: open the browser directly (Waze app scheme isn't expected there).
  if (isDesktop) {
    final ok = await safeLaunch(googleDirectionsUrl);
    if (!ok) showFail('Google Maps');
    return;
  }

  // One-tap behavior: prefer Waze (app), fallback to Google Maps.
  if (await safeLaunch(wazeAppUrl)) return;
  final googleUrl = platform == TargetPlatform.android
      ? Uri.parse('google.navigation:q=$dest&mode=d')
      : googleDirectionsUrl;

  final ok = await safeLaunch(googleUrl);
  if (!ok) showFail('Google Maps');
}

class _AgendaGpsFullMapScreen extends StatefulWidget {
  final LatLng point;
  final String title;

  const _AgendaGpsFullMapScreen({required this.point, required this.title});

  @override
  State<_AgendaGpsFullMapScreen> createState() =>
      _AgendaGpsFullMapScreenState();
}

class _AgendaGpsFullMapScreenState extends State<_AgendaGpsFullMapScreen> {
  final _mapController = MapController();
  LatLng? _myPoint;
  bool _locating = false;

  String get _coordsText => formatLatLng(widget.point);

  Future<void> _navigateExternal() async {
    await _openBestNavigation(context, widget.point);
  }

  Future<void> _copyCoords() async {
    await Clipboard.setData(ClipboardData(text: _coordsText));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copiado: $_coordsText')));
  }

  Future<void> _copyDirectionsLink() async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeQueryComponent(_coordsText)}&travelmode=driving',
    ).toString();
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link de navegación copiado')));
  }

  void _centerOnDestination() {
    _mapController.move(widget.point, 16);
  }

  Future<void> _centerOnMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      // On Windows desktop, location plugins can hang the app ("No responde")
      // depending on OS/location settings. Fail fast with a clear message.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ubicación no disponible en Windows. Usa Android/iOS para GPS.',
            ),
          ),
        );
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activa el GPS del dispositivo')),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permiso de ubicación denegado')),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final p = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _myPoint = p);
      _mapController.move(p, 16);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener tu ubicación')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final destinationMarker = Marker(
      width: 56,
      height: 56,
      point: widget.point,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.location_on,
            color: scheme.onSurface.withValues(alpha: 0.35),
            size: 58,
          ),
          Icon(Icons.location_on, color: scheme.primary, size: 52),
        ],
      ),
    );

    final myMarker = _myPoint == null
        ? null
        : Marker(
            width: 22,
            height: 22,
            point: _myPoint!,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.secondary,
                border: Border.all(color: scheme.onSecondary, width: 2),
              ),
            ),
          );

    return Scaffold(
      appBar: AppBar(
        leading: const OperationsBackButton(fallbackRoute: Routes.operaciones),
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Copiar coordenadas',
            onPressed: _copyCoords,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Copiar link navegación',
            onPressed: _copyDirectionsLink,
            icon: const Icon(Icons.link_outlined),
          ),
          IconButton(
            tooltip: 'Ir',
            onPressed: _navigateExternal,
            icon: const Icon(Icons.directions_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: widget.point, initialZoom: 16),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'fulltech_app',
                  tileProvider: NetworkTileProvider(),
                ),
                MarkerLayer(
                  markers: [destinationMarker, if (myMarker != null) myMarker],
                ),
              ],
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'gps-center-dest',
                    tooltip: 'Centrar ubicación',
                    onPressed: _centerOnDestination,
                    child: const Icon(Icons.my_location_outlined),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: 'gps-my-location',
                    tooltip: 'Mi ubicación',
                    onPressed: _locating ? null : _centerOnMyLocation,
                    child: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_pin_circle_outlined),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: 'gps-navigate',
                    tooltip: 'Ir',
                    onPressed: _navigateExternal,
                    child: const Icon(Icons.directions_outlined),
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
