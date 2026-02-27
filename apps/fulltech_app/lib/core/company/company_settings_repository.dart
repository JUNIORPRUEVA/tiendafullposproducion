import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'company_settings_model.dart';

final companySettingsRepositoryProvider = Provider<CompanySettingsRepository>((
  ref,
) {
  return CompanySettingsRepository();
});

class CompanySettingsRepository {
  static const _key = 'company_settings_v1';

  Future<CompanySettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return CompanySettings.empty();

    try {
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return CompanySettings.fromMap(map);
    } catch (_) {
      return CompanySettings.empty();
    }
  }

  Future<void> saveSettings(CompanySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toMap()));
  }
}
