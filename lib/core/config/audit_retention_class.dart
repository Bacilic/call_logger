/// Σε ποια κλάση διατήρησης ανήκει μια εγγραφή του Ιστορικού.
///
/// **Η αρχή:** σβήνεται ό,τι **επαναλαμβάνεται**, κρατιέται ό,τι είναι **η
/// μόνη μαρτυρία**.
///
/// Μια τροποποίηση τμήματος δεν χάνεται πραγματικά όταν σβηστεί: η τρέχουσα
/// κατάσταση του τμήματος είναι εκεί, στον πίνακά του. Η **δημιουργία** όμως
/// είναι διαφορετική — οι πίνακες του Καταλόγου δεν κρατούν δική τους
/// υπογραφή, οπότε η γραμμή του Ιστορικού είναι η μοναδική απάντηση στο
/// «ποιος το έφτιαξε και πότε». Το ίδιο και η **διαγραφή**: μόλις σβηστεί,
/// τίποτα δεν θυμάται ότι η οντότητα υπήρξε ποτέ.
///
/// Καθαρός υπολογισμός: καμία βάση, καμία ρύθμιση. Η ίδια κρίση οφείλει να
/// δίνει το ίδιο αποτέλεσμα στην προεπισκόπηση και στη διαγραφή, αλλιώς ο
/// χειριστής εγκρίνει ένα νούμερο και εκτελείται άλλο.
library;

/// Οι τρεις κλάσεις, από την πιο πολύτιμη προς την πιο αναλώσιμη.
enum AuditRetentionClass {
  /// **Δεν σβήνεται ποτέ**, όποιο όριο κι αν οριστεί.
  ///
  /// Γεννήσεις και θάνατοι οντοτήτων του Καταλόγου, και κάθε επέμβαση
  /// επιδιόρθωσης στα δεδομένα.
  permanent,

  /// Αλλαγές σε οντότητες που ζουν ακόμη.
  ///
  /// Η τρέχουσα κατάσταση υπάρχει στον πίνακα της οντότητας· εδώ ζει μόνο η
  /// διαδρομή προς αυτήν. Χρήσιμη για μήνες, όχι για χρόνια.
  operational,

  /// Ημερήσια κίνηση: κλήσεις, εκκρεμότητες, αντίγραφα ασφαλείας.
  ///
  /// Πληθαίνει καθημερινά και παλιώνει γρήγορα. Οι ίδιες οι κλήσεις και οι
  /// εκκρεμότητες ζουν στους δικούς τους πίνακες με τις ημερομηνίες τους — το
  /// Ιστορικό εδώ είναι δεύτερο αντίγραφο του «πότε».
  volatile,
}

/// Τα είδη οντοτήτων των οποίων η γέννηση και ο θάνατος είναι αναντικατάστατα.
///
/// Είναι ο Κατάλογος: ό,τι ζει πολλά χρόνια και αναφέρεται από αλλού. Οι
/// κλήσεις και οι εκκρεμότητες **δεν** ανήκουν εδώ — έχουν δικές τους
/// ημερομηνίες στους πίνακές τους.
const Set<String> kCatalogEntityTypes = {
  'user',
  'department',
  'equipment',
  'phone',
  'category',
  'operator',
};

/// Οι λέξεις με τις οποίες ξεκινά μια ενέργεια γέννησης ή θανάτου.
///
/// Ταιριάζουν ως **πρόθεμα** και όχι ως ολόκληρη τιμή, γιατί η ενέργεια
/// περιγράφει και το είδος: «ΔΗΜΙΟΥΡΓΙΑ ΥΠΑΛΛΗΛΟΥ», «ΔΙΑΓΡΑΦΗ». Ένα νέο είδος
/// οντότητας κληρονομεί τον κανόνα χωρίς να χρειαστεί να προστεθεί εδώ.
const List<String> kLifecycleActionPrefixes = [
  'ΔΗΜΙΟΥΡΓΙΑ',
  'ΔΙΑΓΡΑΦΗ',
  'ΕΠΙΔΙΟΡΘΩΣΗ',
];

/// Τα είδη που είναι εξ ορισμού ημερήσια κίνηση.
const Set<String> kVolatileEntityTypes = {'call', 'task', 'backup'};

/// Κατατάσσει μια εγγραφή, από τα δύο πεδία που έχει ήδη το Ιστορικό.
AuditRetentionClass classifyAuditRow({
  required String? entityType,
  required String? action,
}) {
  final type = (entityType ?? '').trim();
  final act = (action ?? '').trim().toUpperCase();

  final isLifecycle = kLifecycleActionPrefixes.any(act.startsWith);

  // Η επιδιόρθωση ακεραιότητας είναι μαρτυρία επέμβασης όποιο κι αν είναι το
  // είδος — ακόμη και σε κλήση. Μπαίνει πριν από κάθε άλλο κριτήριο.
  if (act.startsWith('ΕΠΙΔΙΟΡΘΩΣΗ')) return AuditRetentionClass.permanent;

  if (kCatalogEntityTypes.contains(type) && isLifecycle) {
    return AuditRetentionClass.permanent;
  }

  if (kVolatileEntityTypes.contains(type)) return AuditRetentionClass.volatile;

  return AuditRetentionClass.operational;
}

/// Η ελληνική ετικέτα της κλάσης, όπως τη διαβάζει ο χειριστής.
String auditRetentionClassLabel(AuditRetentionClass value) {
  switch (value) {
    case AuditRetentionClass.permanent:
      return 'Δημιουργίες και διαγραφές Καταλόγου';
    case AuditRetentionClass.operational:
      return 'Αλλαγές σε καρτέλες';
    case AuditRetentionClass.volatile:
      return 'Κλήσεις, εκκρεμότητες, αντίγραφα';
  }
}

/// Μία πρόταση για το τι σημαίνει η κλάση — για την οθόνη ρυθμίσεων.
String auditRetentionClassDescription(AuditRetentionClass value) {
  switch (value) {
    case AuditRetentionClass.permanent:
      return 'Η μόνη απάντηση στο «ποιος το έφτιαξε». Δεν σβήνεται ποτέ.';
    case AuditRetentionClass.operational:
      return 'Η διαδρομή μιας καρτέλας ως τη σημερινή της μορφή.';
    case AuditRetentionClass.volatile:
      return 'Ημερήσια κίνηση — οι ίδιες οι κλήσεις μένουν άθικτες.';
  }
}

/// Το κομμάτι SQL που επιλέγει τις εγγραφές **μιας** κλάσης.
///
/// Ζει δίπλα στην [classifyAuditRow] επίτηδες και όχι στο repository: οι δύο
/// είναι η ίδια απόφαση σε δύο γλώσσες, και αν αποκλίνουν η προεπισκόπηση θα
/// υπόσχεται άλλα από όσα σβήνει η εκκαθάριση. Το τεστ που τις συγκρίνει
/// πάνω σε πραγματικά δεδομένα είναι ο φρουρός αυτής της συμφωνίας.
({String sql, List<Object?> args}) auditRetentionClassClause(
  AuditRetentionClass value,
) {
  final catalog = List<String>.from(kCatalogEntityTypes);
  final volatileTypes = List<String>.from(kVolatileEntityTypes);
  final catalogMarks = List.filled(catalog.length, '?').join(',');
  final volatileMarks = List.filled(volatileTypes.length, '?').join(',');

  // Ίδια σειρά κριτηρίων με την [classifyAuditRow]: πρώτα η επιδιόρθωση.
  const repair = "UPPER(TRIM(COALESCE(action,''))) LIKE 'ΕΠΙΔΙΟΡΘΩΣΗ%'";
  const lifecycle =
      "(UPPER(TRIM(COALESCE(action,''))) LIKE 'ΔΗΜΙΟΥΡΓΙΑ%' "
      "OR UPPER(TRIM(COALESCE(action,''))) LIKE 'ΔΙΑΓΡΑΦΗ%' "
      "OR UPPER(TRIM(COALESCE(action,''))) LIKE 'ΕΠΙΔΙΟΡΘΩΣΗ%')";
  final inCatalog = "TRIM(COALESCE(entity_type,'')) IN ($catalogMarks)";
  final inVolatile = "TRIM(COALESCE(entity_type,'')) IN ($volatileMarks)";

  final permanentSql = '($repair OR ($inCatalog AND $lifecycle))';
  final permanentArgs = <Object?>[...catalog];

  switch (value) {
    case AuditRetentionClass.permanent:
      return (sql: permanentSql, args: permanentArgs);
    case AuditRetentionClass.volatile:
      return (
        sql: 'NOT $permanentSql AND $inVolatile',
        args: <Object?>[...permanentArgs, ...volatileTypes],
      );
    case AuditRetentionClass.operational:
      return (
        sql: 'NOT $permanentSql AND NOT $inVolatile',
        args: <Object?>[...permanentArgs, ...volatileTypes],
      );
  }
}
