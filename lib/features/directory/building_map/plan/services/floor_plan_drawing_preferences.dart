import 'dart:convert';

import '../../../../../core/database/database_helper.dart';
import '../../../../../core/services/profile_settings.dart';

/// Οι βοήθειες της σχεδίασης που ανοιγοκλείνουν από το γρανάζι.
///
/// Όλες ανοιχτές από την αρχή· αποθηκεύονται όσες **έκλεισε** ο χρήστης, ώστε
/// μια βοήθεια που θα προστεθεί αργότερα να ξεκινά ανοιχτή.
class FloorPlanDrawingAids {
  const FloorPlanDrawingAids({this.guides = true, this.angles = true});

  /// Από το σύνολο των κλειστών, όπως αποθηκεύεται.
  FloorPlanDrawingAids.fromOff(Set<String> off)
    : guides = !off.contains(_guidesKey),
      angles = !off.contains(_anglesKey);

  static const _guidesKey = 'guides';
  static const _anglesKey = 'angles';

  /// Γραμμές-οδηγοί: η προέκταση και η κάθετη από τις άκρες των τοίχων.
  final bool guides;

  /// Μοίρες τομής: η γωνία ενός τοίχου με όσους συναντά.
  final bool angles;

  FloorPlanDrawingAids copyWith({bool? guides, bool? angles}) =>
      FloorPlanDrawingAids(
        guides: guides ?? this.guides,
        angles: angles ?? this.angles,
      );

  /// Οι κλειστές βοήθειες, όπως αποθηκεύονται.
  Set<String> get off => {if (!guides) _guidesKey, if (!angles) _anglesKey};
}

/// Οι βοήθειες σχεδίασης του ενεργού χρήστη — προσωπική ρύθμιση, που τον
/// ακολουθεί σε όποιον υπολογιστή.
class FloorPlanDrawingPreferences {
  const FloorPlanDrawingPreferences._();

  static const _key = ProfileSettingKeys.floorPlanDrawingAidsOff;

  /// Όλες ανοιχτές όταν δεν έχει οριστεί ή δεν διαβάζεται.
  static Future<FloorPlanDrawingAids> read() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final raw = await ProfileSettings(db, setting: _key).read(_key);
      if (raw == null || raw.isEmpty) return const FloorPlanDrawingAids();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const FloorPlanDrawingAids();
      return FloorPlanDrawingAids.fromOff({
        for (final item in decoded)
          if (item is String) item,
      });
    } catch (_) {
      return const FloorPlanDrawingAids();
    }
  }

  static Future<void> write(FloorPlanDrawingAids aids) async {
    final db = await DatabaseHelper.instance.database;
    await ProfileSettings(
      db,
      setting: _key,
    ).write(_key, jsonEncode(aids.off.toList()..sort()));
  }
}
