/// Τι διαβάζει ο χειριστής όταν τελειώσει ένα αντίγραφο.
///
/// Καθαρός υπολογισμός, χωρίς δίσκο και χωρίς ρυθμίσεις: δέχεται **τι μπήκε
/// πράγματι** και **τι δεν μπήκε**, και βγάζει μία πρόταση.
///
/// **Γιατί ξεχωριστό αρχείο:** το μήνυμα ήταν το τελευταίο κομμάτι μιας
/// μεθόδου 210 γραμμών, και γι' αυτό ακριβώς είχε καταφέρει να λέει ψέματα —
/// η λίστα περιεχομένων χτιζόταν από τις **ρυθμίσεις** αντί από το
/// αποτέλεσμα, και κανένα τεστ δεν μπορούσε να το πιάσει γιατί δεν υπήρχε
/// τρόπος να ρωτηθεί το μήνυμα χωρίς να τρέξει ολόκληρο αντίγραφο.
library;

/// Τι κατάφερε να μπει από ένα φορητό κομμάτι.
///
/// Δύο αριθμοί, όχι σημαία: η διαφορά ανάμεσα σε «μπήκαν όλα», «μπήκαν τα
/// μισά» και «δεν υπήρχε τίποτα» είναι ακριβώς αυτό που έλειπε από το μήνυμα.
class PortablePartOutcome {
  const PortablePartOutcome({required this.added, required this.failed});

  /// Κανένα αρχείο δεν βρέθηκε — ούτε καν για να αποτύχει.
  const PortablePartOutcome.nothingFound() : added = 0, failed = 0;

  final int added;
  final int failed;
}

/// Πού καταλήγει ένα φορητό κομμάτι: στα περιεχόμενα, στα ελλείποντα, ή και
/// στα δύο.
class PortablePartVerdict {
  const PortablePartVerdict({this.included, this.missing});

  /// Η γραμμή για τη λίστα περιεχομένων· `null` όταν δεν μπήκε τίποτα.
  final String? included;

  /// Η γραμμή για τα ελλείποντα· `null` όταν μπήκαν όλα.
  final String? missing;
}

/// Κρίνει ένα φορητό κομμάτι από το **αποτέλεσμα** της συσκευασίας του.
///
/// Ο κανόνας που επιβάλλει, και ο λόγος που ζει εδώ και όχι μέσα στη ροή: η
/// λίστα περιεχομένων γράφεται από ό,τι μπήκε πράγματι, ποτέ από τη ρύθμιση
/// που το ζήτησε. Όσο η απόφαση ήταν ένα `included.add(...)` δίπλα σε μια
/// συνάρτηση που δεν επέστρεφε τίποτα, το μήνυμα δήλωνε «εικόνες χαρτών» και
/// για άδειο φάκελο και για κλειδωμένα αρχεία.
///
/// Το [emptyReason] γράφεται στη γλώσσα του κομματιού («δεν βρέθηκε καμία»
/// για εικόνες, «δεν βρέθηκε κανένα» για εικονίδια): ο χρήστης το ζήτησε και
/// δικαιούται να μάθει ότι δεν υπήρχε — μπορεί να σημαίνει ότι κάτι χάθηκε.
PortablePartVerdict judgePortablePart({
  required String label,
  required String emptyReason,
  required PortablePartOutcome outcome,
}) {
  if (outcome.added == 0 && outcome.failed == 0) {
    return PortablePartVerdict(missing: '$label ($emptyReason)');
  }
  if (outcome.added == 0) {
    return PortablePartVerdict(
      missing: '$label (${_unreadPhrase(outcome.failed)})',
    );
  }
  if (outcome.failed == 0) return PortablePartVerdict(included: label);
  // Μπήκαν κάποια και έλειψαν κάποια: το κομμάτι δηλώνεται ως περιεχόμενο —
  // υπάρχει μέσα — αλλά με τον αριθμό όσων λείπουν πάνω του, ώστε κανείς να
  // μη νομίζει ότι το αντίγραφο είναι πλήρες.
  return PortablePartVerdict(
    included: '$label (${_missedPhrase(outcome.failed)})',
  );
}

// Το ρήμα συμφωνεί με τον αριθμό: «1 αρχείο δεν μπήκε», όχι «δεν μπήκαν».
String _missedPhrase(int count) =>
    count == 1 ? '1 αρχείο δεν μπήκε' : '$count αρχεία δεν μπήκαν';

String _unreadPhrase(int count) =>
    count == 1 ? '1 αρχείο δεν διαβάστηκε' : '$count αρχεία δεν διαβάστηκαν';

/// Συνθέτει το μήνυμα ολοκλήρωσης.
///
/// - [isFull]: βγήκε πλήρες αντίγραφο (`.zip` με τα φορητά) ή γρήγορο (`.db`).
/// - [wantsBundle]: ο χρήστης **ζήτησε** φορητά· χρησιμεύει μόνο για να
///   εξηγηθεί γιατί ένα γρήγορο αντίγραφο ήταν σωστή απόφαση και όχι παράλειψη.
/// - [includedParts]: ό,τι μπήκε πράγματι μέσα, με τα λόγια του χρήστη.
/// - [missingParts]: ό,τι ζητήθηκε αλλά δεν μπήκε, με την αιτία μαζί.
String buildBackupCompletionMessage({
  required bool isFull,
  required bool wantsBundle,
  required List<String> includedParts,
  required List<String> missingParts,
}) {
  final tail = includedParts.isEmpty ? '' : ' (${includedParts.join(', ')})';

  final headline = isFull
      ? 'Το πλήρες αντίγραφο ολοκληρώθηκε$tail.'
      : (wantsBundle
            ? 'Το γρήγορο αντίγραφο ολοκληρώθηκε — τα φορητά αρχεία δεν '
                  'έχουν αλλάξει από το τελευταίο πλήρες.'
            : 'Το αντίγραφο ολοκληρώθηκε.');

  if (missingParts.isEmpty) return headline;
  return '$headline Δεν μπήκε: ${missingParts.join('· ')}.';
}

/// Το μήνυμα ενός αντιγράφου που γράφτηκε αλλά δεν πέρασε τον έλεγχο.
///
/// Τρία πράγματα σε μία παράγραφο, με σταθερή σειρά: **τι** βρέθηκε, **τι
/// απέγινε** το αρχείο, και το ωμό κείμενο του σφάλματος για όποιον κληθεί να
/// βοηθήσει.
String buildBrokenBackupMessage({
  required String? reason,
  required bool wasMarked,
  required String? rawDetail,
}) {
  final head = reason?.trim().isNotEmpty == true
      ? reason!.trim()
      : 'Το αντίγραφο δεν πέρασε τον έλεγχο.';
  final fate = wasMarked
      ? 'Το αρχείο σημαδεύτηκε ως χαλασμένο.'
      : 'Το αρχείο έμεινε ως έχει.';
  final detail = rawDetail?.trim();

  final message = '$head $fate';
  if (detail == null || detail.isEmpty) return message;
  return '$message\n$detail';
}
