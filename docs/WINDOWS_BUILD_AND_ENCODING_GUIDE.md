# Οδηγός Μεταγλώττισης σε Εκτελέσιμο στα Windows (Flutter)

Αυτό το έγγραφο περιγράφει τη σωστή διαδικασία για να παραχθεί εκτελέσιμο αρχείο (`.exe`) σε περιβάλλον Windows, καθώς και τις κρίσιμες ρυθμίσεις κωδικοποίησης (encoding) για σωστή εμφάνιση ελληνικών στον τίτλο παραθύρου.

> Σημείωση: Το συγκεκριμένο θέμα με τα ελληνικά στον τίτλο μάς είχε κοστίσει πολλές ώρες. Ο παρακάτω οδηγός είναι η ασφαλής, επαναλήψιμη διαδικασία που λύνει το πρόβλημα.

---

## 1) Προαπαιτούμενα (Prerequisites)

- Εγκατεστημένο `Flutter SDK`
- Εγκατεστημένο `Visual Studio 2022` με workload **Desktop development with C++**
- Ενεργοποιημένο Windows desktop support:

```powershell
flutter config --enable-windows-desktop
```

- Έλεγχος περιβάλλοντος:

```powershell
flutter doctor -v
```

---

## 2) Κρίσιμα σημεία για ελληνικά (UTF-8 / Unicode)

Για σωστή εμφάνιση ελληνικών στον τίτλο παραθύρου των Windows:

1. Το `windows/runner/main.cpp` πρέπει να χρησιμοποιεί wide string literal (`L"..."`) στον τίτλο:

```cpp
if (!window.Create(L"Χειρουργία Στην Ιστοσελίδα", origin, size)) {
  return EXIT_FAILURE;
}
```

2. Το `windows/runner/Runner.rc` πρέπει να έχει:

```rc
#pragma code_page(65001)
```

ώστε το resource script να διαβάζεται ως UTF-8.

3. Τα αρχεία `main.cpp` και `Runner.rc` πρέπει να είναι αποθηκευμένα σε κωδικοποίηση UTF-8 (ιδανικά UTF-8 with BOM αν ο resource compiler είναι αυστηρός).

4. Απέφυγε copy/paste από επεξεργαστές που αλλάζουν encoding σε ANSI/Windows-1252.

---

## 3) Πού ορίζεται ο τίτλος στο Flutter Windows Runner

Ο τίτλος παραθύρου που βλέπει ο χρήστης ορίζεται από το:

- `windows/runner/main.cpp` -> `window.Create(L"...")`

Τα πεδία του `windows/runner/Runner.rc` (`FileDescription`, `ProductName`, κ.λπ.) αφορούν metadata του executable (version info), όχι απαραίτητα τον runtime τίτλο του παραθύρου.

---

## 4) Βήματα καθαρής μεταγλώττισης (Clean Build)

Από τη ρίζα του project:

```powershell
flutter clean
flutter pub get
flutter build windows --release
```

Αν έχεις υποψία για cache/config mismatch:

```powershell
flutter clean
rd /s /q build
flutter pub get
flutter build windows --release
```

---

## 5) Πού βρίσκεται το εκτελέσιμο

Μετά από επιτυχημένο build, το `.exe` βρίσκεται συνήθως εδώ:

- `build/windows/x64/runner/Release/<app_name>.exe`

Μαζί με το `.exe` πρέπει να διανέμονται και τα συνοδευτικά αρχεία/φάκελοι του `Release` (π.χ. DLLs, data).

---

## 6) Έλεγχος ότι το build έγινε σωστά

### Έλεγχος λειτουργίας (Smoke Test)

- Το πρόγραμμα ανοίγει χωρίς crash.
- Φορτώνει σωστά το UI.
- Ο τίτλος παραθύρου εμφανίζει σωστά ελληνικά (χωρίς "σπασμένους" χαρακτήρες).

### Έλεγχος metadata (προαιρετικό)

Δεξί κλικ στο `.exe` -> Properties -> Details, για τα πεδία version info από `Runner.rc`.

---

## 7) Συνήθη προβλήματα και λύσεις (Troubleshooting)

### Πρόβλημα: Ο τίτλος έχει αλλοιωμένα ελληνικά

Πιθανές αιτίες:
- αρχείο σε λάθος encoding
- απουσία `#pragma code_page(65001)` στο `.rc`
- title literal χωρίς `L` στο `main.cpp`

Λύση:
1. Βεβαιώσου ότι στο `main.cpp` είναι `L"..."`.
2. Βεβαιώσου ότι στο `Runner.rc` υπάρχει `#pragma code_page(65001)`.
3. Αποθήκευσε και τα 2 αρχεία σε UTF-8.
4. Τρέξε `flutter clean` και νέο `flutter build windows --release`.

### Πρόβλημα: Build errors από MSVC/CMake

Λύση:
- Εκτέλεσε `flutter doctor -v`
- Βεβαιώσου ότι είναι εγκατεστημένο το Visual Studio C++ workload
- Κάνε επανεκκίνηση terminal/IDE και νέο build.

---

## 8) Προτεινόμενη διαδικασία για μελλοντικές εκδόσεις (Release Process)

1. Αλλαγές κώδικα
2. `flutter analyze`
3. `flutter test` (αν υπάρχουν tests)
4. `flutter build windows --release`
5. Smoke test στο παραγόμενο `.exe`
6. Πακετάρισμα ολόκληρου του φακέλου `Release`

---

## 9) Quick checklist (γρήγορη λίστα)

- [ ] Ο τίτλος στο `main.cpp` είναι `L"..."` με σωστά ελληνικά
- [ ] Το `Runner.rc` έχει `#pragma code_page(65001)`
- [ ] Τα αρχεία είναι αποθηκευμένα σε UTF-8
- [ ] Έγινε `flutter clean` πριν το τελικό release build
- [ ] Το `.exe` ανοίγει και εμφανίζει σωστά τον ελληνικό τίτλο
- [ ] Διανεμήθηκε όλος ο φάκελος `Release` (όχι μόνο το `.exe`)

---

## 10) Ενδεικτική καταγραφή "επιτυχούς build"

Χρήσιμο να κρατάμε σε changelog/internal notes:

- Ημερομηνία build
- Flutter version (`flutter --version`)
- Commit/hash (αν υπάρχει git)
- Μηχάνημα/OS build
- Επιβεβαίωση ότι ο ελληνικός τίτλος εμφανίζεται σωστά

Έτσι, το επόμενο release γίνεται επαναλήψιμο χωρίς να χαθεί ξανά χρόνος σε θέματα κωδικοποίησης.

