/// Ετικέτες οντοτήτων αναφοράς της Λάμπας (γραφείο, μοντέλο, σύμβαση).
///
/// **Συμβόλαιο:** η ετικέτα ξεκινά από το όνομα της **ίδιας** της οντότητας·
/// τα ονόματα γονέων μπαίνουν ως πλαίσιο δίπλα, με ετικέτα, ποτέ στη θέση της.
///
/// Ο λόγος είναι πρακτικός: οι ετικέτες τροφοδοτούν λίστες υποψηφίων στη
/// χειροκίνητη επίλυση. Αν επικεφαλής μπει το όνομα του γονέα, όλα τα παιδιά
/// του ίδιου γονέα γράφονται πανομοιότυπα και ο χρήστης μένει χωρίς κριτήριο
/// επιλογής — πέντε διαφορετικά γραφεία του Αιματολογικού εμφανίζονταν όλα ως
/// «Αιματολογικό Εργαστήριο».
library;

/// Το πρώτο κείμενο που λέει κάτι: μη κενό και όχι σκέτος αριθμός.
///
/// Ένα «12» ως όνομα δεν βοηθά κανέναν να αναγνωρίσει εγγραφή, οπότε
/// προσπερνιέται προς όφελος του επόμενου υποψηφίου.
String? lampFirstInformativeText(String? a, String? b, String? c) {
  for (final candidate in <String?>[a, b, c]) {
    final text = candidate?.trim();
    if (text == null || text.isEmpty) continue;
    if (lampLooksNumericOnly(text)) continue;
    return text;
  }
  return null;
}

bool lampLooksNumericOnly(String value) =>
    RegExp(r'^[0-9\-\s]+$').hasMatch(value.trim());

/// Ετικέτα υπαλλήλου: «‹Επώνυμο Όνομα› · γραφείο=‹γραφείο›».
///
/// Το γραφείο είναι συχνά το **μόνο** κριτήριο επιλογής όταν δύο υποψήφιοι
/// έχουν παρόμοιο όνομα: «191 · Παπαβασιλείου Τζένη» και «340 · Παπαβασιλείου
/// Ελένη» ξεχωρίζουν αμέσως μόλις φανεί πού δουλεύει ο καθένας.
///
/// Ίδιο μοτίβο με [lampOfficeDisplayLabel]: ταυτότητα πρώτα, πλαίσιο δίπλα.
String lampOwnerDisplayLabel({
  String? lastName,
  String? firstName,
  String? officeName,
  String? departmentName,
}) {
  final name = <String>[
    ?_trimmedOrNull(lastName),
    ?_trimmedOrNull(firstName),
  ].join(' ');
  // Το γραφείο είναι πιο συγκεκριμένο από το τμήμα· το τμήμα μπαίνει μόνο
  // όταν δεν υπάρχει γραφείο, ώστε η ετικέτα να μένει σύντομη.
  final place =
      _trimmedOrNull(officeName) ?? _trimmedOrNull(departmentName);
  if (place == null || place.isEmpty) return name;
  if (name.isEmpty) return 'γραφείο=$place';
  return '$name · γραφείο=$place';
}

String? _trimmedOrNull(String? value) {
  final text = value?.trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// Ετικέτα γραφείου: «‹όνομα γραφείου› · τμήμα=‹τμήμα›».
///
/// Το τμήμα είναι πλαίσιο, όχι ταυτότητα — πολλά γραφεία το μοιράζονται. Όταν
/// το γραφείο ονομάζεται όπως το τμήμα του, η επανάληψη παραλείπεται.
String lampOfficeDisplayLabel({
  String? officeName,
  String? departmentName,
  String? organizationName,
}) {
  final baseName = lampFirstInformativeText(
    officeName,
    departmentName,
    organizationName,
  );
  final department = departmentName?.trim();
  final parts = <String>[
    ?baseName,
    if (department != null && department.isNotEmpty && department != baseName)
      'τμήμα=$department',
  ];
  if (parts.isEmpty) {
    return officeName ?? departmentName ?? organizationName ?? '';
  }
  return parts.join(' · ');
}
