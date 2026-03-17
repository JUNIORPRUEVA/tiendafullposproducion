import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/routes.dart';
import '../../../core/widgets/app_drawer.dart';
import '../application/operations_controller.dart';
import '../data/operations_repository.dart';
import '../operations_models.dart';
import '../presentation/service_location_helpers.dart';
import 'widgets/technical_execution_cards.dart';

final _serviceDetailProvider = FutureProvider.family<ServiceModel, String>((
  ref,
  serviceId,
) async {
  return ref.read(operationsControllerProvider.notifier).getOne(serviceId);
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

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '—';
    final v = dt.toLocal();
    final d = v.day.toString().padLeft(2, '0');
    final m = v.month.toString().padLeft(2, '0');
    final y = v.year.toString();
    return '$d/$m/$y';
  }

  String _money(double? v) {
    if (v == null) return '—';
    final safe = v.isNaN ? 0.0 : v;
    return 'RD\$${safe.toStringAsFixed(2)}';
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

    address ??= raw.trim().isEmpty ? '—' : raw.trim();
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
      data: (service) {
        final assigned = service.assignments
            .map((a) => a.userName.trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);

        final scheduled = service.scheduledStart ?? service.scheduledEnd;

        final location = buildServiceLocationInfo(
          addressOrText: service.customerAddress,
        );

        final snapshot = _parseLocationSnapshot(service.customerAddress);
        final pay = _paymentInfo(service);

        final phone = service.customerPhone.trim();
        final canOpenQuote = phone.isNotEmpty;

        final addressLabel = snapshot.address == '—'
            ? (location.label.trim().isEmpty ? '—' : location.label)
            : snapshot.address;

        final historyAsync = ref.watch(_serviceHistoryProvider(service));

        final images = service.files
            .where(_isLikelyImage)
            .toList(growable: false);
        final videos = service.files
            .where(_isLikelyVideo)
            .toList(growable: false);
        final otherFiles = service.files
            .where((f) => !(_isLikelyImage(f) || _isLikelyVideo(f)))
            .toList(growable: false);

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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              children: [
                TechnicalSectionCard(
                  icon: Icons.flash_on_outlined,
                  title: 'Acciones rápidas',
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final manageButton = FilledButton.icon(
                        onPressed: () {
                          final id = service.id.trim();
                          if (id.isEmpty) return;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted) return;
                            context.push(Routes.operacionesTecnicoDetail(id));
                          });
                        },
                        icon: const Icon(Icons.build_outlined),
                        label: const Text('Gestionar'),
                      );

                      return SizedBox(
                        width: double.infinity,
                        child: manageButton,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TechnicalSectionCard(
                  icon: Icons.person_outline,
                  title: 'Información del cliente',
                  child: Column(
                    children: [
                      _KvRow(label: 'Cliente', value: service.customerName),
                      const SizedBox(height: 10),
                      _KvRow(label: 'Teléfono', value: service.customerPhone),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TechnicalSectionCard(
                  icon: Icons.place_outlined,
                  title: 'Ubicación y referencias',
                  trailing: FilledButton.tonalIcon(
                    onPressed: location.canOpenMaps
                        ? () async {
                            final uri = location.mapsUri;
                            if (uri == null) return;
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        : null,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Abrir en Google Maps'),
                  ),
                  child: Column(
                    children: [
                      _KvRow(label: 'Dirección', value: addressLabel),
                      const SizedBox(height: 10),
                      _KvRow(label: 'Referencia', value: snapshot.reference),
                      const SizedBox(height: 10),
                      _KvRow(label: 'GPS', value: snapshot.gpsText),
                      const SizedBox(height: 10),
                      _KvRow(
                        label: 'MAPS',
                        value: snapshot.mapsText,
                        multiline: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TechnicalSectionCard(
                  icon: Icons.description_outlined,
                  title: 'Información del servicio',
                  child: Column(
                    children: [
                      _KvRow(
                        label: 'Tipo de servicio',
                        value: service.serviceType,
                      ),
                      const SizedBox(height: 10),
                      _KvRow(
                        label: 'Técnico asignado',
                        value: assigned.isEmpty ? '—' : assigned.join(', '),
                      ),
                      const SizedBox(height: 10),
                      _KvRow(
                        label: 'Fecha programada',
                        value: _fmtDate(scheduled),
                      ),
                      const SizedBox(height: 10),
                      _KvRow(
                        label: 'Estado actual',
                        value: service.orderState.trim().isEmpty
                            ? service.status
                            : service.orderState,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TechnicalSectionCard(
                  icon: Icons.subject_outlined,
                  title: 'Descripción del servicio',
                  child: Column(
                    children: [
                      _KvRow(
                        label: 'Trabajo solicitado',
                        value: service.title.trim().isEmpty
                            ? '—'
                            : service.title,
                        multiline: true,
                      ),
                      const SizedBox(height: 10),
                      _KvRow(
                        label: 'Problema / notas',
                        value: service.description.trim().isEmpty
                            ? '—'
                            : service.description,
                        multiline: true,
                      ),
                      const SizedBox(height: 10),
                      const _KvRow(
                        label: 'Notas adicionales',
                        value: '—',
                        multiline: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TechnicalSectionCard(
                  icon: Icons.receipt_long_outlined,
                  title: 'Información de cotización',
                  child: Column(
                    children: [
                      _KvRow(label: 'Total a pagar', value: _money(pay.total)),
                      const SizedBox(height: 10),
                      _KvRow(label: 'Estado del pago', value: pay.status),
                      const SizedBox(height: 10),
                      _KvRow(
                        label: 'Saldo pendiente',
                        value: _money(pay.balance),
                      ),
                      const SizedBox(height: 16),
                      _KvRow(
                        label: 'Total cotizado',
                        value: _money(service.quotedAmount),
                      ),
                      const SizedBox(height: 10),
                      _KvRow(
                        label: 'Depósito',
                        value: _money(service.depositAmount),
                      ),
                      const SizedBox(height: 10),
                      _KvRow(
                        label: 'Costo final',
                        value: _money(service.finalCost),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: canOpenQuote
                              ? () {
                                  final uri = Uri(
                                    path: Routes.cotizacionesHistorial,
                                    queryParameters: {
                                      'customerPhone': phone,
                                      'pick': '0',
                                    },
                                  );
                                  context.go(uri.toString());
                                }
                              : null,
                          icon: const Icon(Icons.open_in_new_outlined),
                          label: const Text('Ver cotización completa'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TechnicalSectionCard(
                  icon: Icons.history_outlined,
                  title: 'Historial de servicios',
                  child: historyAsync.when(
                    loading: () => const _InlineLoading(),
                    error: (e, _) {
                      return Text(
                        e is ApiException ? e.message : e.toString(),
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    },
                    data: (items) {
                      if (items.isEmpty) {
                        return const _EmptyHint(
                          label: 'Sin servicios anteriores para este cliente',
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
                TechnicalSectionCard(
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
              ],
            ),
          ),
        );
      },
    );
  }
}

class _KvRow extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;

  const _KvRow({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final labelWidth = w < 360
            ? 110.0
            : (w < 420 ? 130.0 : (w < 520 ? 140.0 : 150.0));

        return Row(
          crossAxisAlignment: multiline
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value.trim().isEmpty ? '—' : value.trim(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
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

class _EmptyHint extends StatelessWidget {
  final String label;

  const _EmptyHint({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
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
    final cs = theme.colorScheme;

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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: cs.secondaryContainer,
            foregroundColor: cs.onSecondaryContainer,
            child: const Icon(Icons.assignment_outlined, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$dateLabel • ${service.status}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
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
    final cs = theme.colorScheme;

    if (files.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _EmptyHint(label: 'Sin $title'),
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
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
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
                                    color: cs.onSurfaceVariant,
                                  ),
                                );
                              },
                            )
                          else
                            Center(
                              child: Icon(
                                Icons.insert_drive_file_outlined,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          Positioned(
                            left: 6,
                            bottom: 6,
                            right: 6,
                            child: Text(
                              file.caption?.trim().isNotEmpty == true
                                  ? file.caption!.trim()
                                  : '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w800,
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
