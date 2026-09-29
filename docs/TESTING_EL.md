# Αυτόματες δοκιμές (ελληνική σουίτα)

Η σουίτα ακολουθεί την **Πυραμίδα Δοκιμών (test pyramid)**:

- **Βάση:** δοκιμές providers / λογικής (`test/features/...`), χωρίς πλήρες UI.
- **Μέση / widget:** ροές φόρμας, εκκρεμότητα, αναζήτηση (`test/features/calls/call_form_test.dart`, `test/features/tasks/pending_task_test.dart`, `test/features/history/history_search_test.dart`, `test/features/directory/directory_user_search_test.dart`) με **απομονωμένη βάση SQLite** (βλ. `test/test_setup.dart`).
- **Κορυφή:** εκκίνηση εφαρμογής και βασική πλοήγηση καλύπτονται από `test/widget_test.dart` και `test/core/widgets/main_shell_nav_rail_layout_test.dart`, τα οποία φορτώνουν το πλήρες `MyApp` μέσα στη σουίτα.

> Ο φάκελος `integration_test/` **καταργήθηκε (01/08/2026)**. Επειδή το `flutter test` σαρώνει μόνο το `test/`, το μοναδικό του αρχείο δεν εκτελούνταν ποτέ και γέρασε σιωπηλά μαζί με τον ανασχεδιασμό UI του Ιουλίου 2026 — φύλαγε μπάρα κορυφής και κουμπί Ρυθμίσεων που δεν υπάρχουν πια. Αν χρειαστεί ξανά πραγματικό end-to-end, μπαίνει **μαζί με σταθερό σημείο εκτέλεσης** (π.χ. πριν από κάθε δημοσίευση), αλλιώς ξαναγερνάει.

## Απαιτήσεις (Windows desktop)

- `sqflite_common_ffi`: τα τεστ αρχικοποιούν FFI μέσω `initSqfliteFfiForTests()` στο `test_setup.dart`.
- Αν το `flutter test` κρασάρει με **`PathExistsException` / `sqlite3.dll` (errno 183)**: το Flutter προσπαθεί να αντιγράψει το native `sqlite3` στο `build/native_assets/windows/` χωρίς ασφαλή αντικατάσταση όταν το αρχείο υπάρχει ή είναι κλειδωμένο.
  - **Προτεινόμενο:** από τη ρίζα του project τρέξτε  
    `pwsh -File scripts/flutter_test_windows.ps1`  
    (περνάει τα επιπλέον ορίσματα στο `flutter test`, π.χ. `...ps1 test/widget_test.dart`).  
    Αν το αρχείο είναι **κλειδωμένο** (access denied), κλείστε διεργασίες Flutter/Dart και ξανατρέξτε, ή μετά το κλείσιμο:  
    `pwsh -File scripts/flutter_test_windows.ps1 -Clean` (τρέχει `flutter clean` πριν τα τεστ).
  - **Όταν το DLL μένει κλειδωμένο:** υπάρχει έτοιμο εργαλείο —
    `pwsh -NoProfile -File scripts/terminate_dartvm_delete_sqlite3_dll.ps1`
    Τερματίζει τα `dartvm.exe`, **ρωτά ξεχωριστά** για κάθε άλλη διεργασία που φορτώνει το DLL,
    και διαγράφει το `build/native_assets/windows/sqlite3.dll` μαζί με τον φάκελο
    `.dart_tool/hooks_runner/sqlite3`. Δεν κλείνει τίποτα άσκοπα: αν λείπει ένας από τους δύο
    στόχους, δεν τερματίζει καμία διεργασία. Με `-DryRun` δείχνει τι θα έκανε χωρίς να το κάνει.
  - **Χειροκίνητα, αν προτιμάτε:** κλείστε τις διεργασίες που κρατούν το DLL (τρέχουσα εφαρμογή,
    δεύτερο `flutter test`, debug) και μετά `flutter clean` ή διαγραφή του
    `build/native_assets/windows/sqlite3.dll`. Σκοτώνετε **κατά PID**, ποτέ κατά όνομα — το όνομα
    `dart` παρασύρει και τους μακρόβιους analysis servers.

### Αρχεία `flutter_XX.log` στη ρίζα

Όταν κρασάρει το Flutter CLI, γράφει `flutter_01.log`, `flutter_02.log`, … στο **τρέχον working directory** (συνήθως η ρίζα του project)· δεν υπάρχει επίσημο flag για άλλη διαδρομή.

- Μετά από κάθε `flutter test` μέσω **`scripts/flutter_test_windows.ps1`**, τα `flutter_*.log` **μεταφέρονται αυτόματα** στο φάκελο **`logs/`** (αν υπάρχει ήδη ίδιο όνομα, προστίθεται χρονική σήμανση).
- Αν τρέχεις `flutter` / `flutter test` **απευθείας** από τερματικό, εκτέλεσε όποτε θέλεις καθάρισμα μεταφοράς:  
  `pwsh -File scripts/move_flutter_tool_logs.ps1`  
- Ο φάκελος **`logs/`** (εκτός από `logs/.gitkeep`) είναι στο **`.gitignore`** ώστε να μην γεμίζει το git.

## Εντολές

```bash
# Συγκεκριμένο αρχείο ή φάκελος περιοχής (ο φάκελος test/ καθρεφτίζει το lib/)
flutter test test/features/calls/call_form_test.dart
flutter test test/features/calls/

# Συγκεκριμένη δοκιμή με το όνομά της
flutter test --plain-name "Η εφαρμογή εμφανίζει το κύριο κέλυφος και τα πεδία εισαγωγής κλήσης"

# Πολλές διαδρομές μαζί, σε ΜΙΑ εκτέλεση
flutter test test/features/calls/ test/core/services/lookup_service_test.dart
```

> **Το σκέτο `flutter test` (χωρίς διαδρομή) δεν τρέχει στην καθημερινή δουλειά.** Σαρώνει
> ολόκληρη τη σουίτα — 880 αρχεία, ~5 λεπτά στο γρήγορο μηχάνημα και ~18 στο αργό.
> Τρέχει **μία φορά ανά συνεδρία, στο κλείσιμο, και μόνο στο γρήγορο μηχάνημα**. Όσο δουλεύεις,
> τρέχεις ονομαστικά τα αρχεία που σχετίζονται με ό,τι άλλαξες.

## Χρόνος εκτέλεσης — τι τον καθορίζει

Μετρημένο 29/09/2026 (πλήρης σουίτα: 6:17 → 4:54, 6.780 τεστ).

- **Κάθε αρχείο τεστ κοστίζει ~0,4 δευτερόλεπτα μόνο για να προετοιμαστεί.** Το Flutter
  μεταγλωττίζει τα αρχεία ένα-ένα, σε σειρά, και αυτό είναι ~80% του χρόνου. Ο χρόνος
  ακολουθεί το πλήθος των **αρχείων**, όχι των τεστ — γι' αυτό ο κανόνας Κ7 του `CLAUDE.md`:
  νέο τεστ μπαίνει στο υπάρχον αρχείο της ίδιας λειτουργίας, όπου ταιριάζει.
- **Τα προσωρινά αρχεία των τεστ γράφονται στο `build/test_tmp`**, στον δίσκο του έργου, όχι
  στον φάκελο προσωρινών του συστήματος. Το ορίζει το `test/flutter_test_config.dart`· στο
  γρήγορο μηχάνημα ο C: θέλει ~9ms ανά εγγραφή SQLite και ο F: ~2,6ms. Υπολείμματα παλαιότερα
  της μίας ημέρας σβήνονται αυτόματα· ολόκληρος ο φάκελος φεύγει με `flutter clean`.
- **Ένα τεστ οθόνης (`testWidgets`) που κρεμάει κόβεται στα 2 λεπτά** (το Flutter από μόνο του
  περιμένει 10). Βγαίνει κόκκινο με «Test timed out after 2 minutes». Τεστ που δηλώνει δικό
  του `timeout` το κρατά.
- **Δοκιμάστηκαν και απορρίφθηκαν:** η σημαία `--experimental-faster-testing` (στην 3.47.1
  δεν δουλεύει· με παράκαμψη μετρήθηκε πιο αργή), παράλληλα τρεξίματα `flutter test`
  (συγκρούονται στο `sqlite3.dll`) και συγχώνευση αρχείων (αλλάζει την απομόνωση των τεστ).

## Σταθεροποίηση UI στα widget tests

- `pumpUntilSettled` / `pumpUntilSettledLong` στο `test/test_setup.dart` κάνουν **επαναλαμβανόμενα `pump(step)`** (όχι `pumpAndSettle`): στην οθόνη Κλήσεων το **χρονόμετρο κλήσης** (`Timer.periodic`) κρατά πάντα pending frame, οπότε το `pumpAndSettle` θα «έβγαινε» μόνο μετά πολύ timeout ή θα έκανε τη σουίτα απελπιστικά αργή.
- Μετά την **πρώτη** φόρτωση `MyApp` χρησιμοποιείται συνήθως `pumpUntilSettledLong` (περισσότερα βήματα) για async providers και debounce.

## Αναφορές στα ελληνικά

- Βοηθητικά μηνύματα και συγκεντρωτική αναφορά: `test/test_reporter.dart` (`GreekTestReportCollector`, `greekExpectMsg`, `logStep`).

## Απομόνωση δεδομένων

Όλα τα τεστ που χρησιμοποιούν `registerCallLoggerIsolatedDatabaseHooks()` δεσμεύουν **προσωρινό αρχείο βάσης**, όχι τη βάση παραγωγής/χρήστη. Τα **Riverpod overrides** βρίσκονται στη `callLoggerTestProviderOverrides()`.
