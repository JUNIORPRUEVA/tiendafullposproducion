import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/api_exception.dart';
import '../../core/routing/routes.dart';
import 'data/document_flows_repository.dart';
import 'document_flow_models.dart';

class DocumentFlowsScreen extends ConsumerStatefulWidget {
  const DocumentFlowsScreen({super.key});

  @override
  ConsumerState<DocumentFlowsScreen> createState() => _DocumentFlowsScreenState();
}

class _DocumentFlowsScreenState extends ConsumerState<DocumentFlowsScreen> {
  bool _loading = true;
  String? _error;
  List<OrderDocumentFlowModel> _flows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final flows = await ref.read(documentFlowsRepositoryProvider).listFlows();
      if (!mounted) return;
      setState(() {
        _flows = flows;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el flujo documental';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <DocumentFlowStatus, List<OrderDocumentFlowModel>>{};
    for (final flow in _flows) {
      grouped.putIfAbsent(flow.status, () => <OrderDocumentFlowModel>[]).add(flow);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flujo documental'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 96),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      ),
                    ],
                  )
                : _flows.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 96),
                          Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No hay flujos documentales disponibles'),
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: DocumentFlowStatus.values
                            .where((status) => grouped[status]?.isNotEmpty ?? false)
                            .map(
                              (status) => _DocumentFlowSection(
                                status: status,
                                flows: grouped[status]!,
                              ),
                            )
                            .toList(growable: false),
                      ),
      ),
    );
  }
}

class _DocumentFlowSection extends StatelessWidget {
  const _DocumentFlowSection({
    required this.status,
    required this.flows,
  });

  final DocumentFlowStatus status;
  final List<OrderDocumentFlowModel> flows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              status.label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ...flows.map(
            (flow) => Card(
              child: ListTile(
                onTap: () => context.go(Routes.documentFlowByOrderId(flow.orderId)),
                title: Text(flow.order.client.nombre),
                subtitle: Text(
                  'Orden ${flow.order.id.substring(0, 8).toUpperCase()} · ${flow.order.serviceType} · ${flow.order.category}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(flow.status.label),
                    if (flow.sentAt != null)
                      Text(
                        'Enviado',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}