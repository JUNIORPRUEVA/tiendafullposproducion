import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/routes.dart';
import '../../../core/utils/safe_url_launcher.dart';
import '../../../core/widgets/app_drawer.dart';
import '../application/operations_controller.dart';
import '../data/operations_repository.dart';
import '../operations_models.dart';
import '../presentation/service_location_helpers.dart';
import 'presentation/tech_operations_filters.dart';
import 'technical_visit_models.dart';
import 'widgets/service_order_detail_components.dart';

class _ServiceDetailBundle {
  final ServiceModel service;
  final TechnicalVisitModel? visit;

  const _ServiceDetailBundle({required this.service, required this.visit});
}

final _serviceDetailProvider =
    FutureProvider.family<_ServiceDetailBundle, String>((ref, serviceId) async {
      final repo = ref.read(operationsRepositoryProvider);
      final serviceFuture = ref.watch(serviceProvider(serviceId).future);
      final cacheScope = (ref.read(authStateProvider).user?.id ?? '').trim();
      final visitFuture = () async {
        if (cacheScope.isEmpty) {
          return repo.getTechnicalVisitByOrder(serviceId);
        }

        final cached = await repo.getCachedTechnicalVisitByOrder(
          cacheScope: cacheScope,
          orderId: serviceId,
        );
        if (cached != null) {
          unawaited(
            repo.getTechnicalVisitByOrderAndCache(
              cacheScope: cacheScope,
              orderId: serviceId,
              silent: true,
            ),
          );
          return cached;
        }

        return repo.getTechnicalVisitByOrderAndCache(
          cacheScope: cacheScope,
          orderId: serviceId,
          silent: true,
        );
      }();
      final results = await Future.wait<dynamic>([serviceFuture, visitFuture]);
      return _ServiceDetailBundle(
        service: results[0] as ServiceModel,
        visit: results[1] as TechnicalVisitModel?,
      );
    });

final _serviceHistoryProvider =
    FutureProvider.family<List<ServiceModel>, ServiceModel>((
      ref,
      service,
    ) async {
      final repo = ref.read(operationsRepositoryProvider);
      if (service.customerId.trim().isEmpty) return const [];

      final page = await repo.listServices(
        customerId: service.customerId.trim(),
        page: 1,
        pageSize: 30,
      );

      final items = page.items
          .where((s) => s.id != service.id)
          .toList(growable: false);

      int rank(ServiceModel s) {
        final dt = s.completedAt ?? s.scheduledStart ?? s.scheduledEnd;
        return dt?.millisecondsSinceEpoch ?? 0;
      }

      items.sort((a, b) => rank(b).compareTo(rank(a)));
      return items.take(10).toList(growable: false);
    });

class ServiceOrderDetailScreen extends ConsumerWidget {
  final String serviceId;

  const ServiceOrderDetailScreen({super.key, required this.serviceId});

  String _evidenceIdentity(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      final queryIndex = trimmed.indexOf('?');
      return (queryIndex >= 0 ? trimmed.substring(0, queryIndex) : trimmed)
          .toLowerCase();
    }
    return uri.replace(query: '', fragment: '').toString().toLowerCase();
  }

  String _inferImageMimeType(String url) {
    final lower = _evidenceIdentity(url);
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  ServiceFileModel _visitEvidenceFile({
    required String id,
    required String url,
    required String fileType,
    required String mimeType,
    required String? caption,
    required DateTime? createdAt,
  }) {
    return ServiceFileModel(
      id: id,
      fileUrl: url,
      fileType: fileType,
      mimeType: mimeType,
      caption: caption,
      createdAt: createdAt,
    );
  }

  List<ServiceFileModel> _mergeEvidenceFiles(
    ServiceModel service,
    TechnicalVisitModel? visit,
  ) {
    final merged = <ServiceFileModel>[...service.files];
    final identities = service.files
        .map((file) => _evidenceIdentity(file.fileUrl))
        .where((value) => value.isNotEmpty)
        .toSet();

    void addVisitUrl({
      required String url,
      required String fileType,
      required String mimeType,
      required int index,
    }) {
      final trimmed = url.trim();
      final identity = _evidenceIdentity(trimmed);
      if (trimmed.isEmpty ||
          identity.isEmpty ||
          identities.contains(identity)) {
        return;
      }
      identities.add(identity);
      merged.add(
        _visitEvidenceFile(
          id: '${visit?.id ?? service.id}-$fileType-$index',
          url: trimmed,
          fileType: fileType,
          mimeType: mimeType,
          caption: visit?.reportDescription.trim().isEmpty ?? true
              ? null
              : visit!.reportDescription.trim(),
          createdAt: visit?.updatedAt ?? visit?.visitDate ?? visit?.createdAt,
        ),
      );
    }

    final visitPhotos = visit?.photos ?? const <String>[];
    for (var i = 0; i < visitPhotos.length; i++) {
      addVisitUrl(
        url: visitPhotos[i],
        fileType: 'reference_photo',
        mimeType: _inferImageMimeType(visitPhotos[i]),
        index: i,
      );
    }

    final visitVideos = visit?.videos ?? const <String>[];
    for (var i = 0; i < visitVideos.length; i++) {
      addVisitUrl(
        url: visitVideos[i],
        fileType: 'video_evidence',
        mimeType: 'video/mp4',
        index: i,
      );
    }

    merged.sort((a, b) {
      final left = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final right = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return right.compareTo(left);
    });
    return merged;
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '';
    final v = dt.toLocal();
    final d = v.day.toString().padLeft(2, '0');
    final m = v.month.toString().padLeft(2, '0');
    final y = v.year.toString();
    return '$d/$m/$y';
  }

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '';
    final v = dt.toLocal();
    final d = v.day.toString().padLeft(2, '0');
    final m = v.month.toString().padLeft(2, '0');
    final y = v.year.toString();
    final hour = v.hour == 0 ? 12 : (v.hour > 12 ? v.hour - 12 : v.hour);
    final minute = v.minute.toString().padLeft(2, '0');
    final suffix = v.hour >= 12 ? 'PM' : 'AM';
    return '$d/$m/$y · $hour:$minute $suffix';
  }

  String _money(double? v) {
    if (v == null) return '';
    final safe = v.isNaN ? 0.0 : v;
    return 'RD\$${safe.toStringAsFixed(2)}';
  }

  String _clean(String? value) => (value ?? '').trim();

  bool _hasText(String? value) => _clean(value).isNotEmpty;

  ({Color background, Color foreground, IconData icon}) _statusTheme(
    ServiceModel service,
  ) {
    final status = techOrderStatusFrom(service);
    return (
      background: techOrderStatusColor(status).withValues(alpha: 0.14),
      foreground: techOrderStatusColor(status),
      icon: techOrderStatusIcon(status),
    );
  }

  ({Color background, Color foreground, IconData icon}) _paymentTheme(
    String label,
  ) {
    switch (label.trim().toLowerCase()) {
      case 'pagado':
        return (
          background: const Color(0xFFEAF8EF),
          foreground: const Color(0xFF15803D),
          icon: Icons.check_circle_rounded,
        );
      case 'abono recibido':
        return (
          background: const Color(0xFFEAF2FF),
          foreground: const Color(0xFF0B6BDE),
          icon: Icons.account_balance_wallet_rounded,
        );
      case 'pendiente':
        return (
          background: const Color(0xFFFFF3E6),
          foreground: const Color(0xFFC77800),
          icon: Icons.schedule_rounded,
        );
      default:
        return (
          background: const Color(0xFFF1F5F9),
          foreground: const Color(0xFF64748B),
          icon: Icons.help_outline_rounded,
        );
    }
  }

  ({double? total, double? deposit, double? balance, String status})
  _paymentInfo(ServiceModel service) {
    final total = service.finalCost ?? service.quotedAmount;
    final deposit = service.depositAmount;
    if (total == null) {
      return (total: null, deposit: deposit, balance: null, status: 'N/D');
    }

    final safeTotal = total.isNaN ? 0.0 : total;
    final safeDeposit = (deposit ?? 0.0).isNaN ? 0.0 : (deposit ?? 0.0);
    final balance = safeTotal - safeDeposit;

    if (safeTotal <= 0) {
      return (total: total, deposit: deposit, balance: null, status: 'N/D');
    }
    if (safeDeposit <= 0) {
      return (
        total: total,
        deposit: deposit,
        balance: safeTotal,
        status: 'Pendiente',
      );
    }
    if (safeDeposit >= safeTotal) {
      return (total: total, deposit: deposit, balance: 0.0, status: 'Pagado');
    }

    return (
      total: total,
      deposit: deposit,
      balance: balance,
      status: 'Abono recibido',
    );
  }

  ({String address, String reference, String gpsText, String mapsText})
  _parseLocationSnapshot(String raw) {
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);

    String? address;
    final references = <String>[];
    String? gps;
    String? maps;

    bool isUrl(String v) =>
        RegExp(r'https?://', caseSensitive: false).hasMatch(v);

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.startsWith('gps:')) {
        gps = line.substring(4).trim();
        continue;
      }
      if (lower.startsWith('maps:')) {
        maps = line.substring(5).trim();
        continue;
      }
      if (isUrl(line)) {
        maps ??= line;
        continue;
      }

      address ??= line;
      if (address != line) {
        references.add(line);
      }
    }

    address ??= '—';
    return (
      address: address,
      reference: references.isEmpty ? '—' : references.join(' · '),
      gpsText: (gps ?? '').trim().isEmpty ? '—' : gps!.trim(),
      mapsText: (maps ?? '').trim().isEmpty ? '—' : maps!.trim(),
    );
  }

  bool _isLikelyImage(ServiceFileModel file) {
    final ft = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final url = file.fileUrl.trim().toLowerCase();
    if (ft.contains('image') || ft.contains('image/')) return true;
    return url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.webp');
  }

  bool _isLikelyVideo(ServiceFileModel file) {
    final ft = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final url = file.fileUrl.trim().toLowerCase();
    if (ft.contains('video') || ft.contains('video/')) return true;
    return url.endsWith('.mp4');
  }

  Future<void> _previewEvidence(
    BuildContext context,
    ServiceFileModel file,
  ) async {
    final url = file.fileUrl.trim();
    if (url.isEmpty) return;

    final ft = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final isVideo = ft.contains('video') || url.toLowerCase().endsWith('.mp4');

    if (isVideo) {
      await showDialog<void>(
        context: context,
        builder: (_) => _VideoPreviewDialog(url: url),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                url,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
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

  List<Widget> _buildClientSection(ServiceModel service) {
    final rows = <Widget>[];
    final customerName = _clean(service.customerName);
    final phone = _clean(service.customerPhone);

    if (customerName.isNotEmpty) {
      rows.add(
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.person_rounded, color: Color(0xFF0B6BDE)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cliente',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64758B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customerName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF10233F),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (phone.isNotEmpty) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(
        InfoRow(
          label: 'Teléfono',
          value: phone,
          icon: Icons.call_outlined,
          emphasize: true,
        ),
      );
    }

    return rows;
  }

  List<Widget> _buildOrderSection(ServiceModel service, List<String> assigned) {
    final rawStatus = effectiveServiceStatusLabel(service);
    final scheduled = _fmtDateTime(
      service.scheduledStart ?? service.scheduledEnd,
    );
    final phase = techOrderPhaseFrom(service);
    final statusTheme = _statusTheme(service);
    final rows = <Widget>[
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (phase != null)
            StatusBadge(
              label: techOrderPhaseLabel(phase),
              background: techOrderPhaseColor(phase).withValues(alpha: 0.14),
              foreground: techOrderPhaseColor(phase),
              icon: techOrderPhaseIcon(phase),
            ),
          if (rawStatus.isNotEmpty)
            StatusBadge(
              label: rawStatus,
              background: statusTheme.background,
              foreground: statusTheme.foreground,
              icon: statusTheme.icon,
            ),
        ],
      ),
    ];

    final info = <Widget>[];
    if (_hasText(service.serviceType)) {
      info.add(
        InfoRow(
          label: 'Tipo',
          value: _clean(service.serviceType),
          icon: Icons.miscellaneous_services_rounded,
        ),
      );
    }
    if (_hasText(service.orderLabel)) {
      if (info.isNotEmpty) info.add(const SizedBox(height: 8));
      info.add(
        InfoRow(
          label: 'Orden',
          value: _clean(service.orderLabel),
          icon: Icons.confirmation_number_outlined,
          emphasize: true,
        ),
      );
    }
    if (scheduled.isNotEmpty) {
      if (info.isNotEmpty) info.add(const SizedBox(height: 8));
      info.add(
        InfoRow(
          label: 'Fecha',
          value: scheduled,
          icon: Icons.calendar_month_rounded,
        ),
      );
    }
    if (assigned.isNotEmpty) {
      if (info.isNotEmpty) info.add(const SizedBox(height: 8));
      info.add(
        InfoRow(
          label: 'Técnico',
          value: assigned.join(', '),
          icon: Icons.engineering_outlined,
        ),
      );
    }

    if (info.isNotEmpty) {
      rows
        ..add(const SizedBox(height: 12))
        ..addAll(info);
    }

    return rows;
  }

  List<Widget> _buildLocationSection(
    String addressLabel,
    ({String address, String reference, String gpsText, String mapsText})
    snapshot,
  ) {
    final rows = <Widget>[];
    if (_hasText(addressLabel) && addressLabel != '—') {
      rows.add(
        InfoRow(
          label: 'Dirección',
          value: addressLabel,
          icon: Icons.place_outlined,
          multiline: true,
          emphasize: true,
        ),
      );
    }
    if (_hasText(snapshot.reference) && snapshot.reference != '—') {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(
        InfoRow(
          label: 'Referencia',
          value: snapshot.reference,
          icon: Icons.pin_drop_outlined,
          multiline: true,
        ),
      );
    }
    if (_hasText(snapshot.gpsText) && snapshot.gpsText != '—') {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(
        InfoRow(
          label: 'GPS',
          value: snapshot.gpsText,
          icon: Icons.my_location_rounded,
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final asyncService = ref.watch(_serviceDetailProvider(serviceId));

    return asyncService.when(
      loading: () {
        return Scaffold(
          drawer: buildAdaptiveDrawer(context, currentUser: user),
          appBar: AppBar(
            title: const Text('Orden de servicio'),
            leading: IconButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                  return;
                }
                context.go(Routes.operacionesTecnico);
              },
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: const Center(child: CircularProgressIndicator()),
        );
      },
      error: (e, _) {
        final msg = e is ApiException ? e.message : e.toString();
        return Scaffold(
          drawer: buildAdaptiveDrawer(context, currentUser: user),
          appBar: AppBar(
            title: const Text('Orden de servicio'),
            leading: IconButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                  return;
                }
                context.go(Routes.operacionesTecnico);
              },
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(msg, textAlign: TextAlign.center),
            ),
          ),
        );
      },
      data: (bundle) {
        final service = bundle.service;
        final mergedFiles = _mergeEvidenceFiles(service, bundle.visit);
        final assigned = service.assignments
            .map((a) => a.userName.trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);

        final location = buildServiceLocationInfo(
          addressOrText: service.customerAddress,
        );

        final snapshot = _parseLocationSnapshot(service.customerAddress);
        final pay = _paymentInfo(service);
        final isLevantamiento =
            effectiveServicePhaseKey(service) == 'levantamiento';

        final phone = service.customerPhone.trim();
        final canOpenQuote = phone.isNotEmpty;

        final addressLabel = snapshot.address;

        final historyAsync = ref.watch(_serviceHistoryProvider(service));

        final images = mergedFiles
            .where(_isLikelyImage)
            .toList(growable: false);
        final videos = mergedFiles
            .where(_isLikelyVideo)
            .toList(growable: false);
        final otherFiles = mergedFiles
            .where((f) => !(_isLikelyImage(f) || _isLikelyVideo(f)))
            .toList(growable: false);

        Future<void> openMaps() async {
          final uri = location.mapsUri;
          if (uri == null) return;
          await safeOpenUrl(context, uri, copiedMessage: 'Link copiado');
        }

        final locationSection = _buildLocationSection(addressLabel, snapshot);
        if (location.canOpenMaps) {
          locationSection
            ..addIf(locationSection.isNotEmpty, const SizedBox(height: 12))
            ..add(
              ActionButton(
                label: 'Abrir en Maps',
                icon: Icons.map_outlined,
                tonal: true,
                onPressed: openMaps,
              ),
            );
        }

        final paymentTheme = _paymentTheme(pay.status);
        final clientSection = _buildClientSection(service);
        final orderSection = _buildOrderSection(service, assigned);

        return Scaffold(
          backgroundColor: const Color(0xFFF7FBFE),
          drawer: buildAdaptiveDrawer(context, currentUser: user),
          appBar: AppBar(
            title: const Text('Orden de servicio'),
            elevation: 0,
            backgroundColor: Colors.transparent,
            leading: IconButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                  return;
                }
                context.go(Routes.operacionesTecnico);
              },
              icon: const Icon(Icons.arrow_back),
            ),
            actions: [
              IconButton(
                tooltip: 'Gestionar servicio',
                onPressed: () {
                  final id = service.id.trim();
                  if (id.isEmpty) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    context.push(Routes.operacionesTecnicoDetail(id));
                  });
                },
                icon: const Icon(Icons.build_outlined),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_serviceDetailProvider(serviceId));
              await ref.read(_serviceDetailProvider(serviceId).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                SectionCard(
                  icon: Icons.flash_on_outlined,
                  title: 'Acciones rápidas',
                  child: Column(
                    children: [
                      ActionButton(
                        label: 'Gestionar servicio',
                        icon: Icons.build_outlined,
                        onPressed: () {
                          final id = service.id.trim();
                          if (id.isEmpty) return;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted) return;
                            context.push(Routes.operacionesTecnicoDetail(id));
                          });
                        },
                      ),
                      if (_hasText(service.customerPhone) ||
                          location.canOpenMaps) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (_hasText(service.customerPhone))
                              Expanded(
                                child: ActionButton(
                                  label: 'Llamar',
                                  icon: Icons.call_outlined,
                                  tonal: true,
                                  onPressed: () async {
                                    final phoneValue = _clean(
                                      service.customerPhone,
                                    );
                                    final uri = Uri(
                                      scheme: 'tel',
                                      path: phoneValue,
                                    );
                                    await safeOpenUrl(
                                      context,
                                      uri,
                                      copiedMessage: 'Link copiado',
                                    );
                                  },
                                ),
                              ),
                            if (_hasText(service.customerPhone) &&
                                location.canOpenMaps)
                              const SizedBox(width: 8),
                            if (location.canOpenMaps)
                              Expanded(
                                child: ActionButton(
                                  label: 'Maps',
                                  icon: Icons.map_outlined,
                                  tonal: true,
                                  onPressed: openMaps,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (clientSection.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.person_outline,
                    title: 'Información del cliente',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: clientSection,
                    ),
                  ),
                ],
                if (orderSection.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.assignment_outlined,
                    title: 'Información de la orden',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: orderSection,
                    ),
                  ),
                ],
                if (locationSection.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.place_outlined,
                    title: 'Ubicación y referencias',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: locationSection,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SectionCard(
                  icon: Icons.assignment_turned_in_outlined,
                  title: 'Levantamiento',
                  child: bundle.visit == null
                      ? const EmptyStateWidget(
                          icon: Icons.assignment_late_outlined,
                          title: 'Sin datos de levantamiento aún',
                          message:
                              'Todavía no se ha guardado un levantamiento para esta orden.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InfoRow(
                              label: 'Fecha',
                              value: _fmtDateTime(
                                bundle.visit!.updatedAt ??
                                    bundle.visit!.visitDate ??
                                    bundle.visit!.createdAt,
                              ),
                              icon: Icons.event_outlined,
                            ),
                            if (_hasText(bundle.visit!.reportDescription)) ...[
                              const SizedBox(height: 10),
                              InfoRow(
                                label: 'Reporte',
                                value: _clean(bundle.visit!.reportDescription),
                                icon: Icons.notes_outlined,
                                multiline: true,
                                emphasize: true,
                              ),
                            ],
                            if (_hasText(bundle.visit!.installationNotes)) ...[
                              const SizedBox(height: 10),
                              InfoRow(
                                label: 'Observaciones',
                                value: _clean(bundle.visit!.installationNotes),
                                icon: Icons.subject_outlined,
                                multiline: true,
                              ),
                            ],
                          ],
                        ),
                ),
                if (!isLevantamiento) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.receipt_long_outlined,
                    title: 'Información de cotización',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            StatusBadge(
                              label: pay.status,
                              background: paymentTheme.background,
                              foreground: paymentTheme.foreground,
                              icon: paymentTheme.icon,
                            ),
                          ],
                        ),
                        if (_money(pay.total).isNotEmpty) ...[
                          const SizedBox(height: 12),
                          InfoRow(
                            label: 'Total',
                            value: _money(pay.total),
                            icon: Icons.payments_outlined,
                            emphasize: true,
                          ),
                        ],
                        if (_money(pay.balance).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          InfoRow(
                            label: 'Saldo',
                            value: _money(pay.balance),
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                        ],
                        if (_money(pay.deposit).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          InfoRow(
                            label: 'Depósito',
                            value: _money(pay.deposit),
                            icon: Icons.savings_outlined,
                          ),
                        ],
                        if (_money(service.quotedAmount).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          InfoRow(
                            label: 'Cotizado',
                            value: _money(service.quotedAmount),
                            icon: Icons.request_quote_outlined,
                          ),
                        ],
                        if (_money(service.finalCost).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          InfoRow(
                            label: 'Costo final',
                            value: _money(service.finalCost),
                            icon: Icons.price_check_outlined,
                          ),
                        ],
                        if (canOpenQuote) ...[
                          const SizedBox(height: 12),
                          ActionButton(
                            label: 'Ver cotización',
                            icon: Icons.open_in_new_outlined,
                            tonal: true,
                            onPressed: () {
                              final uri = Uri(
                                path: Routes.cotizacionesHistorial,
                                queryParameters: {
                                  'customerPhone': phone,
                                  'pick': '0',
                                },
                              );
                              context.go(uri.toString());
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SectionCard(
                  icon: Icons.history_outlined,
                  title: 'Historial de servicios',
                  child: historyAsync.when(
                    loading: () => const _InlineLoading(),
                    error: (e, _) {
                      return EmptyStateWidget(
                        icon: Icons.error_outline_rounded,
                        title: 'No fue posible cargar el historial',
                        message: e is ApiException ? e.message : e.toString(),
                      );
                    },
                    data: (items) {
                      if (items.isEmpty) {
                        return const EmptyStateWidget(
                          icon: Icons.history_toggle_off_rounded,
                          title: 'Sin historial anterior',
                          message:
                              'Este cliente no tiene otros servicios registrados.',
                        );
                      }
                      return Column(
                        children: [
                          for (final s in items) ...[
                            _HistoryTile(service: s, fmtDate: _fmtDate),
                            if (s != items.last) const SizedBox(height: 10),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  icon: Icons.attach_file_outlined,
                  title: 'Documentos adjuntos',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AttachmentsGrid(
                        title: 'Fotos',
                        files: images,
                        onPreview: (f) => _previewEvidence(context, f),
                      ),
                      const SizedBox(height: 12),
                      _AttachmentsGrid(
                        title: 'Videos',
                        files: videos,
                        onPreview: (f) => _previewEvidence(context, f),
                      ),
                      const SizedBox(height: 12),
                      _AttachmentsGrid(
                        title: 'Archivos',
                        files: otherFiles,
                        onPreview: (f) => _previewEvidence(context, f),
                      ),
                    ],
                  ),
                ),
                if (_hasText(service.title) ||
                    _hasText(service.description)) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    icon: Icons.subject_outlined,
                    title: 'Descripción del servicio',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_hasText(service.title))
                          InfoRow(
                            label: 'Trabajo',
                            value: _clean(service.title),
                            icon: Icons.assignment_turned_in_outlined,
                            multiline: true,
                            emphasize: true,
                          ),
                        if (_hasText(service.title) &&
                            _hasText(service.description))
                          const SizedBox(height: 10),
                        if (_hasText(service.description))
                          InfoRow(
                            label: 'Notas',
                            value: _clean(service.description),
                            icon: Icons.notes_rounded,
                            multiline: true,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

extension _WidgetListX on List<Widget> {
  void addIf(bool condition, Widget widget) {
    if (condition) add(widget);
  }
}

class _InlineLoading extends StatelessWidget {
  const _InlineLoading();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text('Cargando…', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final ServiceModel service;
  final String Function(DateTime? dt) fmtDate;

  const _HistoryTile({required this.service, required this.fmtDate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusTheme = _historyStatusTheme(effectiveServiceStatusKey(service));
    final statusLabel = effectiveServiceStatusLabel(service);

    final dt =
        service.completedAt ?? service.scheduledStart ?? service.scheduledEnd;
    final dateLabel = fmtDate(dt);

    final title = service.title.trim().isEmpty
        ? (service.description.trim().isEmpty
              ? 'Servicio'
              : service.description.trim())
        : service.title.trim();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EAF2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: statusTheme.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.assignment_outlined,
              size: 18,
              color: statusTheme.foreground,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF10233F),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (dateLabel.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_month_rounded,
                            size: 13,
                            color: Color(0xFF64758B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dateLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF64758B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    StatusBadge(
                      label: statusLabel,
                      background: statusTheme.background,
                      foreground: statusTheme.foreground,
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
}

({Color background, Color foreground}) _historyStatusTheme(String rawStatus) {
  final status = normalizeOperationsKey(rawStatus);
  if (status == 'finalizada' || status == 'cerrada') {
    return (
      background: const Color(0xFFEAF8EF),
      foreground: const Color(0xFF15803D),
    );
  }
  if (status == 'en_proceso' || status == 'en_camino') {
    return (
      background: const Color(0xFFEAF2FF),
      foreground: const Color(0xFF0B6BDE),
    );
  }
  if (status == 'cancelada') {
    return (
      background: const Color(0xFFFFF1F2),
      foreground: const Color(0xFFB42318),
    );
  }
  return (
    background: const Color(0xFFFFF3E6),
    foreground: const Color(0xFFC77800),
  );
}

class _AttachmentsGrid extends StatelessWidget {
  final String title;
  final List<ServiceFileModel> files;
  final void Function(ServiceFileModel file) onPreview;

  const _AttachmentsGrid({
    required this.title,
    required this.files,
    required this.onPreview,
  });

  bool _isHttpUrl(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (files.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: const Color(0xFF10233F),
            ),
          ),
          const SizedBox(height: 8),
          EmptyStateWidget(
            icon: title == 'Videos'
                ? Icons.videocam_outlined
                : (title == 'Fotos'
                      ? Icons.image_outlined
                      : Icons.attach_file_outlined),
            title: 'Sin $title',
            message: 'Aun no hay elementos adjuntos en esta sección.',
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final crossAxisCount = w >= 900
            ? 8
            : (w >= 700 ? 6 : (w >= 520 ? 5 : (w >= 420 ? 4 : 3)));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF10233F),
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1,
              ),
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                final url = file.fileUrl.trim();

                return InkWell(
                  onTap: () => onPreview(file),
                  borderRadius: BorderRadius.circular(10),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE3EAF2)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_isHttpUrl(url))
                            Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) {
                                return Center(
                                  child: Icon(
                                    Icons.insert_drive_file_outlined,
                                    color: const Color(0xFF64758B),
                                  ),
                                );
                              },
                            )
                          else
                            Center(
                              child: Icon(
                                Icons.insert_drive_file_outlined,
                                color: const Color(0xFF64758B),
                              ),
                            ),
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Icon(
                                title == 'Videos'
                                    ? Icons.play_circle_outline_rounded
                                    : (title == 'Fotos'
                                          ? Icons.image_outlined
                                          : Icons.attach_file_outlined),
                                size: 14,
                                color: const Color(0xFF34495E),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 6,
                            bottom: 6,
                            right: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Text(
                                  file.caption?.trim().isNotEmpty == true
                                      ? file.caption!.trim()
                                      : title.substring(
                                          0,
                                          title.length > 1
                                              ? title.length - 1
                                              : title.length,
                                        ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: const Color(0xFF10233F),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
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
      await _controller.pause();
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

    return Dialog(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: cs.surface,
                child: FutureBuilder<void>(
                  future: _init,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!_controller.value.isInitialized) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No se pudo reproducir el video',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      );
                    }

                    final aspect = _controller.value.aspectRatio;
                    return Center(
                      child: AspectRatio(
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
                                    setState(() {});
                                  },
                                  child: Center(
                                    child: Icon(
                                      _controller.value.isPlaying
                                          ? Icons.pause_circle_outline
                                          : Icons.play_circle_outline,
                                      size: 68,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 8,
                              right: 8,
                              bottom: 8,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
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
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
