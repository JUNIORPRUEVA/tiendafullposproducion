import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/company/company_settings_model.dart';
import '../../../core/company/company_settings_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/routing/routes.dart';
import '../../../core/utils/local_file_bytes.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../modules/cotizaciones/cotizacion_models.dart';
import '../../../modules/cotizaciones/data/cotizaciones_repository.dart';
import '../data/operations_repository.dart';
import '../operations_models.dart';
import '../presentation/operations_back_button.dart';
import '../presentation/operations_permissions.dart';
import '../presentation/status_picker_sheet.dart';
import '../presentation/service_location_helpers.dart';
import '../presentation/service_pdf_exporter.dart';
import '../presentation/service_documents_editor_screen.dart';
import 'technical_service_execution_controller.dart';
import 'widgets/dynamic_checklist_experience.dart';
import 'widgets/manage_service_ui.dart';
import 'widgets/service_closure_card.dart';
import 'widgets/service_report_pdf_screen.dart';
import 'widgets/signature_screen.dart';
import 'widgets/technical_execution_cards.dart';

class TechnicalServiceExecutionScreen extends ConsumerStatefulWidget {
  final String serviceId;

  const TechnicalServiceExecutionScreen({super.key, required this.serviceId});

  @override
  ConsumerState<TechnicalServiceExecutionScreen> createState() =>
      _TechnicalServiceExecutionScreenState();
}

class _TechnicalServiceExecutionScreenState
    extends ConsumerState<TechnicalServiceExecutionScreen> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _signaturePreviewBytes;
  final GlobalKey _callActionKey = GlobalKey(debugLabel: 'opsTechCallAction');
  final GlobalKey _orderActionKey = GlobalKey(debugLabel: 'opsTechOrderAction');
  final GlobalKey _quoteActionKey = GlobalKey(debugLabel: 'opsTechQuoteAction');
  final GlobalKey _locationActionKey = GlobalKey(
    debugLabel: 'opsTechLocationAction',
  );

  bool _isInvoicePaid(ServiceModel service) {
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

    final updates = service.updates;
    for (var i = updates.length - 1; i >= 0; i--) {
      final msg = updates[i].message.trim();
      if (!msg.startsWith('[PAGO]')) continue;
      final rest = msg.substring('[PAGO]'.length).trim();
      final kv = parseKv(rest);
      final status = (kv['estado'] ?? kv['status'] ?? 'pendiente')
          .trim()
          .toLowerCase();
      return status == 'pagado';
    }
    return false;
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '—';
    final v = dt.toLocal();
    final d = v.day.toString().padLeft(2, '0');
    final m = v.month.toString().padLeft(2, '0');
    final y = v.year.toString();
    return '$d/$m/$y';
  }

  String _money(double? value) {
    if (value == null) return '';
    final safe = value.isNaN ? 0.0 : value;
    return 'RD\$${safe.toStringAsFixed(2)}';
  }

  String? _infoOrNull(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty || value == '—' || value.toLowerCase() == 'null') {
      return null;
    }
    return value;
  }

  String _humanizeValue(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return '—';
    return cleaned
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .map((part) {
          final lower = part.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  ({String kind, String text})? _parseTechInfoMessage(String raw) {
    final msg = raw.trim();
    if (msg.isEmpty) return null;

    final re = RegExp(r'kind=([^|]+)\|text=(.*)$', dotAll: true);
    final m = re.firstMatch(msg);
    if (m == null) return null;
    final kind = (m.group(1) ?? '').trim().toLowerCase();
    final text = (m.group(2) ?? '').trim();
    if (kind.isEmpty || text.isEmpty) return null;
    return (kind: kind, text: text);
  }

  String _kindLabel(String kind) {
    switch (kind.trim().toLowerCase()) {
      case 'novedad':
        return 'Novedad';
      case 'producto':
        return 'Producto';
      case 'nota':
        return 'Nota';
      default:
        return kind.trim().isEmpty ? 'Info' : kind.trim();
    }
  }

  IconData _kindIcon(String kind) {
    switch (kind.trim().toLowerCase()) {
      case 'novedad':
        return Icons.campaign_outlined;
      case 'producto':
        return Icons.inventory_2_outlined;
      case 'nota':
        return Icons.note_add_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _kindAccentColor(ColorScheme cs, String kind) {
    switch (kind.trim().toLowerCase()) {
      case 'novedad':
        return const Color(0xFFE85D2A);
      case 'producto':
        return const Color(0xFF2F6FED);
      case 'nota':
        return cs.outline;
      default:
        return cs.primary;
    }
  }

  String _compactRelativeTime(DateTime? dt) {
    if (dt == null) return 'Ahora';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays}d';
    return _fmtDate(dt);
  }

  bool _isRecentlyAdded(DateTime? dt) {
    if (dt == null) return false;
    return DateTime.now().difference(dt.toLocal()).inMinutes < 5;
  }

  String _compactAuthor(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'Sistema';
    final parts = text
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.length <= 2) return text;
    return '${parts.first} ${parts[1]}';
  }

  Future<void> _previewEvidence(ServiceFileModel file) async {
    if (!mounted) return;

    final urlRaw = file.fileUrl.trim();
    if (urlRaw.isEmpty) return;

    final lower = urlRaw.toLowerCase();
    final mime = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final isImage =
        mime.contains('image') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
    final isVideo = mime.contains('video') || lower.endsWith('.mp4');

    final uri = Uri.tryParse(urlRaw);
    if (uri == null) {
      _showSnackBarPostFrame(
        const SnackBar(content: Text('URL de archivo inválida')),
      );
      return;
    }

    if (isVideo) {
      await showDialog<void>(
        context: context,
        builder: (_) => _VideoPreviewDialog(url: urlRaw),
      );
      return;
    }

    if (!isImage) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final cs = theme.colorScheme;
        final caption = (file.caption ?? '').trim();

        return Dialog(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: cs.surfaceContainerHighest,
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          caption.isEmpty ? 'Evidencia' : caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Abrir externo',
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: const Icon(Icons.open_in_new),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 520),
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Image.network(
                      urlRaw,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No se pudo cargar la imagen',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
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

  void _postFrame(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      action();
    });
  }

  void _showSnackBarPostFrame(SnackBar snackBar) {
    _postFrame(() {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(snackBar);
    });
  }

  bool _isReadOnly({required ServiceModel service, required dynamic user}) {
    final perms = OperationsPermissions(user: user, service: service);
    if (!perms.canOperate) return true;
    if (perms.isAdminLike) return false;

    final status = parseStatus(service.status);
    return status == ServiceStatus.closed ||
        status == ServiceStatus.cancelled ||
        status == ServiceStatus.completed;
  }

  String _firstName(String raw) {
    final parts = raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return 'Cliente';
    return parts.first.trim();
  }

  String _effectiveState(ServiceModel service) {
    final admin = (service.adminStatus ?? '').toString().trim().toLowerCase();
    if (admin.isNotEmpty) return admin;
    final order = service.orderState.toString().trim().toLowerCase();
    if (order.isNotEmpty) return order;
    return service.status.toString().trim().toLowerCase();
  }

  String? _mapOrderStateToTechProgress(String orderState) {
    switch (orderState) {
      case 'en_camino':
        return 'tecnico_en_camino';
      case 'en_proceso':
        return 'instalacion_iniciada';
      case 'finalizada':
        return 'instalacion_finalizada';
      default:
        return null;
    }
  }

  List<ServiceChecklistTemplateModel> _visibleDynamicChecklists(
    TechnicalExecutionState state,
  ) {
    final templates = state.dynamicChecklists;
    if (templates.isEmpty) return const [];
    return templates;
  }

  bool _isChecklistComplete(List<ServiceChecklistTemplateModel> templates) {
    for (final template in templates) {
      for (final item in template.items) {
        if (item.isRequired && !item.isChecked) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _openChecklistSheet({
    required TechnicalExecutionController ctrl,
    required List<ServiceChecklistTemplateModel> templates,
    required bool readOnly,
    required bool busy,
    required String currentState,
  }) {
    return DynamicChecklistSheet.show(
      context,
      templates: templates,
      onChanged: (readOnly || busy)
          ? null
          : (itemId, checked) => ctrl.setDynamicChecklistItem(itemId, checked),
      onChecklistCompleted:
          (readOnly || busy || !_isChecklistComplete(templates))
          ? null
          : () => _showStatusSelector(
              context: context,
              ctrl: ctrl,
              currentState: currentState,
              readOnly: readOnly,
              busy: busy,
              visibleChecklists: templates,
              forcedNextState: 'finalizada',
            ),
      readOnly: readOnly,
      busy: busy,
    );
  }

  Future<void> _showStatusSelector({
    required BuildContext context,
    required TechnicalExecutionController ctrl,
    required String currentState,
    required bool readOnly,
    required bool busy,
    List<ServiceChecklistTemplateModel> visibleChecklists = const [],
    String? forcedNextState,
  }) async {
    if (readOnly) return;

    final picked =
        forcedNextState ??
        await StatusSelectorModal.show(
          context,
          current: currentState,
          allowedStates: const {
            'pendiente',
            'en_camino',
            'en_proceso',
            'finalizada',
            'cancelada',
          },
        );
    if (!context.mounted || picked == null) return;

    final next = picked.trim().toLowerCase();
    if (next.isEmpty || next == currentState) return;

    if (next == 'finalizada' &&
        visibleChecklists.isNotEmpty &&
        !_isChecklistComplete(visibleChecklists)) {
      _showSnackBarPostFrame(
        const SnackBar(
          content: Text(
            'Completa el checklist obligatorio antes de finalizar el servicio.',
          ),
        ),
      );
      unawaited(
        _openChecklistSheet(
          ctrl: ctrl,
          templates: visibleChecklists,
          readOnly: readOnly,
          busy: busy,
          currentState: currentState,
        ),
      );
      return;
    }

    final nextProgress = _mapOrderStateToTechProgress(next);
    if (nextProgress != null) {
      await ctrl.setTechProgress(nextProgress);
    } else {
      await ctrl.changeOrderState(
        orderState: next,
        message: 'Estado actualizado por técnico',
      );
    }
    if (!context.mounted) return;
    unawaited(HapticFeedback.selectionClick());
    _showSnackBarPostFrame(
      SnackBar(
        content: Text('Estado actualizado: ${StatusPickerSheet.label(next)}'),
      ),
    );
  }

  Future<void> _openOrderDetails(ServiceModel service) async {
    if (!mounted) return;
    final id = service.id.trim();
    if (id.isEmpty) return;
    _postFrame(() {
      if (!mounted) return;
      context.push(Routes.operacionesTecnicoOrder(id));
    });
  }

  Future<void> _callClient(ServiceModel service) async {
    final phone = service.customerPhone.trim();
    if (phone.isEmpty) return;
    final uri = Uri.tryParse('tel:$phone');
    if (uri == null) return;
    await launchUrl(uri);
  }

  Future<void> _openLocation(ServiceModel service) async {
    final info = buildServiceLocationInfo(
      addressOrText: service.customerAddress,
    );
    final uri = info.mapsUri;
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<CotizacionModel?> _loadLatestQuote(String phone) async {
    final repo = ref.read(cotizacionesRepositoryProvider);
    final items = await repo.list(customerPhone: phone, take: 40);
    if (items.isEmpty) return null;
    final sorted = [...items];
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.first;
  }

  Future<void> _showCallDialog(ServiceModel service) async {
    final phone = _infoOrNull(service.customerPhone);

    await showActionDialog<void>(
      context,
      anchorKey: _callActionKey,
      builder: (dialogContext) {
        return ActionDialog(
          icon: Icons.call_outlined,
          title: 'Llamar',
          subtitle: _infoOrNull(service.customerName),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (phone == null)
                Text(
                  'No hay un numero de telefono registrado para este cliente.',
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else ...[
                InfoRowWidget(label: 'Numero', value: phone),
                InfoRowWidget(
                  label: 'Orden',
                  value: _infoOrNull(service.orderLabel),
                ),
              ],
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
            FilledButton.icon(
              onPressed: phone == null
                  ? null
                  : () async {
                      Navigator.of(dialogContext).pop();
                      await _callClient(service);
                    },
              icon: const Icon(Icons.phone_forwarded_rounded),
              label: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showOrderDialog(ServiceModel service) async {
    final statusLabel = _serviceStatusOptionFor(_effectiveState(service)).label;
    final phaseText = phaseLabel(service.currentPhase);
    final scheduled = service.scheduledStart ?? service.scheduledEnd;
    final assigned = service.assignments
        .map((assignment) => assignment.userName.trim())
        .where((name) => name.isNotEmpty)
        .join(', ');

    await showActionDialog<void>(
      context,
      anchorKey: _orderActionKey,
      builder: (dialogContext) {
        return ActionDialog(
          icon: Icons.receipt_long_outlined,
          title: 'Orden',
          subtitle: _infoOrNull(service.orderLabel) ?? 'Sin numero visible',
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRowWidget(
                label: 'Numero',
                value: _infoOrNull(service.orderLabel),
              ),
              InfoRowWidget(
                label: 'Fecha',
                value: scheduled == null ? null : _fmtDate(scheduled),
              ),
              InfoRowWidget(label: 'Estado', value: statusLabel),
              InfoRowWidget(label: 'Fase', value: phaseText),
              InfoRowWidget(label: 'Tecnico', value: _infoOrNull(assigned)),
              InfoRowWidget(
                label: 'Servicio',
                value: _infoOrNull(service.serviceType) == null
                    ? null
                    : _humanizeValue(service.serviceType),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _openOrderDetails(service);
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Abrir orden'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCotizacionDialog(ServiceModel service) async {
    final phone = service.customerPhone.trim();
    final futureQuote = phone.isEmpty
        ? Future.value(null)
        : _loadLatestQuote(phone);

    await showActionDialog<void>(
      context,
      anchorKey: _quoteActionKey,
      builder: (dialogContext) {
        return ActionDialog(
          icon: Icons.request_quote_outlined,
          title: 'Cotizacion',
          subtitle: _infoOrNull(service.customerName),
          body: FutureBuilder<CotizacionModel?>(
            future: futureQuote,
            builder: (context, snap) {
              final quote = snap.data;
              final theme = Theme.of(context);
              final cs = theme.colorScheme;

              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Expanded(child: Text('Cargando cotizacion...')),
                    ],
                  ),
                );
              }

              if (quote == null) {
                return Text(
                  phone.isEmpty
                      ? 'Sin telefono del cliente para consultar cotizaciones.'
                      : 'No hay cotizaciones registradas para este cliente.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoRowWidget(
                    label: 'Fecha',
                    value: _fmtDate(quote.createdAt),
                  ),
                  InfoRowWidget(label: 'Estado', value: 'Registrada'),
                  InfoRowWidget(label: 'Monto', value: _money(quote.total)),
                  InfoRowWidget(
                    label: 'Subtotal',
                    value: quote.items.isEmpty ? null : _money(quote.subtotal),
                  ),
                  InfoRowWidget(
                    label: 'ITBIS',
                    value: quote.includeItbis
                        ? _money(quote.itbisAmount)
                        : null,
                  ),
                  InfoRowWidget(
                    label: 'Items',
                    value: quote.items.isEmpty
                        ? null
                        : '${quote.items.length} registrados',
                  ),
                  InfoRowWidget(
                    label: 'Nota',
                    value: _infoOrNull(quote.note),
                    multiline: true,
                  ),
                  if (quote.items.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Detalle',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final item in quote.items.take(4))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.nombre.trim().isEmpty
                                    ? 'Item'
                                    : item.nombre.trim(),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'x${item.qty.toStringAsFixed(0)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (quote.items.length > 4)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '+${quote.items.length - 4} items mas',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
            FilledButton.icon(
              onPressed: phone.isEmpty
                  ? null
                  : () {
                      Navigator.of(dialogContext).pop();
                      final uri = Uri(
                        path: Routes.cotizacionesHistorial,
                        queryParameters: {'customerPhone': phone, 'pick': '0'},
                      );
                      context.go(uri.toString());
                    },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Abrir historial'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddInfoDialog(TechnicalExecutionController ctrl) async {
    if (!mounted) return;

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Agregar Información'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: const Text('Agregar Novedad'),
                onTap: () => Navigator.pop(dialogContext, 'novedad'),
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Agregar Producto'),
                onTap: () => Navigator.pop(dialogContext, 'producto'),
              ),
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('Agregar Nota'),
                onTap: () => Navigator.pop(dialogContext, 'nota'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );

    if (selected == null || selected.trim().isEmpty) return;
    if (!mounted) return;

    final label = switch (selected) {
      'novedad' => 'Novedad',
      'producto' => 'Producto',
      _ => 'Nota',
    };

    final text = selected == 'producto'
        ? await _askProductDetails()
        : await _askMultilineText(
            title: 'Agregar $label',
            hintText: 'Escribe los detalles…',
          );
    if (text == null || text.trim().isEmpty) return;

    await _saveInfoUpdateWithFeedback(
      ctrl: ctrl,
      kind: selected,
      label: label,
      text: text.trim(),
    );
  }

  Future<void> _saveInfoUpdateWithFeedback({
    required TechnicalExecutionController ctrl,
    required String kind,
    required String label,
    required String text,
  }) async {
    try {
      await ctrl.addInfoUpdate(kind: kind, text: text);
      if (!mounted) return;
      _showSnackBarPostFrame(SnackBar(content: Text('$label guardado')));
    } catch (e) {
      if (!mounted) return;
      _showSnackBarPostFrame(
        SnackBar(content: Text('No se pudo guardar $label: $e')),
      );
    }
  }

  Future<String?> _askMultilineText({
    required String title,
    required String hintText,
  }) async {
    final controller = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: 6,
            decoration: InputDecoration(hintText: hintText),
            textInputAction: TextInputAction.newline,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Agregar'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return res;
  }

  Future<String?> _askProductDetails() async {
    final nameController = TextEditingController();
    final quantityController = TextEditingController();

    final res = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            String? quantityError;

            final rawQuantity = quantityController.text.trim();
            if (rawQuantity.isNotEmpty) {
              final parsed = int.tryParse(rawQuantity);
              if (parsed == null || parsed <= 0) {
                quantityError = 'Ingresa una cantidad válida';
              }
            }

            return AlertDialog(
              title: const Text('Agregar Producto'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del producto',
                      hintText: 'Ej. Fuente 12V 5A',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Cantidad',
                      hintText: 'Ej. 2',
                      errorText: quantityError,
                    ),
                    onChanged: (_) => setStateDialog(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final productName = nameController.text.trim();
                    final quantityText = quantityController.text.trim();
                    final quantity = int.tryParse(quantityText);

                    if (productName.isEmpty) {
                      return;
                    }
                    if (quantity == null || quantity <= 0) {
                      setStateDialog(() {});
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      'Cantidad: $quantity\nProducto: $productName',
                    );
                  },
                  child: const Text('Agregar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    quantityController.dispose();
    return res;
  }

  Future<void> _showContentDialog(TechnicalExecutionController ctrl) async {
    if (!mounted) return;

    final kind = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('¿Qué deseas subir?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Subir Imagen'),
                onTap: () => Navigator.pop(dialogContext, 'image'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Subir Video'),
                onTap: () => Navigator.pop(dialogContext, 'video'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
    if (kind == null) return;
    if (!mounted) return;

    final source = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Selecciona origen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Cámara'),
                onTap: () => Navigator.pop(dialogContext, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Archivos'),
                onTap: () => Navigator.pop(dialogContext, 'files'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
    if (source == null) return;
    if (!mounted) return;

    try {
      if (kind == 'image') {
        await _uploadImage(ctrl, source: source);
      } else {
        await _uploadVideo(ctrl, source: source);
      }
    } catch (e) {
      _showSnackBarPostFrame(
        SnackBar(content: Text('No se pudo subir contenido: $e')),
      );
    }
  }

  Future<void> _uploadImage(
    TechnicalExecutionController ctrl, {
    required String source,
  }) async {
    try {
      if (source == 'camera') {
        final xFile = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 88,
        );
        if (xFile == null) return;
        await ctrl.uploadEvidenceXFile(file: xFile, caption: 'Evidencia');
        return;
      }

      final xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (xFile != null) {
        await ctrl.uploadEvidenceXFile(file: xFile, caption: 'Evidencia');
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withReadStream: !kIsWeb,
        withData: kIsWeb,
      );
      final file = result?.files.isNotEmpty == true
          ? result!.files.first
          : null;
      if (file == null) return;
      await ctrl.uploadEvidence(file: file, caption: 'Evidencia');
    } catch (e) {
      _showSnackBarPostFrame(
        SnackBar(content: Text('No se pudo subir imagen: $e')),
      );
    }
  }

  Future<void> _uploadVideo(
    TechnicalExecutionController ctrl, {
    required String source,
  }) async {
    try {
      if (source == 'camera') {
        final xFile = await _picker.pickVideo(source: ImageSource.camera);
        if (xFile == null) return;
        await ctrl.uploadEvidenceXFile(file: xFile, caption: null);
        return;
      }

      final xFile = await _picker.pickVideo(source: ImageSource.gallery);
      if (xFile != null) {
        await ctrl.uploadEvidenceXFile(file: xFile, caption: null);
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['mp4'],
        withReadStream: !kIsWeb,
        withData: kIsWeb,
      );
      final file = result?.files.isNotEmpty == true
          ? result!.files.first
          : null;
      if (file == null) return;
      await ctrl.uploadEvidence(file: file, caption: null);
    } catch (e) {
      _showSnackBarPostFrame(
        SnackBar(content: Text('No se pudo subir video: $e')),
      );
    }
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final raw = url.trim();
    final uri = Uri.tryParse(raw);
    final scheme = (uri?.scheme ?? '').toLowerCase();
    final isWindowsPath = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(raw);

    if (scheme == 'file' || isWindowsPath) {
      final path = scheme == 'file' ? uri!.toFilePath() : raw;
      final bytes = await readLocalFileBytes(path);
      return Uint8List.fromList(bytes);
    }

    if (scheme != 'http' && scheme != 'https') {
      throw ApiException('Archivo no disponible para descarga');
    }

    final dio = ref.read(dioProvider);
    final res = await dio.get<List<int>>(
      raw,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data;
    if (data == null) return Uint8List(0);
    return Uint8List.fromList(data);
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

  Future<void> _openPdfBytesPreview({
    required String fileName,
    required Future<Uint8List> Function() loadBytes,
  }) async {
    if (!mounted) return;
    final future = Completer<void>();
    _postFrame(() async {
      try {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ServiceReportPdfScreen(
              fileName: fileName,
              loadBytes: loadBytes,
              currentUser: ref.read(authStateProvider).user,
            ),
          ),
        );
        if (!future.isCompleted) future.complete();
      } catch (e, st) {
        if (!future.isCompleted) future.completeError(e, st);
      }
    });
    await future.future;
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

    Uint8List? signatureBytes;
    String? signatureFileId;
    String? signatureFileUrl;
    DateTime? signedAt;
    try {
      final st = ref.read(
        technicalExecutionControllerProvider(widget.serviceId),
      );
      final sig = _readClientSignatureMeta(service, st.phaseSpecificData);
      signatureFileId = sig.fileId;
      signatureFileUrl = sig.fileUrl;
      signedAt = sig.signedAt;
      if ((signatureFileUrl ?? '').trim().isNotEmpty) {
        signatureBytes = await _downloadBytes(signatureFileUrl!.trim());
      }
    } catch (_) {
      signatureBytes = null;
    }

    await _openPdfBytesPreview(
      fileName: 'Factura-${service.orderLabel}.pdf',
      loadBytes: () => ServicePdfExporter.buildInvoicePdfBytes(
        service,
        cotizacion: quote,
        company: company,
        clientSignaturePngBytes: signatureBytes,
        clientSignatureFileId: signatureFileId,
        clientSignatureFileUrl: signatureFileUrl,
        clientSignedAt: signedAt,
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

    Uint8List? signatureBytes;
    String? signatureFileId;
    String? signatureFileUrl;
    DateTime? signedAt;
    try {
      final st = ref.read(
        technicalExecutionControllerProvider(widget.serviceId),
      );
      final sig = _readClientSignatureMeta(service, st.phaseSpecificData);
      signatureFileId = sig.fileId;
      signatureFileUrl = sig.fileUrl;
      signedAt = sig.signedAt;
      if ((signatureFileUrl ?? '').trim().isNotEmpty) {
        signatureBytes = await _downloadBytes(signatureFileUrl!.trim());
      }
    } catch (_) {
      signatureBytes = null;
    }

    await _openPdfBytesPreview(
      fileName: 'Carta-Garantia-${service.orderLabel}.pdf',
      loadBytes: () => ServicePdfExporter.buildWarrantyLetterBytes(
        service,
        cotizacion: quote,
        company: company,
        clientSignaturePngBytes: signatureBytes,
        clientSignatureFileId: signatureFileId,
        clientSignatureFileUrl: signatureFileUrl,
        clientSignedAt: signedAt,
      ),
    );
  }

  Future<void> _openDocumentEditor({
    required ServiceModel service,
    required ServiceDocumentType type,
  }) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ServiceDocumentsEditorScreen(service: service, type: type),
      ),
    );
    if (!mounted || ok != true) return;
    unawaited(
      ref
          .read(technicalExecutionControllerProvider(widget.serviceId).notifier)
          .load(),
    );
  }

  Future<void> _openSignatureScreen(TechnicalExecutionController ctrl) async {
    final saved = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: SignatureScreen(
                onSave: (pngBytes) async {
                  await ctrl.saveClientSignatureLocally(pngBytes: pngBytes);
                  if (!mounted) return;
                  setState(() => _signaturePreviewBytes = pngBytes);
                },
              ),
            ),
          );
        },
      ),
    );

    if (!mounted || saved != true) return;
    _showSnackBarPostFrame(
      const SnackBar(content: Text('Firma guardada correctamente')),
    );
  }

  _ClientSignatureMeta _readClientSignatureMeta(
    ServiceModel service,
    Map<String, dynamic> phaseSpecificData,
  ) {
    String asString(dynamic raw) => (raw ?? '').toString();

    Uint8List? decodeBytes(dynamic raw) {
      final value = asString(raw).trim();
      if (value.isEmpty) return null;
      try {
        return base64Decode(value);
      } catch (_) {
        return null;
      }
    }

    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    ServiceFileModel? latestRemoteSignature() {
      final candidates = service.files
          .where((f) => f.fileType.trim().toLowerCase() == 'client_signature')
          .toList(growable: false);
      if (candidates.isEmpty) return null;

      candidates.sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return candidates.first;
    }

    final raw = phaseSpecificData['clientSignature'];
    if (raw is Map) {
      final map = raw.cast<String, dynamic>();
      final fileId = asString(map['fileId']).trim();
      final fileUrl = asString(map['fileUrl']).trim();
      final signedAt = parseDate(map['signedAt']);
      final previewBytes = decodeBytes(map['localPreviewBase64']);
      final syncStatus = asString(map['syncStatus']).trim();
      final syncError = asString(map['syncError']).trim();
      final latestRemote = latestRemoteSignature();
      if ((syncStatus == 'pending_upload' ||
              syncStatus == 'uploading' ||
              syncStatus == 'local_saved') &&
          latestRemote != null &&
          signedAt != null &&
          latestRemote.createdAt != null &&
          !latestRemote.createdAt!.isBefore(
            signedAt.subtract(const Duration(seconds: 30)),
          )) {
        final remoteUrl = latestRemote.fileUrl.trim();
        if (remoteUrl.isNotEmpty) {
          return _ClientSignatureMeta(
            fileId: latestRemote.id.trim().isEmpty
                ? null
                : latestRemote.id.trim(),
            fileUrl: remoteUrl,
            signedAt: latestRemote.createdAt,
            syncStatus: 'completed',
          );
        }
      }
      if (fileUrl.isNotEmpty || fileId.isNotEmpty || previewBytes != null) {
        return _ClientSignatureMeta(
          fileId: fileId.isEmpty ? null : fileId,
          fileUrl: fileUrl.isEmpty ? null : fileUrl,
          signedAt: signedAt,
          previewBytes: previewBytes,
          syncStatus: syncStatus.isEmpty
              ? (fileUrl.isNotEmpty || fileId.isNotEmpty ? 'completed' : null)
              : syncStatus,
          syncError: syncError.isEmpty ? null : syncError,
        );
      }
    }

    final latest = latestRemoteSignature();
    if (latest == null) {
      return const _ClientSignatureMeta();
    }
    final url = latest.fileUrl.trim();
    if (url.isEmpty) return const _ClientSignatureMeta();
    return _ClientSignatureMeta(
      fileId: latest.id.trim().isEmpty ? null : latest.id.trim(),
      fileUrl: url,
      signedAt: latest.createdAt,
      syncStatus: 'completed',
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(
      technicalExecutionControllerProvider(widget.serviceId),
    );
    final ctrl = ref.read(
      technicalExecutionControllerProvider(widget.serviceId).notifier,
    );
    final user = ref.watch(authStateProvider).user;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (st.loading) {
      return Scaffold(
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        appBar: AppBar(
          leading: const OperationsBackButton(
            fallbackRoute: Routes.operacionesTecnico,
          ),
          title: const Text('Gestión Técnica'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final service = st.service;
    if (service == null) {
      return Scaffold(
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        appBar: AppBar(
          leading: const OperationsBackButton(
            fallbackRoute: Routes.operacionesTecnico,
          ),
          title: const Text('Gestión Técnica'),
        ),
        body: Center(
          child: Text(
            st.error?.trim().isNotEmpty == true
                ? st.error!.trim()
                : 'Servicio no disponible',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    final readOnly = _isReadOnly(service: service, user: user);
    final perms = OperationsPermissions(user: user, service: service);
    final canEditDocs = perms.canCritical;
    final signatureMeta = _readClientSignatureMeta(
      service,
      st.phaseSpecificData,
    );

    final techInfoUpdates = service.updates
        .where((u) {
          final t = u.type.trim().toLowerCase();
          if (t == 'tech_info') return true; // backward compatibility
          if (t != 'note') return false;
          return _parseTechInfoMessage(u.message) != null;
        })
        .toList(growable: false);
    final sortedTechInfo = [...techInfoUpdates];
    sortedTechInfo.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    final evidenceFiles = service.files
        .where((f) {
          final kind = f.fileType.trim().toLowerCase();
          return kind == 'evidence_final' || kind == 'video_evidence';
        })
        .toList(growable: false);
    final sortedEvidenceFiles = [...evidenceFiles];
    sortedEvidenceFiles.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    final pendingEvidence = st.pendingEvidence
        .where((p) => p.caption.trim().toLowerCase() != 'firma del cliente')
        .toList(growable: false);

    final currentState = _effectiveState(service);
    final firstName = _firstName(service.customerName);
    final currentPhaseLabel = phaseLabel(service.currentPhase);
    final statusOption = _serviceStatusOptionFor(currentState);
    final visibleChecklists = _visibleDynamicChecklists(st);

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: CompactAppBar(
        onBack: () {
          if (context.canPop()) {
            context.pop();
            return;
          }
          context.go(Routes.operacionesTecnico);
        },
        clientName: firstName,
        phaseLabel: currentPhaseLabel,
        statusLabel: statusOption.label,
        statusColor: statusOption.color,
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'ops-tech-checklist',
            onPressed: () => _openChecklistSheet(
              ctrl: ctrl,
              templates: visibleChecklists,
              readOnly: readOnly,
              busy: st.busy,
              currentState: currentState,
            ),
            icon: const Icon(Icons.checklist_rtl_outlined),
            label: const Text('Checklist'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'ops-tech-add-info',
            onPressed: readOnly ? null : () => _showAddInfoDialog(ctrl),
            icon: const Icon(Icons.add),
            label: const Text('Agregar'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'ops-tech-content',
            onPressed: readOnly ? null : () => _showContentDialog(ctrl),
            icon: const Icon(Icons.attach_file_outlined),
            label: const Text('Contenido'),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                children: [
                  if ((st.error ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          st.error!.trim(),
                          style: TextStyle(
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (st.busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(minHeight: 3),
                    ),

                  TechnicalSectionCard(
                    icon: Icons.flash_on_outlined,
                    title: 'ACCIONES',
                    child: ActionButtonGrid(
                      items: [
                        ActionButtonItem(
                          anchorKey: _callActionKey,
                          label: 'Llamar',
                          caption: _infoOrNull(service.customerPhone) == null
                              ? 'Sin numero'
                              : 'Confirmar antes',
                          icon: Icons.call_outlined,
                          onTap: () => _showCallDialog(service),
                          accentColor: const Color(0xFF0F766E),
                        ),
                        ActionButtonItem(
                          anchorKey: _locationActionKey,
                          label: 'Ubicacion',
                          caption: 'Accion directa',
                          icon: Icons.near_me_outlined,
                          onTap: () => _openLocation(service),
                          accentColor: const Color(0xFF2563EB),
                        ),
                        ActionButtonItem(
                          anchorKey: _orderActionKey,
                          label: 'Orden',
                          caption:
                              _infoOrNull(service.orderLabel) ?? 'Sin numero',
                          icon: Icons.receipt_long_outlined,
                          onTap: () => _showOrderDialog(service),
                          accentColor: const Color(0xFF7C3AED),
                        ),
                        ActionButtonItem(
                          anchorKey: _quoteActionKey,
                          label: 'Cotizacion',
                          caption: _money(service.quotedAmount).isEmpty
                              ? 'Ver detalle'
                              : _money(service.quotedAmount),
                          icon: Icons.request_quote_outlined,
                          onTap: () => _showCotizacionDialog(service),
                          accentColor: const Color(0xFFEA580C),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  TechnicalSectionCard(
                    icon: Icons.note_alt_outlined,
                    title: 'INFORMACIÓN',
                    child: sortedTechInfo.isEmpty
                        ? Builder(
                            builder: (context) {
                              final cs = Theme.of(context).colorScheme;
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Sin novedades / productos / notas aún.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: cs.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              );
                            },
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: sortedTechInfo.take(40).length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 7),
                            itemBuilder: (context, index) {
                              final u = sortedTechInfo
                                  .take(40)
                                  .elementAt(index);
                              final parsed =
                                  _parseTechInfoMessage(u.message) ??
                                  (kind: 'info', text: u.message.trim());
                              final kind = parsed.kind;
                              final label = _kindLabel(kind);
                              final accent = _kindAccentColor(cs, kind);
                              final highlighted =
                                  _isRecentlyAdded(u.createdAt) ||
                                  kind.trim().toLowerCase() == 'novedad';

                              return _TechInfoActivityCard(
                                key: ValueKey<String>('tech-info-${u.id}'),
                                icon: _kindIcon(kind),
                                title: label,
                                description: parsed.text,
                                author: _compactAuthor(u.changedBy),
                                timestamp: _compactRelativeTime(u.createdAt),
                                accentColor: accent,
                                highlighted: highlighted,
                                animateOnMount: highlighted,
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),

                  EvidenceGalleryCard(
                    title: 'CONTENIDO',
                    emptyLabel: 'Sin fotos/video aún',
                    uploadLabel: 'Subir',
                    icon: Icons.photo_library_outlined,
                    files: sortedEvidenceFiles,
                    pending: pendingEvidence,
                    onUpload: readOnly ? null : () => _showContentDialog(ctrl),
                    onPreview: _previewEvidence,
                  ),
                  const SizedBox(height: 12),

                  DynamicChecklistSummaryCard(
                    templates: visibleChecklists,
                    onOpen: () => _openChecklistSheet(
                      ctrl: ctrl,
                      templates: visibleChecklists,
                      readOnly: readOnly,
                      busy: st.busy,
                      currentState: currentState,
                    ),
                  ),
                  const SizedBox(height: 12),

                  ServiceClosureCard(
                    clientApproved: st.clientApproved,
                    onClientApprovedChanged: (readOnly || st.busy)
                        ? null
                        : ctrl.toggleClientApproved,
                    invoicePaid: _isInvoicePaid(service),
                    onInvoicePaidChanged: (readOnly || st.busy)
                        ? null
                        : (v) async {
                            await ctrl.setInvoicePaid(v);
                            if (!context.mounted) return;
                            _showSnackBarPostFrame(
                              SnackBar(
                                content: Text(
                                  v
                                      ? 'Factura marcada como pagada'
                                      : 'Factura marcada como pendiente',
                                ),
                              ),
                            );
                          },
                    onInvoicePressed: () => _onInvoicePressed(service),
                    onInvoiceEdit: canEditDocs
                        ? () => _openDocumentEditor(
                            service: service,
                            type: ServiceDocumentType.invoice,
                          )
                        : null,
                    onWarrantyPressed: () => _onWarrantyPressed(service),
                    onWarrantyEdit: canEditDocs
                        ? () => _openDocumentEditor(
                            service: service,
                            type: ServiceDocumentType.warranty,
                          )
                        : null,
                    onSignPressed: (readOnly || st.busy)
                        ? null
                        : () => _openSignatureScreen(ctrl),
                    signaturePreviewBytes:
                        _signaturePreviewBytes ?? signatureMeta.previewBytes,
                    signatureUrl: signatureMeta.fileUrl,
                    signatureSignedAt: signatureMeta.signedAt,
                    signatureSyncStatus: signatureMeta.syncStatus,
                    signatureSyncError: signatureMeta.syncError,
                    busy: st.busy,
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                scale: st.savingUpdate ? 0.96 : 1,
                child: FloatingStatusButton(
                  tooltip: 'Cambiar estado',
                  busy: st.savingUpdate,
                  onPressed: readOnly
                      ? null
                      : () => _showStatusSelector(
                          context: context,
                          ctrl: ctrl,
                          currentState: currentState,
                          readOnly: readOnly,
                          busy: st.busy,
                          visibleChecklists: visibleChecklists,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TechnicalServiceHeader extends StatelessWidget {
  final String clientName;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback onClientPressed;

  const TechnicalServiceHeader({
    super.key,
    required this.clientName,
    required this.statusLabel,
    required this.statusColor,
    required this.onClientPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF081225), Color(0xFF153B97), Color(0xFF2D7FF9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
          boxShadow: [
            BoxShadow(
              color: Color(0x2D0F172A),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -28,
              right: -12,
              child: Container(
                width: 124,
                height: 124,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              left: -36,
              bottom: -48,
              child: Container(
                width: 152,
                height: 152,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF60A5FA).withValues(alpha: 0.10),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: SizedBox(
                height: 84,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 12,
                      top: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            iconTheme: const IconThemeData(color: Colors.white),
                          ),
                          child: const OperationsBackButton(
                            fallbackRoute: Routes.operacionesTecnico,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: IconButton(
                          tooltip: 'Cliente',
                          onPressed: onClientPressed,
                          icon: const Icon(
                            Icons.person_outline,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(72, 10, 72, 10),
                      child: ClientStatusAppBar(
                        clientName: clientName,
                        statusLabel: statusLabel,
                        statusColor: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClientStatusAppBar extends StatelessWidget {
  final String clientName;
  final String statusLabel;
  final Color statusColor;

  const ClientStatusAppBar({
    super.key,
    required this.clientName,
    required this.statusLabel,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const statusTextColor = Color(0xFFFF6B6B);

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            clientName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              color: Colors.white,
            ),
          ),
        ),
        Container(
          width: 1.2,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: Colors.white.withValues(alpha: 0.40),
        ),
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: StatusIndicator(
              key: ValueKey<String>(statusLabel),
              label: statusLabel,
              color: statusTextColor,
              compact: true,
              textColor: statusTextColor,
              dotSize: 7,
              spacing: 6,
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showClientOverlay(BuildContext context, ServiceModel service) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => ClientInfoDialog(service: service),
  );
}

class ClientInfoDialog extends StatefulWidget {
  final ServiceModel service;

  const ClientInfoDialog({super.key, required this.service});

  @override
  State<ClientInfoDialog> createState() => _ClientInfoDialogState();
}

class _ClientInfoDialogState extends State<ClientInfoDialog> {
  double _scale = 0.96;
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _scale = 1;
        _opacity = 1;
      });
    });
  }

  String? _infoOrNull(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '—' || value.toLowerCase() == 'null') {
      return null;
    }
    return value;
  }

  String _humanizeValue(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return '—';
    return cleaned
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .map((part) {
          final lower = part.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  Future<void> _callClient() async {
    final phone = widget.service.customerPhone.trim();
    if (phone.isEmpty) return;
    final uri = Uri.tryParse('tel:$phone');
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openLocation() async {
    final info = buildServiceLocationInfo(
      addressOrText: widget.service.customerAddress,
    );
    if (!info.canOpenMaps || info.mapsUri == null) return;
    await launchUrl(info.mapsUri!, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final service = widget.service;

    final name = _infoOrNull(service.customerName) ?? 'Cliente';
    final phone = _infoOrNull(service.customerPhone) ?? 'Sin teléfono';
    final address = _infoOrNull(service.customerAddress) ?? 'Sin dirección';
    final order = _infoOrNull(service.orderLabel) ?? 'Sin orden';
    final serviceType = _infoOrNull(service.serviceType);
    final serviceLabel = serviceType == null
        ? 'Sin servicio definido'
        : _humanizeValue(serviceType);
    final canCall = service.customerPhone.trim().isNotEmpty;
    final locationInfo = buildServiceLocationInfo(
      addressOrText: service.customerAddress,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        opacity: _opacity,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          scale: _scale,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x260F172A),
                  blurRadius: 28,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.person_outline,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Información del cliente',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ClientInfoTile(
                    icon: Icons.call_outlined,
                    label: 'Teléfono',
                    value: phone,
                  ),
                  _ClientInfoDivider(color: cs.outlineVariant),
                  _ClientInfoTile(
                    icon: Icons.place_outlined,
                    label: 'Dirección',
                    value: address,
                  ),
                  _ClientInfoDivider(color: cs.outlineVariant),
                  _ClientInfoTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Orden',
                    value: order,
                  ),
                  _ClientInfoDivider(color: cs.outlineVariant),
                  _ClientInfoTile(
                    icon: Icons.build_outlined,
                    label: 'Servicio',
                    value: serviceLabel,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: canCall ? _callClient : null,
                          icon: const Icon(Icons.call_outlined),
                          label: const Text('Llamar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: locationInfo.canOpenMaps
                              ? _openLocation
                              : null,
                          icon: const Icon(Icons.near_me_outlined),
                          label: const Text('Ver ubicación'),
                        ),
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
  }
}

class _ClientInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ClientInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
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

class _ClientInfoDivider extends StatelessWidget {
  final Color color;

  const _ClientInfoDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 14,
      thickness: 0.8,
      color: color.withValues(alpha: 0.55),
    );
  }
}

class StatusIndicator extends StatelessWidget {
  final String label;
  final Color color;
  final bool compact;
  final Color? textColor;
  final double? dotSize;
  final double spacing;

  const StatusIndicator({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
    this.textColor,
    this.dotSize,
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedDotSize = dotSize ?? (compact ? 8.0 : 10.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: resolvedDotSize,
          height: resolvedDotSize,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: compact ? 8 : 10,
                spreadRadius: 0.5,
              ),
            ],
          ),
        ),
        SizedBox(width: spacing),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: compact ? 13.5 : 14,
            fontWeight: FontWeight.w700,
            color: textColor ?? theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TechInfoActivityCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String author;
  final String timestamp;
  final Color accentColor;
  final bool highlighted;
  final bool animateOnMount;

  const _TechInfoActivityCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.author,
    required this.timestamp,
    required this.accentColor,
    required this.highlighted,
    required this.animateOnMount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = accentColor;
    final baseBackground = highlighted
        ? Color.alphaBlend(accent.withValues(alpha: 0.08), cs.surface)
        : cs.surface;
    final titleColor = cs.onSurface;
    final bodyColor = cs.onSurface.withValues(alpha: 0.84);
    final metaColor = cs.onSurfaceVariant.withValues(alpha: 0.92);
    final timeColor = cs.onSurfaceVariant.withValues(alpha: 0.78);
    final shadowColor = highlighted
        ? accent.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.05);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: animateOnMount ? 0 : 1, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final clamped = value.clamp(0.0, 1.0);
        return Opacity(
          opacity: clamped,
          child: Transform.translate(
            offset: Offset(0, (1 - clamped) * -10),
            child: child,
          ),
        );
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: baseBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: highlighted ? 18 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: highlighted ? 4 : 3,
              height: 42,
              decoration: BoxDecoration(
                color: highlighted
                    ? accent
                    : cs.outlineVariant.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.12),
              ),
              child: Icon(icon, size: 17, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (theme.textTheme.labelLarge ??
                                theme.textTheme.titleSmall)
                            ?.copyWith(
                              color: titleColor,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                              letterSpacing: 0.1,
                            ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (theme.textTheme.bodySmall ??
                                theme.textTheme.bodyMedium)
                            ?.copyWith(
                              color: bodyColor,
                              fontWeight: FontWeight.w700,
                              height: 1.05,
                            ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (highlighted) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: metaColor,
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 54, maxWidth: 66),
              child: Text(
                timestamp,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: timeColor,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FloatingStatusButton extends StatelessWidget {
  final String tooltip;
  final bool busy;
  final VoidCallback? onPressed;

  const FloatingStatusButton({
    super.key,
    required this.tooltip,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: onPressed == null ? 0.55 : 1,
          child: Material(
            color: Colors.transparent,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Ink(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xE63B82F6), Color(0xE61D4ED8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x401D4ED8),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onPressed,
                    splashColor: Colors.white.withValues(alpha: 0.14),
                    highlightColor: Colors.white.withValues(alpha: 0.08),
                    child: Center(
                      child: busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.timeline_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatusSelectorModal extends StatelessWidget {
  final String current;
  final Set<String>? allowedStates;

  const StatusSelectorModal({
    super.key,
    required this.current,
    this.allowedStates,
  });

  static Future<String?> show(
    BuildContext context, {
    required String current,
    Set<String>? allowedStates,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          StatusSelectorModal(current: current, allowedStates: allowedStates),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = current.trim().toLowerCase();
    final currentOption = _serviceStatusOptionFor(normalized);
    final options = _serviceStatusOptions
        .where(
          (option) =>
              allowedStates == null || allowedStates!.contains(option.value),
        )
        .toList(growable: false);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Cambiar estado',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Actualiza el estado del servicio en un solo toque.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            StatusIndicator(
              label: currentOption.label,
              color: currentOption.color,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final selected = option.value == normalized;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: selected
                          ? option.color.withValues(alpha: 0.12)
                          : theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? option.color.withValues(alpha: 0.55)
                            : theme.colorScheme.outlineVariant.withValues(
                                alpha: 0.45,
                              ),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: option.color.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(option.icon, color: option.color),
                      ),
                      title: Text(
                        option.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        selected ? 'Estado actual' : 'Tocar para actualizar',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: selected
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: option.color,
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        unawaited(HapticFeedback.selectionClick());
                        Navigator.pop(context, option.value);
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

class _ServiceStatusOption {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _ServiceStatusOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
}

const _serviceStatusOptions = <_ServiceStatusOption>[
  _ServiceStatusOption(
    value: 'pendiente',
    label: 'Pendiente',
    icon: Icons.schedule_rounded,
    color: Color(0xFF6B7280),
  ),
  _ServiceStatusOption(
    value: 'en_camino',
    label: 'En camino',
    icon: Icons.directions_car_outlined,
    color: Color(0xFFF97316),
  ),
  _ServiceStatusOption(
    value: 'en_proceso',
    label: 'En proceso',
    icon: Icons.play_circle_outline_rounded,
    color: Color(0xFF2563EB),
  ),
  _ServiceStatusOption(
    value: 'finalizada',
    label: 'Finalizado',
    icon: Icons.verified_outlined,
    color: Color(0xFF16A34A),
  ),
  _ServiceStatusOption(
    value: 'cancelada',
    label: 'Cancelado',
    icon: Icons.cancel_outlined,
    color: Color(0xFFDC2626),
  ),
];

_ServiceStatusOption _serviceStatusOptionFor(String raw) {
  final normalized = raw.trim().toLowerCase();

  switch (normalized) {
    case 'en_camino':
      return _serviceStatusOptions[1];
    case 'en_proceso':
    case 'in_progress':
      return _serviceStatusOptions[2];
    case 'finalizada':
    case 'finalized':
      return _serviceStatusOptions[3];
    case 'cancelada':
    case 'cancelled':
      return _serviceStatusOptions[4];
    case 'pendiente':
    case 'pending':
    case 'confirmada':
    case 'confirmed':
    case 'asignada':
    case 'assigned':
    case 'reagendada':
    case 'rescheduled':
    case 'cerrada':
      return _ServiceStatusOption(
        value: normalized.isEmpty ? 'pendiente' : normalized,
        label: StatusPickerSheet.label(
          normalized.isEmpty ? 'pendiente' : normalized,
        ),
        icon: StatusPickerSheet.icon(
          normalized.isEmpty ? 'pendiente' : normalized,
        ),
        color: const Color(0xFF6B7280),
      );
    default:
      return _ServiceStatusOption(
        value: normalized,
        label: normalized.isEmpty ? 'Sin estado' : StatusPickerSheet.label(raw),
        icon: StatusPickerSheet.icon(raw),
        color: const Color(0xFF6B7280),
      );
  }
}

class _VideoPreviewDialog extends StatefulWidget {
  final String url;

  const _VideoPreviewDialog({required this.url});

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  late final VideoPlayerController _controller;
  late final Future<void> _init;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _init = _controller.initialize().then((_) async {
      _controller.setLooping(false);
      try {
        await _controller.seekTo(const Duration(milliseconds: 1));
      } catch (_) {
        // ignore
      }
      try {
        await _controller.play();
      } catch (_) {
        // ignore
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog.fullscreen(
      backgroundColor: cs.scrim,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: FutureBuilder<void>(
                future: _init,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snap.hasError) {
                    final uri = Uri.tryParse(widget.url);
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No se pudo reproducir el video',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${snap.error}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 14),
                            if (uri != null)
                              FilledButton.tonalIcon(
                                onPressed: () => launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                ),
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('Abrir externo'),
                              ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (!_controller.value.isInitialized) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No se pudo reproducir el video',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: cs.onSurface),
                        ),
                      ),
                    );
                  }

                  return Center(
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) {
                        final aspect = value.aspectRatio;
                        return AspectRatio(
                          aspectRatio: aspect > 0 ? aspect : 16 / 9,
                          child: Stack(
                            children: [
                              Positioned.fill(child: VideoPlayer(_controller)),
                              Positioned.fill(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      if (_controller.value.isPlaying) {
                                        _controller.pause();
                                      } else {
                                        _controller.play();
                                      }
                                    },
                                    child: Center(
                                      child: Icon(
                                        value.isPlaying
                                            ? Icons.pause_circle_outline
                                            : Icons.play_circle_outline,
                                        size: 76,
                                        color: cs.onSurface.withValues(
                                          alpha: 0.88,
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
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: VideoProgressIndicator(
                                    _controller,
                                    allowScrubbing: true,
                                    colors: VideoProgressColors(
                                      playedColor: cs.primary,
                                      bufferedColor: cs.primary.withValues(
                                        alpha: 0.35,
                                      ),
                                      backgroundColor: cs.onSurface.withValues(
                                        alpha: 0.20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'Cerrar',
                onPressed: () async {
                  try {
                    await _controller.pause();
                  } catch (_) {
                    // ignore
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.close),
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientSignatureMeta {
  final String? fileId;
  final String? fileUrl;
  final DateTime? signedAt;
  final Uint8List? previewBytes;
  final String? syncStatus;
  final String? syncError;

  const _ClientSignatureMeta({
    this.fileId,
    this.fileUrl,
    this.signedAt,
    this.previewBytes,
    this.syncStatus,
    this.syncError,
  });
}
