# Πληκτρολόγιο και εστίαση (Keyboard & Focus)

## Γενικές αρχές

- **Shortcuts/Actions**: Οι συντόμευσεις πληκτρολογίου ορίζονται μόνο σε root επίπεδο μέσω `Shortcuts` και `Actions`. Δεν χρησιμοποιείται `RawKeyboardListener` ούτε custom key dispatches.
- **Αποφυγή ταυτόχρονου focus**: Το `TextField` του πεδίου «Εσωτερικό» δεν πρέπει να δέχεται force focus ταυτόχρονα μέσω `autofocus: true` και `focusNode.requestFocus()` όταν ενεργοποιείται shortcut ή αλλαγή διαδρομής βάσης. Γι’ αυτό:
  - Το `requestFocus()` από shortcut (Quick Capture) εκτελείται μέσα σε `Future.microtask()` ώστε να γίνει μετά το release του key event.
  - Μετά την υποβολή κλήσης, το `requestFocus()` στο πεδίο Εσωτερικό γίνεται επίσης σε `Future.microtask()`.
- **Rebuild και notifyListeners**: Αν κάποιο service καλεί `notifyListeners()` ή προκαλεί rebuild του UI ενώ μια συντόμευση είναι ενεργή, η ενημέρωση του UI πρέπει να γίνεται μετά το release του key event (π.χ. μέσω `Future.microtask` ή `SchedulerBinding.instance.addPostFrameCallback`).

## Αποδέσμευση focus πριν από αλλαγή context

**Οποιοδήποτε widget που ακούει key events ή διατηρεί μόνιμη εστίαση πρέπει να αποδεσμεύει το focus πριν γίνει rebuild, αλλαγή σελίδας (page reload) ή αλλαγή context.**

Κατά την **αλλαγή διαδρομής βάσης δεδομένων** από τις Ρυθμίσεις (επιλογέας αρχείου βάσης ή επιλογή πρόσφατης διαδρομής) η νέα βάση επαληθεύεται πριν εφαρμοστεί και η εφαρμογή δεν κλείνει αυτόματα.

## Root-level shortcuts

| Συντόμευση   | Intent                  | Ενέργεια                                        |
|--------------|-------------------------|-------------------------------------------------|
| Ctrl+Shift+N | QuickCaptureIntent      | Γρήγορη καταγραφή κλήσης εκτός της κύριας φόρμας |
| Ctrl+Shift+L | LansweeperReportIntent  | Αναφορά Lansweeper με τις σημερινές κλήσεις      |

Ο κατάλογος ζει στο `lib/core/widgets/app_keyboard_shortcuts.dart` και οι ενέργειες ορίζονται στο `AppShortcuts` (root).

**Κάθε συνδυασμός δηλώνεται δύο φορές.** Το `SingleActivator` με λογικό πλήκτρο καλύπτει την αγγλική διάταξη· ο `CharacterActivator` με τον ελληνικό χαρακτήρα («Ν», «Λ») καλύπτει την ελληνική. Χωρίς τη δεύτερη εγγραφή η συντόμευση σιωπά όσο ο χρήστης γράφει ελληνικά — δηλαδή τις μισές ώρες της ημέρας.

Για reset UI μετά από αλλαγή path βάσης ή login χρησιμοποιείται `Future.microtask` (ή ανάλογα) ώστε να μην γίνεται μετάδοση key events κατά το rebuild.

## Unit tests και key events

Σε tests που χειρίζονται key events, το **keyUp πρέπει να συμβαίνει ΜΕΤΑ το keyDown** (π.χ. `tester.sendKeyDownEvent` ακολουθούμενο από `tester.sendKeyUpEvent`), ώστε να προσομοιώνεται σωστά η ακολουθία πληκτρολογίου.
