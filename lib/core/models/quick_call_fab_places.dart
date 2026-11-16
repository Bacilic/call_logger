import 'dart:convert';

/// Οι οθόνες που μπορούν να δείξουν το υπτάμενο κουμπί γρήγορης κλήσης.
///
/// Η σειρά εδώ είναι η σειρά των διακοπτών στις Ρυθμίσεις.
enum QuickCallFabPlace {
  dictionary('Λεξικό'),
  statistics('Στατιστικά'),
  settings('Ρυθμίσεις'),
  mapView('Προβολή χάρτη'),
  floorPlanDesign('Σχεδίαση χάρτη'),
  historyAudit('Έλεγχος ιστορικού (πλήρης οθόνη)'),
  lansweeperReport('Αναφορά Lansweeper');

  const QuickCallFabPlace(this.label);

  final String label;
}

/// Σε ποιες οθόνες φαίνεται το κουμπί γρήγορης κλήσης (ρύθμιση χρήστη).
///
/// Αποθηκεύονται τα **κρυμμένα** σημεία, ώστε ένα σημείο που προστίθεται
/// αργότερα να ξεκινά ορατό σε όλους.
class QuickCallFabPlaces {
  const QuickCallFabPlaces._(this._hidden);

  /// Το κουμπί φαίνεται παντού.
  static const QuickCallFabPlaces all = QuickCallFabPlaces._({});

  /// Το κουμπί δεν φαίνεται πουθενά.
  static final QuickCallFabPlaces none = QuickCallFabPlaces._(
    Set.unmodifiable(QuickCallFabPlace.values),
  );

  final Set<QuickCallFabPlace> _hidden;

  bool shows(QuickCallFabPlace place) => !_hidden.contains(place);

  int get shownCount => QuickCallFabPlace.values.where(shows).length;

  QuickCallFabPlaces withPlace(QuickCallFabPlace place, bool shown) {
    final hidden = {..._hidden};
    shown ? hidden.remove(place) : hidden.add(place);
    return QuickCallFabPlaces._(Set.unmodifiable(hidden));
  }

  String toJsonString() => jsonEncode({
    'hidden': [
      for (final p in QuickCallFabPlace.values)
        if (!shows(p)) p.name,
    ],
  });

  /// Διαβάζει την αποθηκευμένη τιμή.
  ///
  /// Χωρίς δική της τιμή κληρονομεί τον παλιό ενιαίο διακόπτη: όποιος τον
  /// είχε κλειστό ξεκινά με όλα τα σημεία κλειστά, όλοι οι άλλοι με όλα
  /// ανοιχτά.
  static QuickCallFabPlaces fromStorage(String? raw, {bool? legacyShow}) {
    final fallback = legacyShow == false ? none : all;
    if (raw == null || raw.trim().isEmpty) return fallback;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['hidden'] is! List) return fallback;
      final names = (decoded['hidden'] as List).whereType<String>().toSet();
      return QuickCallFabPlaces._(
        Set.unmodifiable({
          for (final p in QuickCallFabPlace.values)
            if (names.contains(p.name)) p,
        }),
      );
    } on FormatException {
      return fallback;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is QuickCallFabPlaces &&
      other._hidden.length == _hidden.length &&
      other._hidden.containsAll(_hidden);

  @override
  int get hashCode => Object.hashAllUnordered(_hidden);
}
