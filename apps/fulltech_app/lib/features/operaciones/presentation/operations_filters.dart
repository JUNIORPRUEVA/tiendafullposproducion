import 'package:flutter/material.dart';

enum OperationsDatePreset { today, week, month, custom }

enum OperationsStatusFilter { all, pending, inProgress, completed, cancelled }

enum OperationsPriorityFilter { all, high, normal, low }

class OperationsFilters {
  final String? createdByUserId;
  final String? technicianId;

  final OperationsDatePreset datePreset;
  final DateTime dateFrom;
  final DateTime dateTo;

  final OperationsStatusFilter status;
  final OperationsPriorityFilter priority;

  const OperationsFilters({
    required this.createdByUserId,
    required this.technicianId,
    required this.datePreset,
    required this.dateFrom,
    required this.dateTo,
    required this.status,
    required this.priority,
  });

  factory OperationsFilters.todayDefault() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    return OperationsFilters(
      createdByUserId: null,
      technicianId: null,
      datePreset: OperationsDatePreset.today,
      dateFrom: start,
      dateTo: end,
      status: OperationsStatusFilter.all,
      priority: OperationsPriorityFilter.all,
    );
  }

  OperationsFilters copyWith({
    String? createdByUserId,
    bool clearCreatedBy = false,
    String? technicianId,
    bool clearTechnician = false,
    OperationsDatePreset? datePreset,
    DateTime? dateFrom,
    DateTime? dateTo,
    OperationsStatusFilter? status,
    OperationsPriorityFilter? priority,
  }) {
    return OperationsFilters(
      createdByUserId: clearCreatedBy
          ? null
          : (createdByUserId ?? this.createdByUserId),
      technicianId: clearTechnician
          ? null
          : (technicianId ?? this.technicianId),
      datePreset: datePreset ?? this.datePreset,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      status: status ?? this.status,
      priority: priority ?? this.priority,
    );
  }

  DateTimeRange get range => DateTimeRange(start: dateFrom, end: dateTo);

  OperationsFilters withTodayRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    return copyWith(
      datePreset: OperationsDatePreset.today,
      dateFrom: start,
      dateTo: end,
    );
  }

  OperationsFilters withWeekRange() {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final end = start.add(const Duration(days: 6));
    return copyWith(
      datePreset: OperationsDatePreset.week,
      dateFrom: DateTime(start.year, start.month, start.day),
      dateTo: DateTime(end.year, end.month, end.day, 23, 59, 59, 999),
    );
  }

  OperationsFilters withMonthRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0);
    return copyWith(
      datePreset: OperationsDatePreset.month,
      dateFrom: DateTime(start.year, start.month, start.day),
      dateTo: DateTime(end.year, end.month, end.day, 23, 59, 59, 999),
    );
  }

  OperationsFilters withCustomRange(DateTimeRange picked) {
    final start = DateTime(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );
    final end = DateTime(
      picked.end.year,
      picked.end.month,
      picked.end.day,
      23,
      59,
      59,
      999,
    );
    return copyWith(
      datePreset: OperationsDatePreset.custom,
      dateFrom: start,
      dateTo: end,
    );
  }
}
