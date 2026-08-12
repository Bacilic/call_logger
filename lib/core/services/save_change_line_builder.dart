import 'lansweeper_department_accounts.dart';

/// Πώς ονομάζεται ένα πεδίο-συλλογή στις τρεις θέσεις που το χρειάζεται το
/// μήνυμα αποθήκευσης: «Προστέθηκε **τηλέφωνο**», «Προστέθηκαν **τηλέφωνα**»,
/// «Επεξεργασία **τηλεφώνου**».
///
/// Όταν ο ενικός ταυτίζεται με τον πληθυντικό, η λέξη είναι περιληπτική
/// («εξοπλισμός») και μένει σε ενικό ακόμη και για πολλά στοιχεία — έτσι το
/// λέει ο χρήστης, έτσι το γράφουμε.
typedef CollectionNoun = ({String singular, String plural, String genitive});

/// Ένα στοιχείο συλλογής, χωρισμένο σε ταυτότητα και εμφάνιση.
///
/// Η [key] είναι με τι ταιριάζουμε παλιό και νέο (αναγνωριστικό, αριθμός,
/// κωδικός)· το [display] είναι τι διαβάζει ο χρήστης. Χωρίζονται επίτηδες:
/// ένας λογαριασμός Lansweeper μπορεί να κρατήσει το αναγνωριστικό του και να
/// αλλάξει ετικέτα — αλλαγή που θα ήταν αόρατη αν συγκρίναμε μόνο εμφανίσεις.
class SaveCollectionItem {
  const SaveCollectionItem({required this.key, required this.display});

  final String key;
  final String display;
}

const Map<String, CollectionNoun> _collectionNouns = <String, CollectionNoun>{
  'lansweeper_usernames': (
    singular: 'αναγνωριστικό Lansweeper',
    plural: 'αναγνωριστικά Lansweeper',
    genitive: 'αναγνωριστικού Lansweeper',
  ),
  'phones': (
    singular: 'τηλέφωνο',
    plural: 'τηλέφωνα',
    genitive: 'τηλεφώνου',
  ),
  'shared_phones': (
    singular: 'κοινόχρηστο τηλέφωνο',
    plural: 'κοινόχρηστα τηλέφωνα',
    genitive: 'κοινόχρηστου τηλεφώνου',
  ),
  'shared_equipment_codes': (
    singular: 'εξοπλισμός',
    plural: 'εξοπλισμός',
    genitive: 'εξοπλισμού',
  ),
};

/// Τα πεδία που κρατούν την **ταυτότητα** της εγγραφής — η αλλαγή τους δεν
/// είναι μια αλλαγή σαν τις άλλες, είναι μετονομασία.
///
/// Ο υπάλληλος έχει δύο: το όνομα και το επώνυμο ενώνονται σε **μία** γραμμή,
/// γιατί «όνομα: Βάσω → Θάνια» και «επώνυμο: — → —» δίπλα-δίπλα διαβάζονται
/// σαν δύο ανεξάρτητα γεγονότα ενώ είναι ένα.
const Map<String, List<String>> _identityFields = <String, List<String>>{
  'department': ['name'],
  'category': ['name'],
  'equipment': ['code_equipment'],
  'user': ['first_name', 'last_name'],
};

/// `true` όταν το πεδίο περιγράφεται καλύτερα ως «τι μπήκε / τι βγήκε» παρά
/// ως «παλιό → νέο».
bool isCollectionField(String field) => _collectionNouns.containsKey(field);

/// Τα πεδία που καταναλώνει η [buildRenameLine].
///
/// Ο βρόχος των υπόλοιπων αλλαγών οφείλει να τα προσπεράσει· αλλιώς η ίδια
/// αλλαγή ανακοινώνεται δύο φορές, με δύο διαφορετικές διατυπώσεις.
Set<String> renameFieldsFor(String entityType) =>
    (_identityFields[entityType.trim()] ?? const <String>[]).toSet();

/// «Μετονομασία: Λοιμώξεων → Γραφείο Λοιμώξεων», ή `null` όταν η ταυτότητα
/// δεν άλλαξε (ή η οντότητα δεν έχει όνομα, όπως η κλήση).
String? buildRenameLine({
  required String entityType,
  required Map<String, dynamic> oldMap,
  required Map<String, dynamic> newMap,
}) {
  final fields = _identityFields[entityType.trim()];
  if (fields == null) return null;

  String joined(Map<String, dynamic> map) => fields
      .map((f) => (map[f] ?? '').toString().trim())
      .where((s) => s.isNotEmpty)
      .join(' ');

  final before = joined(oldMap);
  final after = joined(newMap);
  if (before.isEmpty || after.isEmpty || before == after) return null;
  return 'Μετονομασία: $before → $after';
}

/// Οι γραμμές που περιγράφουν τι έγινε σε μια συλλογή — μόνο όσες ισχύουν.
///
/// Ό,τι έμεινε ίδιο δεν αναφέρεται καθόλου: το ζητούμενο είναι να διαβάζεις τη
/// **διαφορά**, όχι να ψάχνεις ποιο από τα δέκα στοιχεία λείπει από τη δεξιά
/// λίστα.
List<String> buildCollectionChangeLines({
  required String field,
  required dynamic oldValue,
  required dynamic newValue,
}) {
  final noun = _collectionNouns[field];
  if (noun == null) return const [];

  final oldItems = _collectionItems(field, oldValue);
  final newItems = _collectionItems(field, newValue);
  final oldByKey = {for (final i in oldItems) i.key: i};
  final newByKey = {for (final i in newItems) i.key: i};

  final lines = <String>[];

  // Ίδια ταυτότητα, άλλη εμφάνιση: ο χρήστης πείραξε την ετικέτα, δεν
  // αντικατέστησε τον λογαριασμό.
  for (final item in oldItems) {
    final after = newByKey[item.key];
    if (after != null && after.display != item.display) {
      lines.add(
        'Επεξεργασία ${noun.genitive}: ${item.display} → ${after.display}',
      );
    }
  }

  final removed = [
    for (final i in oldItems)
      if (!newByKey.containsKey(i.key)) i,
  ];
  final added = [
    for (final i in newItems)
      if (!oldByKey.containsKey(i.key)) i,
  ];

  // Ένα έφυγε και ένα ήρθε: σχεδόν πάντα διόρθωση, όχι δύο άσχετες κινήσεις.
  // Το λέμε ως μία γραμμή γιατί έτσι το σκέφτηκε ο χρήστης όταν το έκανε.
  if (removed.length == 1 && added.length == 1) {
    lines.add(
      'Επεξεργασία ${noun.genitive}: '
      '${removed.single.display} → ${added.single.display}',
    );
    return lines;
  }

  if (added.isNotEmpty) {
    lines.add(
      '${_verb('Προστέθηκε', 'Προστέθηκαν', added.length, noun)}: '
      '${added.map((i) => i.display).join(', ')}',
    );
  }
  if (removed.isNotEmpty) {
    lines.add(
      '${_verb('Αφαιρέθηκε', 'Αφαιρέθηκαν', removed.length, noun)}: '
      '${removed.map((i) => i.display).join(', ')}',
    );
  }

  return lines;
}

String _verb(String singular, String plural, int count, CollectionNoun noun) {
  final isMassNoun = noun.singular == noun.plural;
  return (isMassNoun || count == 1)
      ? '$singular ${noun.singular}'
      : '$plural ${noun.plural}';
}

/// Κανονικοποιεί την αποθηκευμένη τιμή σε στοιχεία, ό,τι μορφή κι αν έχει.
List<SaveCollectionItem> _collectionItems(String field, dynamic value) {
  if (field == 'lansweeper_usernames') {
    return [
      for (final account in decodeLansweeperAccounts(value?.toString()))
        SaveCollectionItem(
          key: account.username,
          display: account.displayLabel,
        ),
    ];
  }

  final parts = value is List
      ? value.map((e) => '$e')
      : (value?.toString() ?? '').split(',');

  return [
    for (final part in parts)
      if (part.trim().isNotEmpty)
        SaveCollectionItem(key: part.trim(), display: part.trim()),
  ];
}
