import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/app_config.dart';
import 'department_color_palette.dart';

/// Οκτώ θέσεις προσαρμοσμένων χρωμάτων (μετά το λευκό στην παλέτα), τοπική αποθήκευση.
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

  /// Μετά από rollback επαναφοράς ρυθμίσεων εφαρμογής.
  Future<void> reloadFromPreferences() async {
    _loading = null;
    await ensureLoaded();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getStringList(_prefKey(_prefsKeySlots));
    raw ??= await _migrateFromLegacy(prefs);
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

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefKey(_prefsKeySlots),
      [
        for (final c in _slots) c == null ? '' : colorToDepartmentHex(c),
      ],
    );
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
    _slots = List<Color?>.from(_slots)..[index] = color;
    await _persist();
    notifyListeners();
  }

  /// Καθαρισμός θέσης.
  Future<void> clearCustomSlot(int index) async {
    assert(index >= 0 && index < customSlotCount);
    await ensureLoaded();
    if (_slots[index] == null) return;
    _slots = List<Color?>.from(_slots)..[index] = null;
    await _persist();
    notifyListeners();
  }
}
