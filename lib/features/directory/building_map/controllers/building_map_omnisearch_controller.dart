import 'package:flutter/foundation.dart';

import '../../../../core/database/omnisearch_service.dart';

/// Υπογραφή της αναζήτησης χάρτη — ό,τι ακριβώς χρειάζεται το πεδίο.
typedef BuildingMapOmnisearch =
    Future<List<BuildingMapOmnisearchHit>> Function(String query);

/// Αναζήτηση χάρτη με debounce και ακύρωση ξεπερασμένων αιτημάτων.
///
/// **Συμβόλαιο:** ο καλών ρωτά με ένα κείμενο και παίρνει τα αποτελέσματα
/// ΑΥΤΟΥ του κειμένου — ποτέ κατάσταση που γεμίζει αργότερα. Επιστροφή `null`
/// σημαίνει «το αίτημα ξεπεράστηκε από νεότερο, μη το χρησιμοποιήσεις».
class BuildingMapOmnisearchController {
  BuildingMapOmnisearchController({
    required this.search,
    this.debounce = const Duration(milliseconds: 220),
  });

  /// Μεταβλητή ώστε το widget να ακολουθεί αλλαγή repositories χωρίς να χάνει
  /// τον controller (και μαζί του την εκκρεμή αναζήτηση).
  BuildingMapOmnisearch search;

  final Duration debounce;

  /// True όσο εκκρεμεί αναζήτηση — για τον δείκτη φόρτωσης του πεδίου.
  final ValueNotifier<bool> isSearching = ValueNotifier<bool>(false);

  int _seq = 0;
  bool _disposed = false;

  /// Αναζήτηση μετά από [debounce] — για την πληκτρολόγηση.
  Future<List<BuildingMapOmnisearchHit>?> query(String raw) =>
      _run(raw, wait: true);

  /// Αναζήτηση χωρίς αναμονή — για Enter και το κουμπί αναζήτησης.
  Future<List<BuildingMapOmnisearchHit>?> queryImmediate(String raw) =>
      _run(raw, wait: false);

  Future<List<BuildingMapOmnisearchHit>?> _run(
    String raw, {
    required bool wait,
  }) async {
    if (_disposed) return null;
    final q = raw.trim();
    final own = ++_seq;

    if (q.isEmpty) {
      _setSearching(false);
      return const [];
    }

    if (wait) {
      await Future<void>.delayed(debounce);
      if (_isStale(own)) return null;
    }

    _setSearching(true);
    try {
      final hits = await search(q);
      return _isStale(own) ? null : hits;
    } finally {
      if (own == _seq) _setSearching(false);
    }
  }

  bool _isStale(int own) => _disposed || own != _seq;

  void _setSearching(bool value) {
    if (_disposed || isSearching.value == value) return;
    isSearching.value = value;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _seq++;
    isSearching.dispose();
  }
}
