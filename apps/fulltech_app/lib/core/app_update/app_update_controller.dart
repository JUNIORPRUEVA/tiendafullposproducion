import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_models.dart';
import 'app_update_repository.dart';

final appUpdateProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
      return AppUpdateController(ref.read(appUpdateRepositoryProvider));
    });

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(this._repository) : super(AppUpdateState.initial());

  final AppUpdateRepository _repository;
  Future<void>? _checkFuture;
  DateTime? _lastCheckedAt;
  static const Duration _minimumRecheckInterval = Duration(minutes: 1);

  Future<void> checkNow({bool force = false}) {
    if (!force && state.blocksUsage) {
      return Future.value();
    }

    if (!force && _checkFuture != null) {
      return _checkFuture!;
    }

    if (!force && _lastCheckedAt != null) {
      final elapsed = DateTime.now().difference(_lastCheckedAt!);
      if (elapsed < _minimumRecheckInterval) {
        return Future.value();
      }
    }

    late final Future<void> future;
    future = _runCheck().whenComplete(() {
      if (identical(_checkFuture, future)) {
        _checkFuture = null;
      }
    });
    _checkFuture = future;
    return future;
  }

  Future<void> _runCheck() async {
    if (!_repository.isConfigured) {
      state = state.copyWith(
        phase: AppUpdatePhase.disabled,
        message: 'Releases no configurado.',
        clearUpdateInfo: true,
      );
      return;
    }

    final installedRelease = await _repository.readInstalledRelease();
    if (installedRelease == null) {
      state = state.copyWith(
        phase: AppUpdatePhase.unsupported,
        message: 'La plataforma actual no usa releases administrados.',
        clearUpdateInfo: true,
      );
      return;
    }

    state = state.copyWith(
      phase: AppUpdatePhase.checking,
      installedRelease: installedRelease,
      clearMessage: true,
    );

    try {
      final updateInfo = await _repository.checkForUpdate(installedRelease);
      _lastCheckedAt = DateTime.now();

      state = state.copyWith(
        phase: _resolvePhase(updateInfo),
        installedRelease: installedRelease,
        updateInfo: updateInfo,
        checkedAt: _lastCheckedAt,
        clearMessage: true,
      );
    } on AppUpdateConfigurationException catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.disabled,
        installedRelease: installedRelease,
        message: error.message,
        clearUpdateInfo: true,
      );
    } catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        installedRelease: installedRelease,
        message: error.toString(),
        clearUpdateInfo: true,
      );
    }
  }

  AppUpdatePhase _resolvePhase(AppUpdateInfo updateInfo) {
    if (updateInfo.required) return AppUpdatePhase.requiredUpdate;
    if (updateInfo.update) return AppUpdatePhase.optionalUpdate;
    return AppUpdatePhase.upToDate;
  }
}
