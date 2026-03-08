import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkScheduleRequest {
  final String id;
  final String type; // day_off_change | special_leave | block_date | swap
  final String fromDate;
  final String toDate;
  final String reason;
  final String status; // pending | approved | rejected
  final DateTime createdAt;

  const WorkScheduleRequest({
    required this.id,
    required this.type,
    required this.fromDate,
    required this.toDate,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  String get typeLabel {
    switch (type) {
      case 'day_off_change':
        return 'Cambio de día libre';
      case 'special_leave':
        return 'Permiso especial';
      case 'block_date':
        return 'Bloqueo de fecha';
      case 'swap':
        return 'Intercambio';
      default:
        return type;
    }
  }
}

class WorkSchedulingRequestsState {
  final List<WorkScheduleRequest> items;

  const WorkSchedulingRequestsState({required this.items});

  factory WorkSchedulingRequestsState.initial() =>
      const WorkSchedulingRequestsState(items: []);
}

final workSchedulingRequestsControllerProvider =
    StateNotifierProvider.autoDispose<
      WorkSchedulingRequestsController,
      WorkSchedulingRequestsState
    >((ref) => WorkSchedulingRequestsController(ref));

class WorkSchedulingRequestsController
    extends StateNotifier<WorkSchedulingRequestsState> {
  final Ref ref;

  WorkSchedulingRequestsController(this.ref)
    : super(WorkSchedulingRequestsState.initial());

  void create({
    required String type,
    required String fromDate,
    required String toDate,
    required String reason,
  }) {
    final now = DateTime.now();
    final req = WorkScheduleRequest(
      id: '${now.microsecondsSinceEpoch}',
      type: type,
      fromDate: fromDate,
      toDate: toDate,
      reason: reason,
      status: 'pending',
      createdAt: now,
    );

    final next = [req, ...state.items];
    state = WorkSchedulingRequestsState(items: next);
  }
}
