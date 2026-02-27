import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/api_exception.dart';
import 'data/operations_repository.dart';
import 'operations_models.dart';

class OperacionesFinalizadosScreen extends ConsumerStatefulWidget {
	const OperacionesFinalizadosScreen({super.key});

	@override
	ConsumerState<OperacionesFinalizadosScreen> createState() =>
			_OperacionesFinalizadosScreenState();
}

class _OperacionesFinalizadosScreenState
		extends ConsumerState<OperacionesFinalizadosScreen> {
	final _bodyKey = GlobalKey<OperacionesFinalizadosBodyState>();

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			appBar: AppBar(
				title: const Text('Finalizados'),
				actions: [
					IconButton(
						tooltip: 'Actualizar',
						onPressed: () => _bodyKey.currentState?.refresh(),
						icon: const Icon(Icons.refresh),
					),
				],
			),
			body: OperacionesFinalizadosBody(key: _bodyKey),
		);
	}
}

class OperacionesFinalizadosBody extends ConsumerStatefulWidget {
	final bool showHeader;
	final EdgeInsets padding;
	final DateTime? selectedDay;

	const OperacionesFinalizadosBody({
		super.key,
		this.showHeader = true,
		this.selectedDay,
		this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 18),
	});

	@override
	ConsumerState<OperacionesFinalizadosBody> createState() =>
			OperacionesFinalizadosBodyState();
}

class OperacionesFinalizadosBodyState extends ConsumerState<OperacionesFinalizadosBody> {
	bool _loading = false;
	String? _error;
	List<ServiceModel> _items = const [];

	static const int _pageSize = 120;
	static const int _maxPages = 25;

	bool _isSameDay(DateTime a, DateTime b) {
		return a.year == b.year && a.month == b.month && a.day == b.day;
	}

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

			final merged = byId.values.toList()
				..sort((a, b) {
					final ad = a.completedAt;
					final bd = b.completedAt;
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
				_error =
						e is ApiException ? e.message : 'No se pudieron cargar finalizados';
			});
		}
	}

	String _statusLabel(String raw) {
		switch (raw) {
			case 'completed':
				return 'Finalizada';
			case 'closed':
				return 'Cerrada';
			default:
				return raw;
		}
	}

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

	Future<void> _openQuickDetail(ServiceModel service) async {
		final df = DateFormat('dd/MM/yyyy HH:mm', 'es');
		final techs = service.assignments.map((a) => a.userName).toList();

		await showModalBottomSheet<void>(
			context: context,
			showDragHandle: true,
			builder: (context) {
				return SafeArea(
					child: Padding(
						padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
						child: Column(
							mainAxisSize: MainAxisSize.min,
							crossAxisAlignment: CrossAxisAlignment.start,
							children: [
								Text(
									service.title,
									style: Theme.of(context)
											.textTheme
											.titleMedium
											?.copyWith(fontWeight: FontWeight.w800),
								),
								const SizedBox(height: 6),
								Text('${service.customerName} · ${service.customerPhone}'),
								const SizedBox(height: 10),
								Wrap(
									spacing: 8,
									runSpacing: 8,
									children: [
										_pill(context, 'Estado', _statusLabel(service.status)),
										_pill(context, 'Tipo', _typeLabel(service.serviceType)),
										_pill(context, 'Prioridad', 'P${service.priority}'),
										_pill(
											context,
											'Finalizó',
											service.completedAt == null
													? '—'
													: df.format(service.completedAt!),
										),
									],
								),
								if (techs.isNotEmpty) ...[
									const SizedBox(height: 12),
									Text(
										'Técnicos',
										style: Theme.of(context)
												.textTheme
												.bodyMedium
												?.copyWith(fontWeight: FontWeight.w700),
									),
									const SizedBox(height: 6),
									Text(techs.join(', ')),
								],
								const SizedBox(height: 14),
								Align(
									alignment: Alignment.centerRight,
									child: FilledButton(
										onPressed: () => Navigator.of(context).pop(),
										child: const Text('Cerrar'),
									),
								),
							],
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

		final filteredItems = widget.selectedDay == null
				? _items
				: _items.where((service) {
						final completedAt = service.completedAt;
						if (completedAt == null) return false;
						return _isSameDay(completedAt, widget.selectedDay!);
					}).toList();

		return RefreshIndicator(
			onRefresh: _load,
			child: ListView(
				padding: widget.padding,
				children: [
					if (widget.showHeader)
						Card(
							child: Padding(
								padding: const EdgeInsets.all(12),
								child: Row(
									children: [
										const Icon(Icons.done_all),
										const SizedBox(width: 10),
										Expanded(
											child: Text(
												'Servicios finalizados (${filteredItems.length})',
												style: theme.textTheme.titleSmall
														?.copyWith(fontWeight: FontWeight.w800),
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
					if (widget.showHeader) const SizedBox(height: 8),
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
						const SizedBox(height: 8),
					],
					if (!_loading && _error == null && filteredItems.isEmpty)
						Card(
							child: Padding(
								padding: const EdgeInsets.all(14),
								child: Row(
									children: [
										Icon(
											Icons.check_circle_outline,
											color: theme.colorScheme.primary,
										),
										const SizedBox(width: 10),
										Expanded(
											child: Text(
												widget.selectedDay == null
														? 'Aún no hay servicios finalizados para mostrar.'
														: 'Sin finalizados para este día ✅',
												style: theme.textTheme.bodyMedium
														?.copyWith(fontWeight: FontWeight.w700),
											),
										),
									],
								),
							),
						)
					else
						...filteredItems.map((service) {
							final completedAt = service.completedAt;
							final dateText = completedAt == null
									? 'Sin fecha de finalización'
									: DateFormat('dd/MM/yyyy HH:mm', 'es').format(completedAt);

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
											'${_statusLabel(service.status)} · ${_typeLabel(service.serviceType)} · P${service.priority}\n$dateText',
											maxLines: 3,
											overflow: TextOverflow.ellipsis,
										),
										trailing: const Icon(Icons.chevron_right),
										onTap: () => _openQuickDetail(service),
									),
								),
							);
						}),
				],
			),
		);
	}
}

