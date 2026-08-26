/// Η γέφυρα κειμένου ανάμεσα σε μια κλήση και την εκκρεμότητα που γεννά.
///
/// **Το πρόβλημα που λύνει:** η λύση γραφόταν μία φορά και έμενε στη μία μόνο
/// πλευρά του δεσμού — ο χρήστης έπρεπε να τη γράψει δεύτερη φορά για να τη
/// βλέπει και από την άλλη.
///
/// **Οι δύο κατευθύνσεις δεν είναι συμμετρικές, επίτηδες:**
///
/// 1. **Κλήση → εκκρεμότητα** (τη στιγμή της γέννησης): η «Λύση» της κλήσης
///    είναι συνήθως τα **πρώτα βήματα**, όχι η τελική απάντηση — «Να γίνει
///    αίτημα στην DataMed». Ανήκει λοιπόν στις **σημειώσεις** της
///    εκκρεμότητας, με ρητή ένδειξη, και ΟΧΙ στη δική της λύση: εκείνη
///    κρατιέται για το πραγματικό φινάλε.
/// 2. **Εκκρεμότητα → κλήση** (τη στιγμή του κλεισίματος): η τελική λύση
///    **προστίθεται** στη λύση της κλήσης αντί να την αντικαταστήσει, ώστε η
///    αλυσίδα «από πού ξεκίνησε → πώς έκλεισε» να μένει ολόκληρη σε μία ματιά.
library;

/// Η ένδειξη που συνοδεύει τη λύση της κλήσης μέσα στις σημειώσεις.
const String kCallSolutionNotePrefix = 'Λύση:';

/// Η ένδειξη που συνοδεύει τη λύση της εκκρεμότητας μέσα στη λύση της κλήσης.
const String kTaskSolutionCallPrefix = 'Από την εκκρεμότητα:';

/// Οι σημειώσεις της νέας εκκρεμότητας: περιγραφή της κλήσης + η λύση της.
///
/// Κενή λύση δεν αφήνει ίχνος — ούτε ετικέτα, ούτε κενές γραμμές.
String taskNotesFromCall({required String notes, required String solution}) {
  final body = notes.trim();
  final extra = solution.trim();
  if (extra.isEmpty) return body;
  final marked = '$kCallSolutionNotePrefix $extra';
  return body.isEmpty ? marked : '$body\n\n$marked';
}

/// Η λύση της κλήσης αφού κλείσει η συνδεδεμένη εκκρεμότητα.
///
/// Επιστρέφει `null` όταν δεν υπάρχει τίποτα να γραφτεί — είτε επειδή η λύση
/// της εκκρεμότητας είναι κενή, είτε επειδή **βρίσκεται ήδη μέσα** στη λύση της
/// κλήσης: το ξανακλείσιμο της ίδιας εκκρεμότητας δεν διπλογράφει.
String? callSolutionAfterTaskClose({
  required String? existingCallSolution,
  required String taskSolution,
}) {
  final addition = taskSolution.trim();
  if (addition.isEmpty) return null;

  final existing = (existingCallSolution ?? '').trim();
  if (existing.contains(addition)) return null;

  final marked = '$kTaskSolutionCallPrefix $addition';
  return existing.isEmpty ? marked : '$existing\n\n$marked';
}
