import 'package:flutter/foundation.dart';

String minutesToHm(int? minutes) {
  final value = minutes ?? 0;
  final h = (value ~/ 60).toString().padLeft(2, '0');
  final m = (value % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

DateTime parseDateOnly(String isoDate) {
  // Expects YYYY-MM-DD.
  final parts = isoDate.split('-');
  if (parts.length != 3) return DateTime.tryParse(isoDate) ?? DateTime.now();
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

String dateOnly(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String weekdayLabelEs(int weekday) {
  switch (weekday) {
    case 0:
      return 'Lun';
    case 1:
      return 'Mar';
    case 2:
      return 'Mié';
    case 3:
      return 'Jue';
    case 4:
      return 'Vie';
    case 5:
      return 'Sáb';
    case 6:
      return 'Dom';
    default:
      return 'Día';
  }
}

@immutable
class WorkDayAssignment {
  final String id;
  final String userId;
  final String userName;
  final String? role;
  final String date; // YYYY-MM-DD
  final int weekday; // 0..6 (Mon..Sun)
  final String status; // WORK | DAY_OFF | EXCEPTION_OFF
  final int? startMinute;
  final int? endMinute;
  final bool manualOverride;
  final String? note;
  final List<String> conflictFlags;

  const WorkDayAssignment({
    required this.id,
    required this.userId,
    required this.userName,
    required this.role,
    required this.date,
    required this.weekday,
    required this.status,
    required this.startMinute,
    required this.endMinute,
    required this.manualOverride,
    required this.note,
    required this.conflictFlags,
  });

  factory WorkDayAssignment.fromJson(Map<String, dynamic> json) {
    final flagsRaw = json['conflict_flags'];
    final flags = flagsRaw is List
        ? flagsRaw.whereType<String>().toList()
        : const <String>[];

    return WorkDayAssignment(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      userName: (json['user_name'] ?? '').toString(),
      role: json['role']?.toString(),
      date: (json['date'] ?? '').toString(),
      weekday: (json['weekday'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? '').toString(),
      startMinute: (json['start_minute'] as num?)?.toInt(),
      endMinute: (json['end_minute'] as num?)?.toInt(),
      manualOverride: ((json['manual_override'] as num?)?.toInt() ?? 0) == 1,
      note: json['note']?.toString(),
      conflictFlags: flags,
    );
  }
}

@immutable
class WorkWeekSchedule {
  final String id;
  final String weekStartDate; // YYYY-MM-DD
  final DateTime generatedAt;
  final List<Map<String, dynamic>> warnings;
  final List<WorkDayAssignment> days;

  const WorkWeekSchedule({
    required this.id,
    required this.weekStartDate,
    required this.generatedAt,
    required this.warnings,
    required this.days,
  });

  factory WorkWeekSchedule.fromJson(Map<String, dynamic> json) {
    final warningsRaw = json['warnings'];
    final warnings = warningsRaw is List
        ? warningsRaw
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList()
        : <Map<String, dynamic>>[];

    final daysRaw = json['days'];
    final days = daysRaw is List
        ? daysRaw
            .whereType<Map>()
            .map((e) => WorkDayAssignment.fromJson(e.cast<String, dynamic>()))
            .toList()
        : <WorkDayAssignment>[];

    return WorkWeekSchedule(
      id: (json['id'] ?? '').toString(),
      weekStartDate: (json['week_start_date'] ?? '').toString(),
      generatedAt: DateTime.tryParse((json['generated_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      warnings: warnings,
      days: days,
    );
  }
}

@immutable
class WorkEmployeeScheduleConfig {
  final bool enabled;
  final String? scheduleProfileId;
  final int? preferredDayOffWeekday;
  final int? fixedDayOffWeekday;
  final List<int> disallowedDayOffWeekdays;
  final List<int> unavailableWeekdays;
  final String? notes;
  final int? lastAssignedDayOffWeekday;

  const WorkEmployeeScheduleConfig({
    required this.enabled,
    required this.scheduleProfileId,
    required this.preferredDayOffWeekday,
    required this.fixedDayOffWeekday,
    required this.disallowedDayOffWeekdays,
    required this.unavailableWeekdays,
    required this.notes,
    required this.lastAssignedDayOffWeekday,
  });

  factory WorkEmployeeScheduleConfig.fromJson(Map<String, dynamic> json) {
    List<int> intList(dynamic v) {
      if (v is List) {
        return v.whereType<num>().map((e) => e.toInt()).toList();
      }
      return const [];
    }

    return WorkEmployeeScheduleConfig(
      enabled: json['enabled'] == true,
      scheduleProfileId: json['schedule_profile_id']?.toString(),
      preferredDayOffWeekday:
          (json['preferred_day_off_weekday'] as num?)?.toInt(),
      fixedDayOffWeekday: (json['fixed_day_off_weekday'] as num?)?.toInt(),
      disallowedDayOffWeekdays: intList(json['disallowed_day_off_weekdays']),
      unavailableWeekdays: intList(json['unavailable_weekdays']),
      notes: json['notes']?.toString(),
      lastAssignedDayOffWeekday:
          (json['last_assigned_day_off_weekday'] as num?)?.toInt(),
    );
  }
}

@immutable
class WorkEmployee {
  final String id;
  final String nombreCompleto;
  final String? email;
  final String? telefono;
  final String role;
  final bool blocked;
  final WorkEmployeeScheduleConfig schedule;

  const WorkEmployee({
    required this.id,
    required this.nombreCompleto,
    required this.email,
    required this.telefono,
    required this.role,
    required this.blocked,
    required this.schedule,
  });

  factory WorkEmployee.fromJson(Map<String, dynamic> json) {
    return WorkEmployee(
      id: (json['id'] ?? '').toString(),
      nombreCompleto: (json['nombre_completo'] ?? '').toString(),
      email: json['email']?.toString(),
      telefono: json['telefono']?.toString(),
      role: (json['role'] ?? '').toString(),
      blocked: ((json['blocked'] as num?)?.toInt() ?? 0) == 1,
      schedule: WorkEmployeeScheduleConfig.fromJson(
        (json['schedule'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

@immutable
class WorkScheduleProfileDay {
  final int weekday;
  final bool isWorking;
  final String kind;
  final int? startMinute;
  final int? endMinute;

  const WorkScheduleProfileDay({
    required this.weekday,
    required this.isWorking,
    required this.kind,
    required this.startMinute,
    required this.endMinute,
  });

  factory WorkScheduleProfileDay.fromJson(Map<String, dynamic> json) {
    return WorkScheduleProfileDay(
      weekday: (json['weekday'] as num?)?.toInt() ?? 0,
      isWorking: json['is_working'] == true,
      kind: (json['kind'] ?? 'NORMAL').toString(),
      startMinute: (json['start_minute'] as num?)?.toInt(),
      endMinute: (json['end_minute'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toUpsertJson() {
    return {
      'weekday': weekday,
      'is_working': isWorking,
      'kind': kind,
      'start_minute': startMinute,
      'end_minute': endMinute,
    };
  }
}

@immutable
class WorkScheduleProfile {
  final String id;
  final String name;
  final bool isDefault;
  final List<WorkScheduleProfileDay> days;

  const WorkScheduleProfile({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.days,
  });

  factory WorkScheduleProfile.fromJson(Map<String, dynamic> json) {
    final daysRaw = json['days'];
    final days = daysRaw is List
        ? daysRaw
            .whereType<Map>()
            .map((e) => WorkScheduleProfileDay.fromJson(
                  e.cast<String, dynamic>(),
                ))
            .toList()
        : <WorkScheduleProfileDay>[];

    return WorkScheduleProfile(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      isDefault: json['is_default'] == true,
      days: days,
    );
  }
}

@immutable
class WorkCoverageRule {
  final String role;
  final int weekday;
  final int minRequired;

  const WorkCoverageRule({
    required this.role,
    required this.weekday,
    required this.minRequired,
  });

  factory WorkCoverageRule.fromJson(Map<String, dynamic> json) {
    return WorkCoverageRule(
      role: (json['role'] ?? '').toString(),
      weekday: (json['weekday'] as num?)?.toInt() ?? 0,
      minRequired: (json['min_required'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toUpsertJson() {
    return {'role': role, 'weekday': weekday, 'min_required': minRequired};
  }
}

@immutable
class WorkScheduleException {
  final String id;
  final String? userId;
  final String? userName;
  final String type;
  final String dateFrom;
  final String dateTo;
  final String? note;

  const WorkScheduleException({
    required this.id,
    required this.userId,
    required this.userName,
    required this.type,
    required this.dateFrom,
    required this.dateTo,
    required this.note,
  });

  factory WorkScheduleException.fromJson(Map<String, dynamic> json) {
    return WorkScheduleException(
      id: (json['id'] ?? '').toString(),
      userId: json['user_id']?.toString(),
      userName: json['user_name']?.toString(),
      type: (json['type'] ?? '').toString(),
      dateFrom: (json['date_from'] ?? '').toString(),
      dateTo: (json['date_to'] ?? '').toString(),
      note: json['note']?.toString(),
    );
  }
}

@immutable
class WorkScheduleAuditLog {
  final String id;
  final String action;
  final String actorUserId;
  final String actorName;
  final String? targetUserId;
  final String? targetUserName;
  final String? weekStartDate;
  final String? date;
  final String? fromDate;
  final String? toDate;
  final String? reason;
  final DateTime createdAt;

  const WorkScheduleAuditLog({
    required this.id,
    required this.action,
    required this.actorUserId,
    required this.actorName,
    required this.targetUserId,
    required this.targetUserName,
    required this.weekStartDate,
    required this.date,
    required this.fromDate,
    required this.toDate,
    required this.reason,
    required this.createdAt,
  });

  factory WorkScheduleAuditLog.fromJson(Map<String, dynamic> json) {
    return WorkScheduleAuditLog(
      id: (json['id'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      actorUserId: (json['actor_user_id'] ?? '').toString(),
      actorName: (json['actor_name'] ?? '').toString(),
      targetUserId: json['target_user_id']?.toString(),
      targetUserName: json['target_user_name']?.toString(),
      weekStartDate: json['week_start_date']?.toString(),
      date: json['date']?.toString(),
      fromDate: json['from_date']?.toString(),
      toDate: json['to_date']?.toString(),
      reason: json['reason']?.toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
