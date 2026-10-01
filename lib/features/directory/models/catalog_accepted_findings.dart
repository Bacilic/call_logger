import 'dart:convert';

import 'catalog_validation_finding.dart';

/// Τα αποτυπώματα ([CatalogValidationFinding.acceptKey]) των ευρημάτων που ο
/// χρήστης έκρινε σωστά — μία λίστα κειμένων στη βάση.
class CatalogAcceptedFindings {
  const CatalogAcceptedFindings(this.keys);

  final Set<String> keys;

  static const CatalogAcceptedFindings none = CatalogAcceptedFindings(
    <String>{},
  );

  /// Κενό ή αλλοιωμένο κείμενο = καμία αποδοχή: μια χαλασμένη τιμή δεν
  /// πρέπει να κρύψει ευρήματα ούτε να ρίξει τον έλεγχο.
  factory CatalogAcceptedFindings.fromRawJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return none;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return none;
      return CatalogAcceptedFindings({
        for (final item in decoded)
          if (item is String && item.isNotEmpty) item,
      });
    } on FormatException {
      return none;
    }
  }

  String toRawJson() => jsonEncode(keys.toList()..sort());

  CatalogAcceptedFindings withKey(String key) =>
      CatalogAcceptedFindings({...keys, key});

  CatalogAcceptedFindings withoutKey(String key) =>
      CatalogAcceptedFindings({...keys}..remove(key));

  bool isAccepted(CatalogValidationFinding finding) {
    final key = finding.acceptKey;
    return key != null && keys.contains(key);
  }

  /// Χωρίζει τα ευρήματα σε ανοιχτά και αποδεκτά, κρατώντας τη σειρά τους.
  ({
    List<CatalogValidationFinding> open,
    List<CatalogValidationFinding> accepted,
  })
  partition(List<CatalogValidationFinding> findings) {
    final open = <CatalogValidationFinding>[];
    final accepted = <CatalogValidationFinding>[];
    for (final finding in findings) {
      (isAccepted(finding) ? accepted : open).add(finding);
    }
    return (open: open, accepted: accepted);
  }
}
