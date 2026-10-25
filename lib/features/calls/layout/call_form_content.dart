import '../provider/call_entry_provider.dart';
import '../provider/smart_entity_selector_state.dart';

/// Έχει η φόρμα κλήσης κάτι που θα χανόταν αν έκλεινε τώρα;
///
/// Ο κανόνας «ανοιχτή κλήση» σε ΕΝΑ σημείο: τον ρωτούν ο φρουρός αλλαγής βάσης
/// (για την κύρια φόρμα και για την ελαχιστοποιημένη γρήγορη καταγραφή) και το
/// «Χ» της γρήγορης καταγραφής. Το χρονόμετρο μετρά, γιατί ξεκινά με το πρώτο
/// ψηφίο του τηλεφώνου.
///
/// Το τηλέφωνο διαβάζεται και απευθείας: γράφεται στη φόρμα με κάθε ψηφίο,
/// ενώ η σημαία «έχει περιεχόμενο» ανανεώνεται μόνο όταν το πεδίο κλειδώσει
/// (έξοδος, Enter). Ένα «2807» που μόλις πληκτρολογήθηκε είναι ήδη κλήση.
bool callFormHasContent(SmartEntitySelectorState smart, CallEntryState entry) {
  return smart.hasAnyContent ||
      (smart.selectedPhone?.trim().isNotEmpty ?? false) ||
      entry.isCallTimerRunning ||
      entry.durationSeconds > 0 ||
      entry.notes.trim().isNotEmpty ||
      entry.category.trim().isNotEmpty;
}
