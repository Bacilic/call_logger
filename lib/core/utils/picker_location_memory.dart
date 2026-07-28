import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'file_picker_initial_directory.dart';

/// Θυμάται τον τελευταίο φάκελο ΑΝΑ ΛΕΙΤΟΥΡΓΙΑ (feature key), ώστε κάθε
/// επιλογέας αρχείων να ανοίγει στοχευμένα στη δική του τοποθεσία και όχι
/// στην καθολική «τελευταία θέση» των Windows, που μολύνεται από άσχετους
/// επιλογείς της ίδιας εφαρμογής.
///
/// Χρήση: `initialDirectory` πριν τον επιλογέα (με προαιρετικό ρητό hint από
/// σχετικό πεδίο), `remember` μετά από επιτυχή επιλογή.
class PickerLocationMemory {
  const PickerLocationMemory(this.featureKey);

  /// Σταθερό αναγνωριστικό λειτουργίας (π.χ. 'building_map_image').
  final String featureKey;

  static const _keyPrefix = 'picker_last_directory::';

  String get _prefKey => '$_keyPrefix$featureKey';

  /// Αρχικός φάκελος για τον επιλογέα. Προτεραιότητα: ρητό [pathHint] από
  /// σχετικό πεδίο → αποθηκευμένος φάκελος της λειτουργίας → null
  /// (προεπιλογή των Windows).
  Future<String?> initialDirectory({String? pathHint}) async {
    final hint = pathHint?.trim() ?? '';
    if (hint.isNotEmpty) {
      return initialDirectoryForFilePicker(hint);
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey)?.trim() ?? '';
    if (stored.isEmpty) return null;
    try {
      if (Directory(stored).existsSync()) return stored;
    } catch (_) {}
    return null;
  }

  /// Αποθηκεύει τον φάκελο του επιλεγμένου αρχείου [pickedPath] για την
  /// επόμενη φορά. Κενές/άκυρες διαδρομές αγνοούνται σιωπηλά.
  Future<void> remember(String pickedPath) async {
    final trimmed = pickedPath.trim();
    if (trimmed.isEmpty) return;
    final dir = p.dirname(trimmed);
    if (dir.isEmpty || dir == trimmed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, p.normalize(dir));
  }
}
