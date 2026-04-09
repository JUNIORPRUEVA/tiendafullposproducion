enum ReleasePlatform { android, windows }

extension ReleasePlatformApiValue on ReleasePlatform {
  String get apiValue {
    switch (this) {
      case ReleasePlatform.android:
        return 'android';
      case ReleasePlatform.windows:
        return 'windows';
    }
  }

  String get displayName {
    switch (this) {
      case ReleasePlatform.android:
        return 'Android';
      case ReleasePlatform.windows:
        return 'Windows';
    }
  }
}

class InstalledReleaseInfo {
  final ReleasePlatform platform;
  final String currentVersion;
  final int currentBuild;

  const InstalledReleaseInfo({
    required this.platform,
    required this.currentVersion,
    required this.currentBuild,
  });
}

class AppUpdateInfo {
  final bool update;
  final bool required;
  final String? latestVersion;
  final int? latestBuild;
  final String? downloadUrl;
  final String? releaseNotes;
  final int? fileSize;

  const AppUpdateInfo({
    required this.update,
    required this.required,
    this.latestVersion,
    this.latestBuild,
    this.downloadUrl,
    this.releaseNotes,
    this.fileSize,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      update: json['update'] == true,
      required: json['required'] == true,
      latestVersion: (json['latest_version'] as String?)?.trim(),
      latestBuild: _asInt(json['latest_build']),
      downloadUrl: (json['download_url'] as String?)?.trim(),
      releaseNotes: (json['release_notes'] as String?)?.trim(),
      fileSize: _asInt(json['file_size']),
    );
  }

  bool get hasDownloadUrl => (downloadUrl ?? '').isNotEmpty;

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}

enum AppUpdatePhase {
  idle,
  disabled,
  unsupported,
  checking,
  upToDate,
  optionalUpdate,
  requiredUpdate,
  error,
}

class AppUpdateState {
  final AppUpdatePhase phase;
  final InstalledReleaseInfo? installedRelease;
  final AppUpdateInfo? updateInfo;
  final String? message;
  final DateTime? checkedAt;

  const AppUpdateState({
    required this.phase,
    this.installedRelease,
    this.updateInfo,
    this.message,
    this.checkedAt,
  });

  factory AppUpdateState.initial() {
    return const AppUpdateState(phase: AppUpdatePhase.idle);
  }

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    InstalledReleaseInfo? installedRelease,
    AppUpdateInfo? updateInfo,
    String? message,
    DateTime? checkedAt,
    bool clearUpdateInfo = false,
    bool clearMessage = false,
  }) {
    return AppUpdateState(
      phase: phase ?? this.phase,
      installedRelease: installedRelease ?? this.installedRelease,
      updateInfo: clearUpdateInfo ? null : (updateInfo ?? this.updateInfo),
      message: clearMessage ? null : (message ?? this.message),
      checkedAt: checkedAt ?? this.checkedAt,
    );
  }

  bool get blocksUsage => phase == AppUpdatePhase.requiredUpdate;
}
