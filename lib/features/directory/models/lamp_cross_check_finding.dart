import 'catalog_validation_finding.dart';

/// Ποιος έλεγχος γέννησε το εύρημα — καθορίζει εικονίδιο και τίτλο.
enum LampCrossCheckKind {
  userNameSpelling,
  userAmbiguousMatch,
  userMissing,
  userDepartment,
  userPhoneOnlyInLamp,
  userPhoneOnlyInCatalog,
  departmentNameSpelling,
  departmentMissing,
  departmentPhoneOnlyInLamp,
  departmentPhoneOnlyInCatalog,
  equipmentMissing,
  equipmentRetired,
  equipmentType,
  equipmentOwner,
  equipmentDepartment,
}

/// Μία απόκλιση ανάμεσα στον Κατάλογο και τη Λάμπα.
///
/// **Κουβαλά και τις δύο πλευρές.** Η Λάμπα δεν είναι «σωστή» ούτε «λάθος»:
/// από τότε που πάγωσε, οι δύο βάσεις απαντούν σε διαφορετική ερώτηση. Το
/// εύρημα δείχνει τι λέει η καθεμιά και ο χρήστης αποφασίζει — γι' αυτό η
/// τιμή της Λάμπας ζει δίπλα στην τιμή του Καταλόγου, όχι μέσα στο μήνυμα.
class LampCrossCheckFinding {
  const LampCrossCheckFinding({
    required this.kind,
    required this.title,
    required this.entityKind,
    required this.entityId,
    required this.entityLabel,
    required this.focusedField,
    required this.catalogValue,
    this.lampValue,
    this.note = '',
  });

  final LampCrossCheckKind kind;

  /// Τι συμβαίνει, σε μία γραμμή («Ο κωδικός 5151 δεν υπάρχει στη Λάμπα»).
  final String title;

  /// Η εγγραφή του **Καταλόγου** που ανοίγει με το κλικ. Η Λάμπα διαβάζεται
  /// μόνο, άρα δεν υπάρχει ποτέ διέξοδος προς τη δική της καρτέλα.
  final CatalogEntityKind entityKind;
  final int entityId;

  /// Πώς αναγνωρίζει ο χρήστης την εγγραφή («Ψαρρά Σοφία», «Εξοπλισμός 3257»).
  final String entityLabel;

  /// Κλειδί εστίασης του διαλόγου επεξεργασίας.
  final String focusedField;

  /// Τι λέει ο Κατάλογος.
  final String catalogValue;

  /// Τι λέει η Λάμπα. `null` όταν η Λάμπα δεν έχει τίποτα να πει — τότε η
  /// κάρτα δείχνει μία μόνο πλευρά αντί για άδειο κουτί.
  final String? lampValue;

  /// Γιατί το λέει («Το μικρό όνομα διαφέρει σε 1 γράμμα»).
  final String note;
}
