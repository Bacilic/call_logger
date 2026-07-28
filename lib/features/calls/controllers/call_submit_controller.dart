import '../../../core/services/lookup_service.dart';
import '../../../core/utils/user_similarity_finder.dart';
import '../../directory/screens/widgets/similar_users_dialog.dart';
import '../models/user_model.dart';
import '../provider/call_header_provider.dart';

/// Έκβαση της «Καταγραφής» — το UI αποφασίζει τι μήνυμα θα δείξει.
enum CallSubmitOutcome {
  /// Αποθηκεύτηκε.
  saved,

  /// Η αποθήκευση επιχειρήθηκε και απέτυχε.
  failed,

  /// Ο χρήστης ακύρωσε πριν την αποθήκευση — κανένα μήνυμα.
  cancelled,
}

/// Ερωτήσεις προς τον χρήστη πριν την αποθήκευση κλήσης.
abstract class CallSubmitPrompts {
  /// Το όνομα που γράφτηκε μοιάζει με υπάρχοντες υπαλλήλους· τι κάνουμε;
  ///
  /// `null` σημαίνει «δεν ρωτήθηκε» και η αποθήκευση συνεχίζει ανενόχλητη.
  Future<SimilarUsersDialogResult?> resolveSimilarCallers(
    List<UserSimilarityMatch> matches,
  );
}

/// Ενέργειες υποβολής κλήσης.
abstract class CallSubmitActions {
  CallHeaderState get header;

  /// Ταυτοποίηση με υπάρχοντα υπάλληλο — ΔΕΝ δημιουργεί εγγραφή καταλόγου.
  void attachExistingCaller(UserModel user);

  Future<bool> submitCall();
}

/// Ενορχηστρώνει το κουμπί «Καταγραφή».
///
/// Η μόνη απόφαση πριν την αποθήκευση: όταν ο καλών είναι ελεύθερο κείμενο που
/// μοιάζει με υπάρχοντα υπάλληλο, ρωτάμε μήπως εννοεί εκείνον. Το ίδιο το
/// συμβόλαιο της υποβολής μένει άθικτο — καμία οντότητα καταλόγου δεν γεννιέται
/// εδώ, μόνο σύνδεση με υπάρχουσα.
class CallSubmitController {
  const CallSubmitController({required this.actions, required this.prompts});

  final CallSubmitActions actions;
  final CallSubmitPrompts prompts;

  Future<CallSubmitOutcome> run(LookupService? lookup) async {
    if (!await _resolveCallerIdentity(lookup)) {
      return CallSubmitOutcome.cancelled;
    }
    return await actions.submitCall()
        ? CallSubmitOutcome.saved
        : CallSubmitOutcome.failed;
  }

  /// `false` όταν ο χρήστης ακύρωσε την αποθήκευση.
  Future<bool> _resolveCallerIdentity(LookupService? lookup) async {
    if (lookup == null) return true;

    final header = actions.header;
    // Επιλεγμένος καλών σημαίνει ότι η ταυτοποίηση έχει ήδη γίνει ρητά.
    if (header.selectedCaller != null) return true;
    if (!header.hasExplicitCallerText) return true;

    final matches = UserSimilarityFinder.findSimilarUsersFromCallerText(
      users: lookup.users,
      callerDisplayText: header.normalizedCallerDisplayText,
    );
    if (matches.isEmpty) return true;

    final result = await prompts.resolveSimilarCallers(matches);
    if (result == null) return true;
    if (result.isCancelled) return false;

    final picked = result.selectedUser;
    if (picked != null) actions.attachExistingCaller(picked);
    return true;
  }
}
