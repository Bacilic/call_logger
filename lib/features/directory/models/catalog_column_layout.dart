import 'dart:convert';

/// Στήλη πίνακα Καταλόγου: αρκεί ένα σταθερό κλειδί για να αποθηκευτεί.
abstract interface class CatalogColumn {
  String get key;
}

/// Κλειδί της στήλης επιλογής — κοινό στους τέσσερις πίνακες.
const kCatalogSelectionColumnKey = 'selection';

/// Αποτέλεσμα ανάγνωσης ρυθμίσεων στηλών (σειρά πλήρους λίστας + ποια κλειδιά
/// είναι ορατά).
typedef CatalogColumnLayout<C extends CatalogColumn> = ({
  List<C> order,
  Set<String> visible,
});

/// Ανάγνωση της αποθηκευμένης διάταξης στηλών ενός πίνακα Καταλόγου.
///
/// Μία συνάρτηση για Υπαλλήλους, Τμήματα, Εξοπλισμό και Κατηγορίες: τέσσερα
/// αντίγραφα είχαν ήδη αποκλίνει — η διόρθωση για τις νέες στήλες είχε μπει
/// μόνο στο ένα.
///
/// Δύο μορφές γίνονται δεκτές: το σημερινό αντικείμενο `{order, visible}` και
/// η παλιά σκέτη λίστα κλειδιών. Στήλη που δεν υπάρχει στο αποθηκευμένο
/// κείμενο είναι **νέα** — μπαίνει στο τέλος και παίρνει την ορατότητα που θα
/// είχε σε καθαρή εγκατάσταση ([defaultVisible]). Μόνο ό,τι υπάρχει στη σειρά
/// και λείπει από τις ορατές το έκρυψε πράγματι ο χρήστης.
///
/// Επιστρέφει `null` όταν το κείμενο δεν διαβάζεται· ο καλών κρατά τότε την
/// προεπιλεγμένη διάταξη.
CatalogColumnLayout<C>? parseCatalogColumnLayoutJson<C extends CatalogColumn>(
  String raw, {
  required List<C> all,
  required Set<String> defaultVisible,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  final known = {for (final c in all) c.key: c};

  if (decoded is Map<String, dynamic>) {
    final order = _knownColumnsInOrder(decoded['order'], known);
    final added = _appendMissingColumns(order, all);
    final v = decoded['visible'];
    var visible = <String>{
      if (v is List)
        for (final e in v)
          if (e is String && known.containsKey(e)) e,
    };
    if (visible.isEmpty) {
      visible = Set<String>.from(defaultVisible);
    } else {
      visible.addAll(added.intersection(defaultVisible));
    }
    return (order: pinCatalogSelectionFirst(order), visible: visible);
  }

  if (decoded is List) {
    final order = _knownColumnsInOrder(decoded, known);
    if (order.isEmpty) return null;
    final visible = {for (final c in order) c.key};
    visible.addAll(
      _appendMissingColumns(order, all).intersection(defaultVisible),
    );
    return (order: pinCatalogSelectionFirst(order), visible: visible);
  }
  return null;
}

/// Η στήλη επιλογής πάντα στην πρώτη θέση (αν υπάρχει στη λίστα).
List<C> pinCatalogSelectionFirst<C extends CatalogColumn>(List<C> order) {
  final selection = order
      .where((c) => c.key == kCatalogSelectionColumnKey)
      .firstOrNull;
  if (selection == null) return List<C>.from(order);
  return [selection, ...order.where((c) => c.key != selection.key)];
}

List<C> _knownColumnsInOrder<C extends CatalogColumn>(
  Object? raw,
  Map<String, C> known,
) {
  final order = <C>[];
  final seen = <String>{};
  if (raw is! List) return order;
  for (final e in raw) {
    if (e is! String) continue;
    final c = known[e];
    if (c != null && seen.add(c.key)) order.add(c);
  }
  return order;
}

/// Προσθέτει στο τέλος όσες στήλες λείπουν και επιστρέφει τα κλειδιά τους.
Set<String> _appendMissingColumns<C extends CatalogColumn>(
  List<C> order,
  List<C> all,
) {
  final present = {for (final c in order) c.key};
  final added = <String>{};
  for (final c in all) {
    if (present.add(c.key)) {
      order.add(c);
      added.add(c.key);
    }
  }
  return added;
}
