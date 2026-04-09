import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_routes.dart';
import '../api/env.dart';
import '../debug/trace_log.dart';
import 'app_update_models.dart';

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>((ref) {
  return AppUpdateRepository();
});

class AppUpdateRepository {
  const AppUpdateRepository();

  bool get isConfigured => Env.releasesEnabled;

  ReleasePlatform? getSupportedPlatform() {
    if (kIsWeb) return null;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return ReleasePlatform.android;
      case TargetPlatform.windows:
        return ReleasePlatform.windows;
      default:
        return null;
    }
  }

  Future<InstalledReleaseInfo?> readInstalledRelease() async {
    final platform = getSupportedPlatform();
    if (platform == null) return null;

    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version.trim().isEmpty
        ? '0.0.0'
        : info.version.trim();
    final currentBuild = int.tryParse(info.buildNumber.trim()) ?? 0;

    return InstalledReleaseInfo(
      platform: platform,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
    );
  }

  Future<AppUpdateInfo> checkForUpdate(
    InstalledReleaseInfo installedRelease,
  ) async {
    final baseUrl = Env.releasesApiBaseUrl;
    final apiKey = Env.releasesApiKey;
    if (baseUrl == null || apiKey.isEmpty) {
      throw const AppUpdateConfigurationException(
        'La configuración de releases no está completa.',
      );
    }

    final seq = TraceLog.nextSeq();
    TraceLog.log(
      'AppUpdate',
      'check start ${installedRelease.platform.apiValue} ${installedRelease.currentVersion}+${installedRelease.currentBuild}',
      seq: seq,
    );

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: Duration(milliseconds: Env.apiTimeoutMs),
        sendTimeout: Duration(milliseconds: Env.apiTimeoutMs),
        receiveTimeout: Duration(milliseconds: Env.apiTimeoutMs),
        headers: {'Accept': 'application/json', 'x-api-key': apiKey},
      ),
    );

    try {
      final response = await dio.get<Map<String, dynamic>>(
        ApiRoutes.releaseCheckUpdate,
        queryParameters: {
          'platform': installedRelease.platform.apiValue,
          'current_build': installedRelease.currentBuild,
          'current_version': installedRelease.currentVersion,
        },
      );

      final data = response.data ?? const <String, dynamic>{};
      final parsed = AppUpdateInfo.fromJson(data);
      TraceLog.log(
        'AppUpdate',
        'check done update=${parsed.update} required=${parsed.required}',
        seq: seq,
      );
      return parsed;
    } catch (error, stackTrace) {
      TraceLog.log(
        'AppUpdate',
        'check failed',
        seq: seq,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      dio.close(force: true);
    }
  }
}

class AppUpdateConfigurationException implements Exception {
  final String message;

  const AppUpdateConfigurationException(this.message);

  @override
  String toString() => message;
}
