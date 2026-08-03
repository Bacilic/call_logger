/// Ανάλυση όρων «#id» σε κείμενο αναζήτησης.
///
/// Το πρόθεμα «#» σημαίνει «ακριβές αναγνωριστικό»: ο όρος «#243» ταιριάζει
/// την οντότητα με id 243 και μόνο αυτήν — όχι το «1243» ούτε τιμές που
/// απλώς περιέχουν το «243». Οι υπόλοιποι όροι παραμένουν ελεύθερο κείμενο.
class IdSearchQuery {
  const IdSearchQuery({
    required this.ids,
    required this.hasInvalidIdToken,
    required this.text,
  });

  /// Αριθμητικά ids από όρους «#N».
  final List<int> ids;

  /// true όταν υπάρχει όρος «#» χωρίς έγκυρο αριθμό (π.χ. «#», «#αβγ»).
  /// Τότε η αναζήτηση δεν ταιριάζει τίποτα — ειλικρινές «κανένα αποτέλεσμα»
  /// αντί για σιωπηλή μετάπτωση σε αναζήτηση κειμένου.
  final bool hasInvalidIdToken;

  /// Το υπόλοιπο κείμενο χωρίς τους όρους «#…».
  final String text;

  bool get hasIdTokens => ids.isNotEmpty || hasInvalidIdToken;

  bool get isEmpty => !hasIdTokens && text.isEmpty;

  static IdSearchQuery parse(String query) {
    final ids = <int>[];
    var invalid = false;
    final rest = <String>[];
    for (final token in query.trim().split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      if (token.startsWith('#')) {
        final id = int.tryParse(token.substring(1));
        if (id == null) {
          invalid = true;
        } else {
          ids.add(id);
        }
        continue;
      }
      rest.add(token);
    }
    return IdSearchQuery(
      ids: ids,
      hasInvalidIdToken: invalid,
      text: rest.join(' '),
    );
  }

  /// true αν η τιμή είναι όρος «#…» (υποψήφιο ακριβές αναγνωριστικό).
  static bool isIdToken(String value) => value.trim().startsWith('#');

  /// Ο αριθμός μετά το «#», ή null αν δεν είναι έγκυρος όρος id.
  static int? parseIdToken(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('#')) return null;
    return int.tryParse(trimmed.substring(1).trim());
  }

  /// Ταίριασμα οντότητας με ΟΛΟΥΣ τους όρους «#id» του query.
  bool matchesEntityId(int? entityId) {
    if (hasInvalidIdToken) return false;
    if (ids.isEmpty) return true;
    if (entityId == null) return false;
    return ids.every((id) => id == entityId);
  }
}
