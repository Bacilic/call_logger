# Αυτόματες δοκιμές (ελληνική σουίτα)

Η σουίτα ακολουθεί την **Πυραμίδα Δοκιμών (test pyramid)**:

- **Βάση:** δοκιμές providers / λογικής (`test/features/...`), χωρίς πλήρες UI.
- **Μέση / widget:** ροές φόρμας, εκκρεμότητα, αναζήτηση (`test/call_form_test.dart`, `test/pending_task_test.dart`, `test/search_test.dart`) με **απομονωμένη βάση SQLite** (βλ. `test/test_setup.dart`).
- **Κορυφή:** `integration_test/call_logger_integration_test.dart` για εκκίνηση εφαρμογής και βασική πλοήγηση.

## Απαιτήσεις (Windows desktop)

- `sqflite_common_ffi`: τα τεστ αρχικοποιούν FFI μέσω `initSqfliteFfiForTests()` στο `test_setup.dart`.
- Αν το `flutter test` κρασάρει με **`PathExistsException` / `sqlite3.dll` (errno 183)**: το Flutter προσπαθεί να αντιγράψει το native `sqlite3` στο `build/native_assets/windows/` χωρίς ασφαλή αντικατάσταση όταν το αρχείο υπάρχει ή είναι κλειδωμένο.
  - **Προτεινόμενο:** από τη ρίζα του project τρέξτε  
    `pwsh -File scripts/flutter_test_windows.ps1`  
    (περνάει τα επιπλέον ορίσματα στο `flutter test`, π.χ. `...ps1 test/widget_test.dart`).  
    Αν το αρχείο είναι **κλειδωμένο** (access denied), κλείστε διεργασίες Flutter/Dart και ξανατρέξτε, ή μετά το κλείσιμο:  
    `pwsh -File scripts/flutter_test_windows.ps1 -Clean` (τρέχει `flutter clean` πριν τα τεστ).
  - **Αλλιώς:** κλείστε άλλες διεργασίες που κρατούν το DLL (τρέχουσα εφαρμογή, δεύτερο `flutter test`, debug) και μετά `flutter clean` ή χειροκίνητη διαγραφή του `build/native_assets/windows/sqlite3.dll`.

### Αρχεία `flutter_XX.log` στη ρίζα

Όταν κρασάρει το Flutter CLI, γράφει `flutter_01.log`, `flutter_02.log`, … στο **τρέχον working directory** (συνήθως η ρίζα του project)· δεν υπάρχει επίσημο flag για άλλη διαδρομή.

- Μετά από κάθε `flutter test` μέσω **`scripts/flutter_test_windows.ps1`**, τα `flutter_*.log` **μεταφέρονται αυτόματα** στο φάκελο **`logs/`** (αν υπάρχει ήδη ίδιο όνομα, προστίθεται χρονική σήμανση).
- Αν τρέχεις `flutter` / `flutter test` **απευθείας** από τερματικό, εκτέλεσε όποτε θέλεις καθάρισμα μεταφοράς:  
  `pwsh -File scripts/move_flutter_tool_logs.ps1`  
- Ο φάκελος **`logs/`** (εκτός από `logs/.gitkeep`) είναι στο **`.gitignore`** ώστε να μην γεμίζει το git.

## Εντολές

```bash
# Όλα τα unit/widget tests (φάκελος test/)
flutter test

# Συγκεκριμένο αρχείο
flutter test test/call_form_test.dart

# Integration (χρειάζεται συσκευή / εκτελέσιμο — π.χ. Windows)
flutter test integration_test/call_logger_integration_test.dart
```

Για integration σε Windows desktop συχνά:

```bash
flutter test integration_test/call_logger_integration_test.dart -d windows
```

## Σταθεροποίηση UI στα widget tests

- `pumpUntilSettled` / `pumpUntilSettledLong` στο `test/test_setup.dart` κάνουν **επαναλαμβανόμενα `pump(step)`** (όχι `pumpAndSettle`): στην οθόνη Κλήσεων το **χρονόμετρο κλήσης** (`Timer.periodic`) κρατά πάντα pending frame, οπότε το `pumpAndSettle` θα «έβγαινε» μόνο μετά πολύ timeout ή θα έκανε τη σουίτα απελπιστικά αργή.
- Μετά την **πρώτη** φόρτωση `MyApp` χρησιμοποιείται συνήθως `pumpUntilSettledLong` (περισσότερα βήματα) για async providers και debounce.

## Αναφορές στα ελληνικά

- Βοηθητικά μηνύματα και συγκεντρωτική αναφορά: `test/test_reporter.dart` (`GreekTestReportCollector`, `greekExpectMsg`, `logStep`).
- Στο τέλος του αρχείου `integration_test/call_logger_integration_test.dart` καλείται `printFinalSummary` με ελληνικό τίτλο.

## Απομόνωση δεδομένων

Όλα τα τεστ που χρησιμοποιούν `registerCallLoggerIsolatedDatabaseHooks()` (ή `registerCallLoggerIsolatedDatabaseHooksIntegration()`) δεσμεύουν **προσωρινό αρχείο βάσης**, όχι τη βάση παραγωγής/χρήστη. Τα **Riverpod overrides** βρίσκονται στη `callLoggerTestProviderOverrides()`.
