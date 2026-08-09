/// Οντότητες της Λάμπας που **δεν** έχουν συνδεδεμένο εξοπλισμό.
///
/// **Το πρόβλημα που λύνουν:** η αναζήτηση χτίζεται με `FROM equipment LEFT
/// JOIN …`, δηλαδή μία γραμμή ανά εξοπλισμό. Ό,τι δεν κρέμεται από εξοπλισμό
/// είναι αόρατο — στη `lampa.db` αυτό ήταν 360 εγγραφές, ανάμεσά τους 202
/// ιδιοκτήτες (40% του προσωπικού) με τηλέφωνα που δεν βρίσκονταν ποτέ.
///
/// **Συμβόλαιο (Διευθυντής 08/08/2026):** ΟΛΗ η πληροφορία στη βάση είναι
/// αναζητήσιμη· τίποτα δεν αποκλείεται.
library;

import '../../utils/search_text_normalizer.dart';
import 'lamp_reference_labels.dart';

/// Είδος οντότητας — καθορίζει εικονίδιο και επικεφαλίδα στην προβολή.
enum LampUnlinkedEntityKind {
  office('Γραφείο', 'γραφεία'),
  owner('Ιδιοκτήτης', 'ιδιοκτήτες'),
  model('Μοντέλο', 'μοντέλα'),
  contract('Σύμβαση', 'συμβάσεις');

  const LampUnlinkedEntityKind(this.singularLabel, this.pluralLabel);

  final String singularLabel;
  final String pluralLabel;
}

/// Κενά εξοπλισμού που μπορούν να ζητηθούν ως ομάδα.
///
/// Αφορούν **εξοπλισμό που υπάρχει** αλλά του λείπει δεσμός — αντίθετα από τις
/// [LampUnlinkedEntityKind], που είναι οντότητες χωρίς εξοπλισμό.
enum LampEquipmentGapKind {
  withoutOffice('Χωρίς γραφείο', 'office'),
  withoutOwner('Χωρίς ιδιοκτήτη', 'owner');

  const LampEquipmentGapKind(this.label, this.columnName);

  final String label;

  /// Η στήλη του `equipment` που πρέπει να είναι κενή.
  final String columnName;
}

/// Μία οντότητα χωρίς συνδεδεμένο εξοπλισμό, έτοιμη για προβολή και αναζήτηση.
class LampUnlinkedEntity {
  const LampUnlinkedEntity({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.normalizedText,
    this.isEmptyRecord = false,
    this.transferRow,
  });

  final LampUnlinkedEntityKind kind;

  /// Το αναγνωριστικό στον πίνακα προέλευσης (`office`, `owner`, …).
  final int id;

  /// Το όνομα της ίδιας της οντότητας — π.χ. «Διευθυντής Αιματολογικού».
  final String title;

  /// Πλαίσιο σε μία γραμμή — π.χ. «τμήμα=Αιματολογικό Εργαστήριο».
  final String subtitle;

  /// Όλα τα πεδία κανονικοποιημένα, για ταίριασμα ελεύθερου κειμένου.
  final String normalizedText;

  /// Η εγγραφή δεν κουβαλά κανένα στοιχείο επικοινωνίας ή ζωής.
  ///
  /// Ισχυρή ένδειξη καταλοίπου της παλιάς βάσης: στη `lampa.db` ήταν 110 από
  /// τους 202 ασύνδετους ιδιοκτήτες και 13 από τα 78 γραφεία. **Δεν εμποδίζει
  /// τίποτα** — η μεταφορά επιτρέπεται κανονικά· απλώς δεν προτείνεται.
  final bool isEmptyRecord;

  /// Η γραμμή με τα ονόματα στηλών που περιμένει ο οδηγός μεταφοράς.
  ///
  /// `null` για μοντέλα και συμβάσεις: δεν υπάρχουν ως οντότητες στην κανονική
  /// βάση, οπότε δεν έχουν πού να μεταφερθούν.
  final Map<String, Object?>? transferRow;

  bool get canTransfer => transferRow != null;
}

/// Τα SQL που φέρνουν τις ασύνδετες οντότητες ανά πίνακα.
///
/// Το `NOT IN (SELECT … WHERE … IS NOT NULL)` είναι υποχρεωτικό: με NULL μέσα
/// στο υποερώτημα, το `NOT IN` της SQLite επιστρέφει πάντα κενό σύνολο και η
/// λίστα θα έβγαινε σιωπηλά άδεια.
const Map<LampUnlinkedEntityKind, String> kLampUnlinkedEntitySql =
    <LampUnlinkedEntityKind, String>{
      // Το `owner_count` κρίνει αν το γραφείο είναι κενό: γραφείο χωρίς
      // εξοπλισμό αλλά με ανθρώπους μέσα είναι ζωντανό, όχι κατάλοιπο.
      LampUnlinkedEntityKind.office: '''
        SELECT f.office AS id, f.office_name, f.department_name,
               f.organization_name, f.building, f.level, f.phones, f.e_mail,
               (SELECT COUNT(*) FROM owners o WHERE o.office = f.office)
                 AS owner_count
        FROM offices f
        WHERE f.office NOT IN (
          SELECT office FROM equipment WHERE office IS NOT NULL
        )
        ORDER BY f.office_name, f.office
      ''',
      LampUnlinkedEntityKind.owner: '''
        SELECT o.owner AS id, o.last_name, o.first_name, o.phones, o.e_mail,
               f.office_name, f.department_name
        FROM owners o
        LEFT JOIN offices f ON f.office = o.office
        WHERE o.owner NOT IN (
          SELECT owner FROM equipment WHERE owner IS NOT NULL
        )
        ORDER BY o.last_name, o.first_name, o.owner
      ''',
      LampUnlinkedEntityKind.model: '''
        SELECT model AS id, model_name, manufacturer_name, category_name,
               subcategory_name
        FROM model
        WHERE model NOT IN (
          SELECT model FROM equipment WHERE model IS NOT NULL
        )
        ORDER BY model_name, model
      ''',
      LampUnlinkedEntityKind.contract: '''
        SELECT contract AS id, contract_name, supplier_name, category_name,
               start_date, end_date
        FROM contracts
        WHERE contract NOT IN (
          SELECT contract FROM equipment WHERE contract IS NOT NULL
        )
        ORDER BY contract_name, contract
      ''',
    };

/// Χτίζει την οντότητα προβολής από μία γραμμή του αντίστοιχου ερωτήματος.
///
/// Επιστρέφει `null` όταν λείπει αναγνωριστικό — μια εγγραφή χωρίς id δεν
/// μπορεί ούτε να προβληθεί ούτε να συνδεθεί με τίποτα.
LampUnlinkedEntity? buildLampUnlinkedEntity(
  LampUnlinkedEntityKind kind,
  Map<String, Object?> row,
) {
  final id = _toInt(row['id']);
  if (id == null) return null;

  final title = _titleFor(kind, row, id);
  final subtitle = _subtitleFor(kind, row);
  return LampUnlinkedEntity(
    kind: kind,
    id: id,
    title: title,
    subtitle: subtitle,
    normalizedText: _normalizedTextFor(kind, row, id),
    isEmptyRecord: lampUnlinkedIsEmptyRecord(kind, row),
    transferRow: lampUnlinkedTransferRow(kind, row),
  );
}

/// «Κενή εγγραφή»: τίποτα που να δείχνει ότι αντιστοιχεί σε κάτι υπαρκτό.
///
/// - **Ιδιοκτήτης** χωρίς τηλέφωνο και χωρίς email.
/// - **Γραφείο** χωρίς τηλέφωνο και χωρίς κανέναν άνθρωπο μέσα.
/// - **Μοντέλα και συμβάσεις** δεν κρίνονται: είναι κατάλογοι και ιστορικό,
///   όχι εγγραφές που «ζουν» ή «πέθαναν».
bool lampUnlinkedIsEmptyRecord(
  LampUnlinkedEntityKind kind,
  Map<String, Object?> row,
) {
  switch (kind) {
    case LampUnlinkedEntityKind.owner:
      return _nonEmpty(row['phones']) == null &&
          _nonEmpty(row['e_mail']) == null;
    case LampUnlinkedEntityKind.office:
      return _nonEmpty(row['phones']) == null &&
          (_toInt(row['owner_count']) ?? 0) == 0;
    case LampUnlinkedEntityKind.model:
    case LampUnlinkedEntityKind.contract:
      return false;
  }
}

/// Μεταφράζει τη γραμμή στα ονόματα στηλών που περιμένει ο οδηγός μεταφοράς.
///
/// Ο οδηγός χτίστηκε γύρω από τη γραμμή εξοπλισμού, όπου τα τηλέφωνα και τα
/// email έχουν πρόθεμα ανά οντότητα (`owner_phones`, `office_email`) ώστε να
/// μη συγκρούονται μεταξύ τους στο ίδιο ενιαίο `SELECT`. Οι δικές μας γραμμές
/// έρχονται από έναν πίνακα η καθεμία, οπότε λέγονται σκέτα `phones`/`e_mail`.
///
/// Επιστρέφει `null` για μοντέλα και συμβάσεις — δεν υπάρχουν ως οντότητες
/// στην κανονική βάση, άρα δεν έχουν πού να μεταφερθούν.
Map<String, Object?>? lampUnlinkedTransferRow(
  LampUnlinkedEntityKind kind,
  Map<String, Object?> row,
) {
  switch (kind) {
    case LampUnlinkedEntityKind.owner:
      return <String, Object?>{
        'owner': row['id'],
        'last_name': row['last_name'],
        'first_name': row['first_name'],
        'owner_phones': row['phones'],
        'owner_email': row['e_mail'],
        'office_name': row['office_name'],
        'department_name': row['department_name'],
      };
    case LampUnlinkedEntityKind.office:
      return <String, Object?>{
        'office': row['id'],
        'office_name': row['office_name'],
        'department_name': row['department_name'],
        'building': row['building'],
        'level': row['level'],
        'office_phones': row['phones'],
        'office_email': row['e_mail'],
      };
    case LampUnlinkedEntityKind.model:
    case LampUnlinkedEntityKind.contract:
      return null;
  }
}

String _titleFor(
  LampUnlinkedEntityKind kind,
  Map<String, Object?> row,
  int id,
) {
  switch (kind) {
    case LampUnlinkedEntityKind.office:
      // Ίδιος κανόνας με τη λίστα υποψηφίων: το όνομα του γραφείου πρώτο.
      final label = lampOfficeDisplayLabel(
        officeName: _text(row['office_name']),
        departmentName: _text(row['department_name']),
        organizationName: _text(row['organization_name']),
      );
      return label.isEmpty ? 'Γραφείο $id' : label.split(' · ').first;
    case LampUnlinkedEntityKind.owner:
      final name = <String>[
        ?_nonEmpty(row['last_name']),
        ?_nonEmpty(row['first_name']),
      ].join(' ');
      return name.isEmpty ? 'Ιδιοκτήτης $id' : name;
    case LampUnlinkedEntityKind.model:
      return _nonEmpty(row['model_name']) ??
          _nonEmpty(row['subcategory_name']) ??
          _nonEmpty(row['category_name']) ??
          'Μοντέλο $id';
    case LampUnlinkedEntityKind.contract:
      return _nonEmpty(row['contract_name']) ?? 'Σύμβαση $id';
  }
}

String _subtitleFor(LampUnlinkedEntityKind kind, Map<String, Object?> row) {
  final parts = <String>[];
  switch (kind) {
    case LampUnlinkedEntityKind.office:
      _add(parts, 'τμήμα', row['department_name']);
      final place = <String>[
        ?_nonEmpty(row['building']),
        ?_nonEmpty(row['level']),
      ].join(' ');
      if (place.isNotEmpty) parts.add('κτίριο=$place');
      _add(parts, 'τηλέφωνα', row['phones']);
    case LampUnlinkedEntityKind.owner:
      _add(parts, 'γραφείο', row['office_name']);
      _add(parts, 'τμήμα', row['department_name']);
      _add(parts, 'τηλέφωνα', row['phones']);
      _add(parts, 'email', row['e_mail']);
    case LampUnlinkedEntityKind.model:
      _add(parts, 'κατασκευαστής', row['manufacturer_name']);
      _add(parts, 'κατηγορία', row['category_name']);
    case LampUnlinkedEntityKind.contract:
      _add(parts, 'προμηθευτής', row['supplier_name']);
      _add(parts, 'κατηγορία', row['category_name']);
      _add(parts, 'λήξη', row['end_date']);
  }
  return parts.join(' · ');
}

/// Όλα τα πεδία της γραμμής σε ένα κανονικοποιημένο κείμενο, μαζί με το id.
///
/// Το id μπαίνει ώστε η αναζήτηση «186» να βρίσκει το γραφείο 186 — ο χρήστης
/// βλέπει αναγνωριστικά στους διαλόγους επίλυσης και τα ψάχνει αυτούσια.
String _normalizedTextFor(
  LampUnlinkedEntityKind kind,
  Map<String, Object?> row,
  int id,
) {
  final buffer = <String>['$id'];
  for (final entry in row.entries) {
    // Τα βοηθητικά πλήθη δεν είναι περιεχόμενο: χωρίς την εξαίρεση, η
    // αναζήτηση «3» θα έβρισκε κάθε γραφείο με τρεις ιδιοκτήτες.
    if (_nonSearchableColumns.contains(entry.key)) continue;
    final text = _text(entry.value);
    if (text != null && text.isNotEmpty) buffer.add(text);
  }
  return SearchTextNormalizer.normalizeForSearch(buffer.join(' '));
}

const Set<String> _nonSearchableColumns = <String>{'owner_count'};

/// Πεδία αναζήτησης που υπάρχουν **μόνο** πάνω σε εξοπλισμό.
///
/// Όταν ο χρήστης γεμίσει έστω ένα από αυτά, ζητά εξοπλισμό — καμία ασύνδετη
/// οντότητα δεν μπορεί να απαντήσει, οπότε η ενότητα μένει κενή αντί να
/// γεμίσει με άσχετα.
const Set<String> kLampEquipmentOnlySearchFields = <String>{
  'code',
  'description',
  'serialNo',
  'assetNo',
  'state',
};

/// Ποια είδη ασύνδετων οντοτήτων μπορεί να απαντήσουν σε κάθε πεδίο.
///
/// Το τηλέφωνο αφορά δύο είδη: το κρατούν και οι ιδιοκτήτες και τα γραφεία.
const Map<String, Set<LampUnlinkedEntityKind>> kLampUnlinkedFieldKinds =
    <String, Set<LampUnlinkedEntityKind>>{
      'owner': <LampUnlinkedEntityKind>{LampUnlinkedEntityKind.owner},
      'office': <LampUnlinkedEntityKind>{LampUnlinkedEntityKind.office},
      'model': <LampUnlinkedEntityKind>{LampUnlinkedEntityKind.model},
      'contract': <LampUnlinkedEntityKind>{LampUnlinkedEntityKind.contract},
      'phone': <LampUnlinkedEntityKind>{
        LampUnlinkedEntityKind.owner,
        LampUnlinkedEntityKind.office,
      },
    };

/// Ταιριάζει η οντότητα με την αναζήτηση ανά πεδίο;
///
/// Το [normalizedFilters] είναι «κλειδί πεδίου → κανονικοποιημένη τιμή», μόνο
/// για τα πεδία που ο χρήστης γέμισε πραγματικά.
bool lampUnlinkedMatchesFields(
  LampUnlinkedEntity entity,
  Map<String, String> normalizedFilters,
) {
  if (normalizedFilters.isEmpty) return false;
  for (final field in normalizedFilters.keys) {
    if (kLampEquipmentOnlySearchFields.contains(field)) return false;
  }
  for (final entry in normalizedFilters.entries) {
    final kinds = kLampUnlinkedFieldKinds[entry.key];
    // Άγνωστο πεδίο: δεν μπορούμε να το εγγυηθούμε, άρα δεν ταιριάζει.
    if (kinds == null || !kinds.contains(entity.kind)) return false;
    if (!lampNormalizedTextContainsAll(entity.normalizedText, entry.value)) {
      return false;
    }
  }
  return true;
}

/// Περιέχει το κείμενο **όλες** τις λέξεις του ερωτήματος;
bool lampNormalizedTextContainsAll(String normalizedText, String query) {
  for (final token in query.split(' ')) {
    if (token.isEmpty) continue;
    if (!normalizedText.contains(token)) return false;
  }
  return true;
}

void _add(List<String> parts, String label, Object? value) {
  final text = _nonEmpty(value);
  if (text != null) parts.add('$label=$text');
}

String? _text(Object? value) => value?.toString().trim();

String? _nonEmpty(Object? value) {
  final text = _text(value);
  return (text == null || text.isEmpty) ? null : text;
}

int? _toInt(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');
