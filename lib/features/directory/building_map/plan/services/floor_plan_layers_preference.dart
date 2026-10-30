import 'dart:convert';

import '../../../../../core/database/database_helper.dart';
import '../../../../../core/services/profile_settings.dart';

/// Οι κρυμμένες στρώσεις του χάρτη για τον ενεργό χρήστη — μία ρύθμιση,
/// κοινή για τον κεντρικό χάρτη και τη σχεδίαση.
class FloorPlanLayersPreference {
  const FloorPlanLayersPreference._();

  static const _key = ProfileSettingKeys.floorPlanHiddenLayers;

  /// Κενό σύνολο όταν δεν έχει οριστεί ή δεν διαβάζεται: όλα φαίνονται.
  static Future<Set<String>> read() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final raw = await ProfileSettings(db, setting: _key).read(_key);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return {
        for (final item in decoded)
          if (item is String) item,
      };
    } catch (_) {
      return const {};
    }
  }

  static Future<void> write(Set<String> hidden) async {
    final db = await DatabaseHelper.instance.database;
    await ProfileSettings(
      db,
      setting: _key,
    ).write(_key, jsonEncode(hidden.toList()..sort()));
  }
}
