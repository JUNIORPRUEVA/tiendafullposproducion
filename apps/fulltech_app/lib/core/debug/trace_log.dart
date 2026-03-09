import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

class TraceLog {
  static int _seq = 0;

  static int nextSeq() => ++_seq;

  static void log(
    String scope,
    String message, {
    int? seq,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!kDebugMode) return;

    final id = seq ?? nextSeq();
    final ts = DateTime.now().toIso8601String();
    final base = '[TRACE][$id][$ts][$scope] $message';

    if (error != null) {
      dev.log(base, name: 'TraceLog', error: error, stackTrace: stackTrace);
      return;
    }

    dev.log(base, name: 'TraceLog');
  }
}
