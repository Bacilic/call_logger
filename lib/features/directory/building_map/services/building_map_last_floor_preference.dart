import '../../../../core/database/database_helper.dart';
import '../../../../core/services/profile_settings.dart';

/// Ο όροφος που είδε τελευταίο ο ενεργός χρήστης στον χάρτη κτιρίου.
class BuildingMapLastFloorPreference {
  const BuildingMapLastFloorPreference._();

  static const _key = ProfileSettingKeys.buildingMapLastFloor;

  /// `null` όταν δεν έχει οριστεί ή δεν διαβάζεται: τότε ισχύει ο κανόνας
  /// της πρώτης φοράς.
  static Future<int?> read() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final raw = await ProfileSettings(db, setting: _key).read(_key);
      return raw == null ? null : int.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// Αποτυχία εγγραφής δεν ενοχλεί τον χρήστη: θα ανοίξει απλώς αλλού.
  static Future<void> write(int floorId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await ProfileSettings(db, setting: _key).write(_key, '$floorId');
    } catch (_) {}
  }
}
