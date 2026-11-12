import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/shared_settings.dart';

import '../../../../core/config/app_config.dart';
import 'department_color_palette.dart';

/// Οκτώ θέσεις προσαρμοσμένων χρωμάτων (μετά το λευκό στην παλέτα), **κοινές**
/// για όλους τους σταθμούς.
///
/// Η εικόνα στη μνήμη διαβάζεται μία φορά ανά εκκίνηση· ο συνάδελφος όμως
/// μπορεί να αλλάξει μια θέση στο μεταξύ. Γι' αυτό:
/// - πριν από κάθε απόφαση («ποια θέση είναι κενή;») ο καλών ζητά
///   [refresh], και
/// - κάθε αλλαγή γράφει **μόνο τη δική της θέση** πάνω στη φρέσκια τιμή —
///   ποτέ και τις οκτώ από την εικόνα της μνήμης.
class DepartmentPaletteStore extends ChangeNotifier {
  DepartmentPaletteStore._();

  static final DepartmentPaletteStore instance = DepartmentPaletteStore._();

  static const customSlotCount = 8;

  static const _prefsKeySlots = 'department_custom_palette_slots_v2';
  static const _prefsKeyLegacy = 'department_custom_palette_hex_v1';

  static String _prefKey(String baseKey) =>
      AppConfig.prefixedPreferencesKey(baseKey);

  List<Color?> _slots = List<Color?>.filled(customSlotCount, null);
  Future<void>? _loading;

  List<Color?> get customSlots => List<Color?>.unmodifiable(_slots);

  Future<void> ensureLoaded() {
    _loading ??= _load();
    return _loading!;
  }

  /// Ξαναδιαβάζει τις θέσεις από τα κοινά — πριν από κάθε ενέργεια στην
  /// παλέτα, ώστε η απόφαση να μη στηρίζεται σε εικόνα του πρωινού.
  Future<void> refresh() async {
    await ensureLoaded();
    final shared = await SharedSettings.read(
      SharedSettingKeys.departmentPaletteSlots,
    );
    if (shared == null || shared.isEmpty) return;
    _adopt(SharedSettings.decodeList(shared));
  }

  /// Μετά από rollback επαναφοράς ρυθμίσεων εφαρμογής.
  Future<void> reloadFromPreferences() async {
    _loading = null;
    await ensureLoaded();
  }

  Future<void> _load() async {
    // Η παλέτα είναι **κοινή** (Φάση 2): το χρώμα ενός τμήματος πρέπει να
    // σημαίνει το ίδιο για όλη την ομάδα. Η τοπική τιμή ανεβαίνει στα κοινά
    // μία φορά, από τον διαχειριστή.
    final shared = await SharedSettings.read(
      SharedSettingKeys.departmentPaletteSlots,
    );
    List<String>? raw = shared == null || shared.isEmpty
        ? null
        : SharedSettings.decodeList(shared);
    if (raw == null) {
      final prefs = await SharedPreferences.getInstance();
      raw = await _migrateFromLegacy(prefs);
    }
    _adopt(raw);
  }

  void _adopt(List<String> raw) {
    final slots = List<Color?>.filled(customSlotCount, null);
    for (var i = 0; i < customSlotCount; i++) {
      if (i < raw.length) {
        slots[i] = tryParseDepartmentHex(raw[i]);
      }
    }
    _slots = slots;
    notifyListeners();
  }

  Future<List<String>> _migrateFromLegacy(SharedPreferences prefs) async {
    final legacy = prefs.getStringList(_prefKey(_prefsKeyLegacy)) ?? const [];
    final slots = List<String>.filled(customSlotCount, '');
    var slotIndex = 0;
    for (final h in legacy) {
      if (slotIndex >= customSlotCount) break;
      if (tryParseDepartmentHex(h) == null) continue;
      slots[slotIndex++] = h;
    }
    await prefs.setStringList(_prefKey(_prefsKeySlots), slots);
    return slots;
  }

  /// Γράφει **μόνο** τη θέση [index] πάνω στην τρέχουσα αποθηκευμένη λίστα,
  /// και υιοθετεί ό,τι αποθηκεύτηκε — μαζί με τις θέσεις του συναδέλφου.
  Future<void> _writeSlot(int index, Color? color) async {
    final hex = color == null ? '' : colorToDepartmentHex(color);
    final stored = await SharedSettings.update(
      SharedSettingKeys.departmentPaletteSlots,
      (current) {
        final list = List<String>.filled(customSlotCount, '');
        final existing = SharedSettings.decodeList(current);
        for (var i = 0; i < customSlotCount && i < existing.length; i++) {
          list[i] = existing[i];
        }
        list[index] = hex;
        return SharedSettings.encodeList(list);
      },
    );
    if (stored != null) {
      _adopt(SharedSettings.decodeList(stored));
    } else {
      _slots = List<Color?>.from(_slots)..[index] = color;
      notifyListeners();
    }
  }

  /// Πρώτη κενή θέση (0–7) ή null αν η παλέτα είναι πλήρη.
  int? get firstEmptySlotIndex {
    for (var i = 0; i < customSlotCount; i++) {
      if (_slots[i] == null) return i;
    }
    return null;
  }

  bool get isCustomPaletteFull => firstEmptySlotIndex == null;

  /// Υπάρχει το ίδιο hex σε προκαθορισμένα ή άλλη custom θέση.
  bool colorExistsInPalette(Color color, {int? exceptSlotIndex}) {
    final hex = colorToDepartmentHex(color);
    for (final c in kDepartmentPaletteColors) {
      if (colorToDepartmentHex(c) == hex) return true;
    }
    for (var i = 0; i < customSlotCount; i++) {
      if (exceptSlotIndex == i) continue;
      final c = _slots[i];
      if (c != null && colorToDepartmentHex(c) == hex) return true;
    }
    return false;
  }

  /// Ευρετήριο θέσης αν το χρώμα είναι σε custom θέση, αλλιώς null.
  int? indexOfCustomColor(Color color) {
    final hex = colorToDepartmentHex(color);
    for (var i = 0; i < customSlotCount; i++) {
      final c = _slots[i];
      if (c != null && colorToDepartmentHex(c) == hex) return i;
    }
    return null;
  }

  /// Αποθήκευση χρώματος σε συγκεκριμένη θέση (0–7).
  Future<void> setCustomSlot(int index, Color color) async {
    assert(index >= 0 && index < customSlotCount);
    await ensureLoaded();
    await _writeSlot(index, color);
  }

  /// Καθαρισμός θέσης.
  Future<void> clearCustomSlot(int index) async {
    assert(index >= 0 && index < customSlotCount);
    await ensureLoaded();
    if (_slots[index] == null) return;
    await _writeSlot(index, null);
  }
}
