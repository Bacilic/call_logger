/// Εναλλακτικό σημείο εκκίνησης, **μόνο για ανάπτυξη**.
///
/// Ανοίγει την ίδια ακριβώς εφαρμογή με το `lib/main.dart`, αλλά με ενεργή την
/// επέκταση του `flutter_driver`: όσο τρέχει έτσι, ένας βοηθός μπορεί να πατά
/// κουμπιά, να γράφει σε πεδία, να διαβάζει κείμενο και να βγάζει στιγμιότυπα
/// από την πραγματική εφαρμογή — δηλαδή να επαληθεύει ο ίδιος μια αλλαγή αντί
/// να ζητά από τον χειριστή να τη δοκιμάσει.
///
/// **Δεν αγγίζει το παραδοτέο.** Το αρχείο ζει έξω από το `lib/`, οπότε δεν
/// μπαίνει ποτέ σε κανονική έκδοση: η επέκταση ανοίγει μόνο όταν ζητηθεί ρητά
/// αυτό το σημείο εκκίνησης.
///
/// Εκτέλεση:
///
///     flutter run -d windows -t test_driver/driver_main.dart
///
/// Για άλλο προφίλ δεδομένων, τα ορίσματα περνούν όπως και στην κανονική
/// εκκίνηση:
///
///     flutter run -d windows -t test_driver/driver_main.dart --dart-entrypoint-args --profile=dev
library;

import 'package:call_logger/main.dart' as app;
import 'package:flutter_driver/driver_extension.dart';

Future<void> main(List<String> arguments) async {
  // Πριν από οτιδήποτε άλλο: η επέκταση στήνει το binding της εφαρμογής, και
  // το `WidgetsFlutterBinding.ensureInitialized()` του κανονικού main βρίσκει
  // μετά έτοιμο αυτό — δεν φτιάχνει δεύτερο.
  //
  // `enableTextEntryEmulation: false` είναι ΑΠΑΡΑΙΤΗΤΟ: με την προεπιλογή του
  // Flutter (true) η επέκταση παίρνει τον έλεγχο της εισαγωγής κειμένου και
  // το πραγματικό πληκτρολόγιο σταματά να γράφει στα πεδία — το ποντίκι
  // δουλεύει, τα γράμματα δεν φτάνουν πουθενά. Με false η εφαρμογή
  // πληκτρολογείται κανονικά· όταν χρειαστεί να γράψει ο βοηθός, ανάβει την
  // προσομοίωση προσωρινά με την εντολή `set_text_entry_emulation`.
  enableFlutterDriverExtension(enableTextEntryEmulation: false);
  await app.main(arguments);
}
