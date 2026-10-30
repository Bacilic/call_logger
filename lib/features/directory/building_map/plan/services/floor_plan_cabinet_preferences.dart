import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import '../../../../../core/database/database_helper.dart';
import '../../../../../core/services/current_operator.dart';
import '../../../../../core/services/profile_settings.dart';

/// Θέση, μέγεθος και ύψος προσόψεων του πάνελ της καμπίνας, σε pixel της
/// περιοχής του χάρτη.
class FloorPlanCabinetLayout {
  const FloorPlanCabinetLayout({
    required this.rect,
    required this.facadeHeight,
  });

  final Rect rect;

  /// Πόσο ύψος παίρνει η ζώνη των προσόψεων στο κάτω μέρος του πάνελ.
  final double facadeHeight;

  static const double minWidth = 320;
  static const double minHeight = 320;
  static const double minFacadeHeight = 80;
  static const double defaultWidth = 520;
  static const double defaultFacadeHeight = 220;
  static const double margin = 8;

  /// Στα δεξιά, σε όλο το ύψος — εκεί που άνοιγε πάντα.
  factory FloorPlanCabinetLayout.defaultFor(Size bounds) =>
      FloorPlanCabinetLayout(
        rect: Rect.fromLTWH(
          bounds.width - defaultWidth - margin,
          margin,
          defaultWidth,
          bounds.height - 2 * margin,
        ),
        facadeHeight: defaultFacadeHeight,
      ).fittedTo(bounds);

  /// Το ίδιο πάνελ μέσα στο [bounds]: ποτέ έξω από τον χάρτη, ποτέ
  /// μικρότερο από το ελάχιστο — π.χ. όταν μίκρυνε το παράθυρο.
  FloorPlanCabinetLayout fittedTo(Size bounds) {
    final maxW = math.max(minWidth, bounds.width - 2 * margin);
    final maxH = math.max(minHeight, bounds.height - 2 * margin);
    final w = rect.width.clamp(minWidth, maxW);
    final h = rect.height.clamp(minHeight, maxH);
    final left = rect.left.clamp(
      margin,
      math.max(margin, bounds.width - w - margin),
    );
    final top = rect.top.clamp(
      margin,
      math.max(margin, bounds.height - h - margin),
    );
    return FloorPlanCabinetLayout(
      rect: Rect.fromLTWH(left.toDouble(), top.toDouble(), w, h),
      facadeHeight: facadeHeight.clamp(
        minFacadeHeight,
        math.max(minFacadeHeight, h - 160),
      ),
    );
  }

  FloorPlanCabinetLayout copyWith({Rect? rect, double? facadeHeight}) =>
      FloorPlanCabinetLayout(
        rect: rect ?? this.rect,
        facadeHeight: facadeHeight ?? this.facadeHeight,
      );

  Map<String, Object> toJson() => {
    'left': rect.left,
    'top': rect.top,
    'width': rect.width,
    'height': rect.height,
    'facade': facadeHeight,
  };

  static FloorPlanCabinetLayout? fromJson(Object? json) {
    if (json is! Map) return null;
    double? n(String key) => (json[key] as num?)?.toDouble();
    final left = n('left');
    final top = n('top');
    final width = n('width');
    final height = n('height');
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    return FloorPlanCabinetLayout(
      rect: Rect.fromLTWH(left, top, width, height),
      facadeHeight: n('facade') ?? defaultFacadeHeight,
    );
  }
}

/// Οι προσωπικές ρυθμίσεις του πάνελ της καμπίνας: πού και πόσο είναι, και
/// ποιες συσκευές κάθε καμπίνας είναι επιλεγμένες.
///
/// Κρατιούνται και στη μνήμη μετά την πρώτη ανάγνωση, ώστε το πάνελ να
/// ανοίγει αμέσως στη θέση του χωρίς να «πηδά».
class FloorPlanCabinetPreferences {
  FloorPlanCabinetPreferences._();

  static const _layoutKey = ProfileSettingKeys.floorPlanCabinetPanelLayout;
  static const _selectionKey = ProfileSettingKeys.floorPlanCabinetSelection;

  static FloorPlanCabinetLayout? _layout;
  static bool _layoutRead = false;
  static Map<int, Set<int>>? _selection;

  /// Ποιανού χρήστη είναι η μνήμη: άλλος χρήστης στον ίδιο υπολογιστή
  /// διαβάζει τις δικές του τιμές.
  static int? _owner;

  static void _forgetIfOtherUser() {
    final id = CurrentOperator.active?.id;
    if (id == _owner) return;
    _owner = id;
    _layout = null;
    _layoutRead = false;
    _selection = null;
  }

  /// Η αποθηκευμένη θέση· `null` πριν διαβαστεί ή αν δεν υπάρχει.
  static FloorPlanCabinetLayout? get cachedLayout {
    _forgetIfOtherUser();
    return _layout;
  }

  static Future<FloorPlanCabinetLayout?> readLayout() async {
    _forgetIfOtherUser();
    if (_layoutRead) return _layout;
    try {
      final raw = await _read(_layoutKey);
      _layout = raw == null
          ? null
          : FloorPlanCabinetLayout.fromJson(jsonDecode(raw));
    } catch (_) {
      _layout = null;
    }
    _layoutRead = true;
    return _layout;
  }

  static Future<void> writeLayout(FloorPlanCabinetLayout layout) async {
    _layout = layout;
    _layoutRead = true;
    await _write(_layoutKey, jsonEncode(layout.toJson()));
  }

  /// Οι επιλεγμένες συσκευές της καμπίνας [cabinetId]· κενό από προεπιλογή.
  static Future<Set<int>> readSelection(int cabinetId) async {
    final all = await _allSelections();
    return {...?all[cabinetId]};
  }

  static Future<void> writeSelection(int cabinetId, Set<int> objectIds) async {
    final all = {...await _allSelections()};
    if (objectIds.isEmpty) {
      all.remove(cabinetId);
    } else {
      all[cabinetId] = {...objectIds};
    }
    _selection = all;
    await _write(
      _selectionKey,
      jsonEncode({
        for (final e in all.entries) '${e.key}': (e.value.toList()..sort()),
      }),
    );
  }

  static Future<Map<int, Set<int>>> _allSelections() async {
    _forgetIfOtherUser();
    final cached = _selection;
    if (cached != null) return cached;
    final result = <int, Set<int>>{};
    try {
      final raw = await _read(_selectionKey);
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map) {
        for (final e in decoded.entries) {
          final id = int.tryParse('${e.key}');
          if (id == null || e.value is! List) continue;
          result[id] = {
            for (final v in e.value as List)
              if (v is int) v,
          };
        }
      }
    } catch (_) {
      // Χαλασμένη τιμή: ξεκινά από την αρχή, χωρίς επιλογές.
    }
    return _selection = result;
  }

  static Future<String?> _read(ProfileSettingKey key) async {
    final db = await DatabaseHelper.instance.database;
    return ProfileSettings(db, setting: key).read(key);
  }

  static Future<void> _write(ProfileSettingKey key, String value) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await ProfileSettings(db, setting: key).write(key, value);
    } catch (_) {
      // Αποτυχία εγγραφής δεν ενοχλεί: την επόμενη φορά ανοίγει αλλού.
    }
  }

  /// Για τα τεστ: θέση στη μνήμη χωρίς βάση.
  static void setLayoutForTest(FloorPlanCabinetLayout layout) {
    _forgetIfOtherUser();
    _layout = layout;
    _layoutRead = true;
  }

  /// Μηδενισμός για τα τεστ — η μνήμη είναι καθολική.
  static void resetForTest() {
    _owner = null;
    _layout = null;
    _layoutRead = false;
    _selection = null;
  }
}
