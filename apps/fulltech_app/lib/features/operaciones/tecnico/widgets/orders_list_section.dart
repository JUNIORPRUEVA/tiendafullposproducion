import 'package:flutter/material.dart';

import '../../operations_models.dart';

class OrdersListSection extends StatelessWidget {
  final bool loading;
  final String? error;
  final List<ServiceModel> services;
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry padding;
  final double itemSpacing;
  final Widget Function(BuildContext context, ServiceModel service) itemBuilder;

  const OrdersListSection({
    super.key,
    required this.loading,
    required this.error,
    required this.services,
    required this.onRefresh,
    this.padding = const EdgeInsets.fromLTRB(8, 0, 8, 12),
    this.itemSpacing = 6,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && services.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null && services.isEmpty) {
      return _MessageState(
        icon: Icons.cloud_off_rounded,
        title: 'No fue posible cargar las órdenes',
        message: error!,
      );
    }

    if (services.isEmpty) {
      return const _MessageState(
        icon: Icons.inventory_2_outlined,
        title: 'Sin órdenes visibles',
        message: 'Ajusta los filtros o actualiza para buscar más servicios.',
      );
    }

    final list = ListView.builder(
      padding: padding,
      cacheExtent: 720,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == services.length - 1 ? 0 : itemSpacing,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: itemBuilder(context, service),
            ),
          ),
        );
      },
    );

    if (onRefresh == null) return list;

    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9F2FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, color: const Color(0xFF0B6BDE), size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF10233F),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5B6B82),
                    height: 1.4,
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
