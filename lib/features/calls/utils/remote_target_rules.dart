/// Κανόνες αναγνώρισης στόχων απομακρυσμένης σύνδεσης (AnyDesk) από κείμενο ή τιμές μοντέλου.
abstract final class RemoteTargetRules {
  RemoteTargetRules._();

  static final RegExp _anydeskLocalPart = RegExp(r'^[a-zA-Z0-9.\-_]+$');

  /// Έγκυρος στόχος AnyDesk: ακριβώς 9–10 ψηφία, ή μορφή `name@namespace` (έως 25 χαρακτήρες).
  static bool isValidAnyDeskTarget(String t) {
    final trimmed = t.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.length == 9 || trimmed.length == 10) {
      return RegExp(r'^\d+$').hasMatch(trimmed);
    }
    if (trimmed.contains('@')) {
      final parts = trimmed.split('@');
      if (parts.length != 2) return false;
      return parts[0].isNotEmpty &&
          parts[1].isNotEmpty &&
          _anydeskLocalPart.hasMatch(parts[0]) &&
          _anydeskLocalPart.hasMatch(parts[1]) &&
          trimmed.length <= 25;
    }
    return false;
  }

  /// Εξαγωγή στόχου AnyDesk από ελεύθερο κείμενο εξοπλισμού (χωρίς επιλεγμένη εγγραφή από βάση).
  static String? parseAnyDeskFromFreeText(String equipmentText) {
    final t = equipmentText.trim();
    if (t.isEmpty) return null;
    if (isValidAnyDeskTarget(t)) return t;

    final digitMatch = RegExp(r'(?<![0-9])(\d{9,10})(?![0-9])').firstMatch(t);
    if (digitMatch != null) {
      final id = digitMatch.group(1)!;
      if (isValidAnyDeskTarget(id)) return id;
    }

    final atMatch = RegExp(
      r'([a-zA-Z0-9.\-_]+@[a-zA-Z0-9.\-_]+)',
    ).firstMatch(t);
    if (atMatch != null) {
      final ns = atMatch.group(1)!;
      if (isValidAnyDeskTarget(ns)) return ns.trim();
    }
    return null;
  }
}
