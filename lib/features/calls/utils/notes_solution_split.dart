/// Το κοινό όριο χαρακτήρων του χαρτιού σημειώσεων (περιγραφή + λύση μαζί).
///
/// Δεν είναι συντακτικός κανόνας: υπάρχει μόνο ως φράγμα σε επικόλληση
/// τεράστιου κειμένου, που θα φούσκωνε τη γραμμή στο Ιστορικό και το ticket.
/// Ένα σημείο, ώστε να μπορέσει αργότερα να γίνει ρύθμιση.
const int kNotesTotalMaxLength = 500;

/// Πώς μοιράζεται το κοινό όριο ανάμεσα στα δύο πεδία του χαρτιού.
abstract final class NotesLengthBudget {
  NotesLengthBudget._();

  /// Το όριο που ισχύει για ΕΝΑ πεδίο, με δεδομένο πόσο κρατά το άλλο.
  ///
  /// Ποτέ μικρότερο από όσα ήδη γράφτηκαν: αλλιώς, γεμίζοντας το δεύτερο πεδίο
  /// θα κοβόταν αναδρομικά κείμενο του πρώτου στην επόμενη πληκτρολόγηση.
  /// Το αποτέλεσμα είναι «δεν χωράει άλλο», όχι «χάθηκε ό,τι είχες γράψει».
  static int limitFor({
    required int currentLength,
    required int otherLength,
    int total = kNotesTotalMaxLength,
  }) {
    final remaining = total - otherLength;
    return remaining < currentLength ? currentLength : remaining;
  }
}

/// Η διάσπαση «τρέχουσα γραμμή → Λύση» του χαρτιού σημειώσεων.
///
/// Ο χρήστης γράφει το πρόβλημα στην πρώτη γραμμή και τη λύση στη δεύτερη —
/// συνήθεια χρόνων. Το chip «Λύση» (ή Ctrl+Enter) αυτοματοποιεί την κίνηση:
/// παίρνει τη γραμμή όπου βρίσκεται ο κέρσορας και τη μεταφέρει στη ζώνη
/// Λύσης. Καθαρή συνάρτηση, χωρίς widgets: εδώ ζουν όλες οι ακμές (μοναδική
/// γραμμή, κενή γραμμή, όρια κειμένου) και εδώ ελέγχονται.
abstract final class NotesSolutionSplit {
  NotesSolutionSplit._();

  /// Αποσπά τη γραμμή του κέρσορα από το [text].
  ///
  /// Επιστρέφει το κείμενο χωρίς τη γραμμή και τη γραμμή καθαρή (trimmed).
  /// Όταν δεν υπάρχει τίποτα να μεταφερθεί, το [movedLine] είναι κενό και το
  /// [notes] μένει το αρχικό κείμενο ανέγγιχτο:
  ///
  /// - Ο κέρσορας πατά σε **κενή** γραμμή — δεν υπάρχει τι να κατέβει.
  /// - Η μεταφορά θα άφηνε τις σημειώσεις **άδειες** — η μόνη γραμμή του
  ///   χαρτιού είναι το πρόβλημα, όχι η λύση· κλήση χωρίς Περιγραφή δεν έχει
  ///   νόημα, και η Εκκρεμότητα πατά πάνω στις μη κενές σημειώσεις.
  static ({String notes, String movedLine}) extractCurrentLine(
    String text,
    int cursorOffset,
  ) {
    if (text.isEmpty) return (notes: text, movedLine: '');
    final offset = cursorOffset.clamp(0, text.length);

    final lineStart = text.lastIndexOf('\n', offset - 1 < 0 ? 0 : offset - 1);
    final start = lineStart < 0 || offset == 0 ? 0 : lineStart + 1;
    final lineEnd = text.indexOf('\n', offset);
    final end = lineEnd < 0 ? text.length : lineEnd;

    final movedLine = text.substring(start, end).trim();
    if (movedLine.isEmpty) return (notes: text, movedLine: '');

    // Μαζί με τη γραμμή φεύγει ΕΝΑ γειτονικό \n, ώστε να μη μείνει κενή τρύπα:
    // το αριστερό όταν υπάρχει (γραμμή στο τέλος/μέση), αλλιώς το δεξί (πρώτη).
    var removeFrom = start;
    var removeTo = end;
    if (removeFrom > 0) {
      removeFrom -= 1;
    } else if (removeTo < text.length) {
      removeTo += 1;
    }
    final remaining = text.replaceRange(removeFrom, removeTo, '');
    if (remaining.trim().isEmpty) return (notes: text, movedLine: '');

    return (notes: remaining, movedLine: movedLine);
  }
}
