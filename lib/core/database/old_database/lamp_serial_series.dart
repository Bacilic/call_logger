/// Αρίθμηση σειράς σε διπλότυπους σειριακούς αριθμούς.
///
/// Στο νοσοκομείο πολλοί «σειριακοί» είναι στην πραγματικότητα barcode
/// **προϊόντος**: κάθε πληκτρολόγιο KB-103 φέρει το ίδιο `8716309093675`.
/// Η καθιερωμένη πρακτική είναι να προστίθεται αύξων αριθμός — και ήδη
/// εφαρμόζεται χειροκίνητα στη βάση, π.χ. `10NXMP0026001-1` έως `-10`.
///
/// Η αρίθμηση οδηγείται από **πρότυπο** με τον τελεστή [kLampSeriesCounterToken]:
/// `NLSHR125070-<αύξον>` δίνει `NLSHR125070-1`, `-2`, `-3`. Το πρότυπο είναι
/// ελεύθερο κείμενο, γιατί η βάση δεν δίνει πάντα χρήσιμη αφετηρία — όταν ο
/// σειριακός είναι σκέτη παύλα, η σύμβαση του νοσοκομείου βάζει το μοντέλο
/// στη θέση του (`Πληκτρολόγιο USB Dell (61)-1`).
///
/// Δύο κανόνες που βγήκαν από τα πραγματικά δεδομένα:
/// - **Όλες** οι εγγραφές παίρνουν αριθμό, καμία δεν μένει γυμνή· η υπάρχουσα
///   σειρά δεν έχει γυμνό πρώτο.
/// - Η σειρά ακολουθεί τον **κωδικό εξοπλισμού**: το τμήμα αλλάζει όταν
///   μετακινηθεί μηχάνημα, ο κωδικός όχι, οπότε η ίδια ενέργεια βγάζει πάντα
///   το ίδιο αποτέλεσμα.
library;

/// Ο τελεστής που αντικαθίσταται από τον αύξοντα αριθμό.
const String kLampSeriesCounterToken = '<αύξον>';

/// Τιμές που δεν λένε τίποτα για τη συσκευή.
///
/// Η σκέτη παύλα είναι η συνηθέστερη: σημαίνει «δεν έχει σειριακό», και
/// χρησιμοποιημένη ως αφετηρία θα παρήγαγε `--1`.
bool lampSerialIsPlaceholder(String? serial) {
  final trimmed = (serial ?? '').trim();
  if (trimmed.isEmpty) return true;
  if (trimmed.length <= 2) return true;
  return const <String>{'-', '—', '.', '0', 'n/a', 'na'}.contains(
    trimmed.toLowerCase(),
  );
}

/// Κλειδί άδειας τύπου Microsoft: πέντε πεντάδες με παύλες.
final RegExp _licenseKeyPattern = RegExp(
  r'^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$',
  caseSensitive: false,
);

const List<String> _softwareHints = <String>[
  'windows',
  'office',
  'λογισμικ',
  'license',
  'άδεια',
];

/// Μοιάζει η τιμή με κλειδί άδειας λογισμικού;
///
/// Τέτοιες τιμές **επαναλαμβάνονται νόμιμα** σε δεκάδες μηχανήματα: είκοσι
/// υπολογιστές με την ίδια volume license δεν είναι σφάλμα. Η αρίθμηση θα
/// κατέστρεφε τη μόνη χρήσιμη πληροφορία — ότι μοιράζονται την ίδια άδεια.
bool lampSerialLooksLikeLicenseKey({
  required String serial,
  String? modelName,
  String? categoryName,
}) {
  if (_licenseKeyPattern.hasMatch(serial.trim())) return true;
  final haystack = '${modelName ?? ''} ${categoryName ?? ''}'.toLowerCase();
  return _softwareHints.any(haystack.contains);
}

/// Το προτεινόμενο πρότυπο για μια ομάδα.
///
/// Όταν ο σειριακός λέει κάτι, χτίζεται πάνω του. Όταν δεν λέει, μπαίνει το
/// μοντέλο — η σύμβαση που ήδη χρησιμοποιείται στο νοσοκομείο όταν το
/// μηχάνημα δεν φέρει δικό του σειριακό.
String lampSuggestedSeriesTemplate({
  required String serial,
  String? modelName,
  int? modelId,
}) {
  final root = lampSerialSeriesRoot(serial);
  if (!lampSerialIsPlaceholder(root)) {
    return '$root-$kLampSeriesCounterToken';
  }
  final name = (modelName ?? '').trim();
  if (name.isEmpty || lampSerialIsPlaceholder(name)) {
    return modelId == null
        ? kLampSeriesCounterToken
        : '$modelId-$kLampSeriesCounterToken';
  }
  final suffix = modelId == null ? '' : ' ($modelId)';
  return '$name$suffix-$kLampSeriesCounterToken';
}

/// Η ρίζα ενός σειριακού που ανήκει ήδη σε σειρά, ή `null` αν δεν ανήκει.
///
/// `10NXMP0026001-7` → `10NXMP0026001`, `MX-B427W (2)` → `MX-B427W`.
({String root, int index})? lampSerialSeriesMember(String serial) {
  final trimmed = serial.trim();
  final dash = RegExp(r'^(.*[^\s-])-(\d{1,3})$').firstMatch(trimmed);
  if (dash != null) {
    return (root: dash.group(1)!, index: int.parse(dash.group(2)!));
  }
  final paren = RegExp(r'^(.*\S)\s*\((\d{1,3})\)$').firstMatch(trimmed);
  if (paren != null) {
    return (root: paren.group(1)!, index: int.parse(paren.group(2)!));
  }
  return null;
}

/// Η βάση ενός σειριακού: χωρίς τον αύξοντα, αν έχει.
String lampSerialSeriesRoot(String serial) =>
    (lampSerialSeriesMember(serial)?.root ?? serial).trim();

/// Το πρότυπο περιέχει τον τελεστή;
///
/// Χωρίς αυτόν κάθε εγγραφή θα έπαιρνε **την ίδια** τιμή και το διπλότυπο θα
/// έμενε ακέραιο — απλώς με άλλο κείμενο.
bool lampSeriesTemplateIsValid(String template) =>
    template.contains(kLampSeriesCounterToken);

/// Ό,τι χρειάζεται ο διάλογος για να δείξει και να εφαρμόσει την αρίθμηση.
class LampSerialSeriesPlan {
  const LampSerialSeriesPlan({
    required this.root,
    required this.assignments,
    required this.existingIndexes,
  });

  /// Το κείμενο του προτύπου χωρίς τον τελεστή και τα διαχωριστικά του —
  /// χρησιμεύει για να αναγνωριστεί η υπάρχουσα σειρά.
  final String root;

  /// Κωδικός εξοπλισμού → νέος σειριακός, με τη σειρά του κωδικού.
  final List<({int code, String serial})> assignments;

  /// Αριθμοί της σειράς που υπάρχουν ήδη στη βάση και προσπεράστηκαν.
  final List<int> existingIndexes;

  bool get isEmpty => assignments.isEmpty;

  /// «Υπάρχουν ήδη 1 έως 10 · η αρίθμηση συνεχίζει από το 11», ή `null`
  /// όταν η σειρά ξεκινά από την αρχή.
  String? get continuationNote {
    if (existingIndexes.isEmpty || assignments.isEmpty) return null;
    final sorted = List<int>.from(existingIndexes)..sort();
    final range = sorted.length == 1
        ? '${sorted.first}'
        : '${sorted.first} έως ${sorted.last}';
    final firstNew = lampSerialSeriesMember(assignments.first.serial)?.index;
    return 'Υπάρχουν ήδη $range · η αρίθμηση συνεχίζει από το '
        '${firstNew ?? sorted.last + 1}';
  }
}

/// Χτίζει την αρίθμηση για μια ομάδα διπλότυπων.
///
/// Το [takenSerials] είναι όλοι οι σειριακοί του **ίδιου μοντέλου**: η
/// μοναδικότητα στη Λάμπα ισχύει ανά μοντέλο, και ένας αριθμός που υπάρχει
/// ήδη προσπερνιέται αντί να πατηθεί.
LampSerialSeriesPlan lampBuildSerialSeries({
  required String template,
  required Iterable<int> equipmentCodes,
  required Iterable<String> takenSerials,
}) {
  if (!lampSeriesTemplateIsValid(template)) {
    return const LampSerialSeriesPlan(
      root: '',
      assignments: <({int code, String serial})>[],
      existingIndexes: <int>[],
    );
  }
  final codes = List<int>.from(equipmentCodes)..sort();
  String render(int index) =>
      template.replaceAll(kLampSeriesCounterToken, '$index');

  // Η ρίζα βγαίνει από το ίδιο το πρότυπο, ώστε να αναγνωρίζεται η σειρά
  // ακόμη κι όταν ο χρήστης έγραψε κάτι εντελώς δικό του.
  final root = lampSerialSeriesRoot(render(1));

  final taken = <String>{
    for (final value in takenSerials) value.trim().toLowerCase(),
  };
  final existing = <int>[
    for (final value in takenSerials)
      if (lampSerialSeriesMember(value) case final member?)
        if (member.root.trim().toLowerCase() == root.toLowerCase())
          member.index,
  ];

  final assignments = <({int code, String serial})>[];
  var next = 1;
  for (final code in codes) {
    var candidate = render(next);
    // Προσπερνά αριθμούς που κρατά ήδη άλλο μηχάνημα του ίδιου μοντέλου.
    while (taken.contains(candidate.trim().toLowerCase())) {
      next++;
      candidate = render(next);
    }
    assignments.add((code: code, serial: candidate.trim()));
    taken.add(candidate.trim().toLowerCase());
    next++;
  }

  return LampSerialSeriesPlan(
    root: root,
    assignments: assignments,
    existingIndexes: existing,
  );
}
