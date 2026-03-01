import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/errors/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/punch_model.dart';
import './application/punch_controller.dart';

class PoncheScreen extends ConsumerStatefulWidget {
  const PoncheScreen({super.key});

  @override
  ConsumerState<PoncheScreen> createState() => _PoncheScreenState();
}

class _PoncheScreenState extends ConsumerState<PoncheScreen> {
  void _showPunchOptions(PunchState state) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '¿Qué deseas registrar?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ...PunchType.values.map(
                (type) => ListTile(
                  leading: Icon(_iconFor(type), color: AppTheme.primaryColor),
                  title: Text(type.label),
                  onTap: state.creating
                      ? null
                      : () {
                          Navigator.pop(context);
                          _handlePunch(type);
                        },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showHistory(PunchState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          builder: (context, controller) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Historial de ponches',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (state.loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (state.items.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('Aún no hay ponches registrados'),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      controller: controller,
                      itemCount: state.items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final punch = state.items[index];
                        final time = DateFormat(
                          'dd/MM/yyyy · hh:mm a',
                        ).format(punch.timestamp.toLocal());
                        return ListTile(
                          leading: Icon(
                            _iconFor(punch.type),
                            color: AppTheme.primaryColor,
                          ),
                          title: Text(punch.type.label),
                          subtitle: Text(time),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handlePunch(PunchType type) async {
    try {
      final punch = await ref
          .read(punchControllerProvider.notifier)
          .register(type);
      if (!mounted) return;
      final time = DateFormat('hh:mm a').format(punch.timestamp.toLocal());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ponche "${type.label}" registrado a las $time'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'No se pudo registrar el ponche';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final punchState = ref.watch(punchControllerProvider);

    return Scaffold(
      drawer: AppDrawer(currentUser: auth.user),
      appBar: AppBar(
        title: const Text('Ponche'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _buildUserTab(punchState),
    );
  }

  Widget _buildUserTab(PunchState state) {
    final lastPunch = state.items.isNotEmpty ? state.items.first : null;
    final statusLabel = _statusLabelFrom(lastPunch);
    final statusColor = _statusColorFrom(lastPunch);
    final statusIcon = _statusIconFrom(lastPunch);
    final chipForeground = statusColor.computeLuminance() > 0.75
        ? Colors.black87
        : statusColor;
    final lastStamp = lastPunch != null
        ? DateFormat(
            'dd/MM/yyyy · hh:mm a',
          ).format(lastPunch.timestamp.toLocal())
        : null;
    final lastLabel = lastPunch != null
        ? '${lastPunch.type.label} · $lastStamp'
        : 'Todavía no hay registros';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.error != null) ...[
                Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      state.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Estado actual',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    backgroundColor: statusColor.withAlpha(
                      (0.15 * 255).round(),
                    ),
                    avatar: Icon(statusIcon, color: chipForeground),
                    label: Text(
                      statusLabel,
                      style: TextStyle(
                        color: chipForeground,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withAlpha((0.18 * 255).round()),
                  foregroundColor: Colors.white,
                  elevation: 8,
                  minimumSize: const Size.fromHeight(72),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(36),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                onPressed: state.creating
                    ? null
                    : () => _showPunchOptions(state),
                child: state.creating
                    ? const SizedBox(
                        height: 28,
                        width: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('PONCHAR'),
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    lastLabel,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (lastStamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Registrado a las $lastStamp',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => _showHistory(state),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text(
                    'Historial',
                    style: TextStyle(decoration: TextDecoration.underline),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _statusIconFrom(PunchModel? punch) {
    switch (punch?.type) {
      case PunchType.entradaLabor:
      case PunchType.entradaAlmuerzo:
      case PunchType.entradaPermiso:
        return Icons.login;
      case PunchType.salidaLabor:
        return Icons.exit_to_app;
      case PunchType.salidaAlmuerzo:
      case PunchType.salidaPermiso:
        return Icons.pause_circle_filled;
      default:
        return Icons.circle_outlined;
    }
  }

  Color _statusColorFrom(PunchModel? punch) {
    switch (punch?.type) {
      case PunchType.entradaLabor:
      case PunchType.entradaAlmuerzo:
      case PunchType.entradaPermiso:
        return Colors.green;
      case PunchType.salidaLabor:
        return Colors.red;
      case PunchType.salidaAlmuerzo:
      case PunchType.salidaPermiso:
        return Colors.orange;
      default:
        return Colors.white;
    }
  }

  String _statusLabelFrom(PunchModel? punch) {
    switch (punch?.type) {
      case PunchType.entradaLabor:
      case PunchType.entradaAlmuerzo:
      case PunchType.entradaPermiso:
        return 'En jornada';
      case PunchType.salidaLabor:
        return 'Fuera';
      case PunchType.salidaAlmuerzo:
        return 'En almuerzo';
      case PunchType.salidaPermiso:
        return 'En permiso';
      default:
        return 'Fuera';
    }
  }
}

IconData _iconFor(PunchType type) {
  return switch (type) {
    PunchType.entradaLabor => Icons.login,
    PunchType.salidaLabor => Icons.exit_to_app,
    PunchType.salidaPermiso => Icons.meeting_room_outlined,
    PunchType.entradaPermiso => Icons.door_back_door,
    PunchType.salidaAlmuerzo => Icons.fastfood,
    PunchType.entradaAlmuerzo => Icons.restaurant,
  };
}
