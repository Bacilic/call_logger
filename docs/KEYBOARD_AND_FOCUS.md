# Πληκτρολόγιο και εστίαση (Keyboard & Focus)

## Γενικές αρχές

- **Shortcuts/Actions**: Οι συντόμευσεις πληκτρολογίου ορίζονται μόνο σε root επίπεδο μέσω `Shortcuts` και `Actions`. Δεν χρησιμοποιείται `RawKeyboardListener` ούτε custom key dispatches.
- **Αποφυγή ταυτόχρονου focus**: Το `TextField` του πεδίου «Εσωτερικό» δεν πρέπει να δέχεται force focus ταυτόχρονα μέσω `autofocus: true` και `focusNode.requestFocus()` όταν ενεργοποιείται shortcut ή αλλαγή διαδρομής βάσης. Γι’ αυτό:
  - Το `requestFocus()` από shortcut (Quick Capture / Ctrl+Alt+L) εκτελείται μέσα σε `Future.microtask()` ώστε να γίνει μετά το release του key event.
  - Μετά την υποβολή κλήσης, το `requestFocus()` στο πεδίο Εσωτερικό γίνεται επίσης σε `Future.microtask()`.
- **Rebuild και notifyListeners**: Αν κάποιο service καλεί `notifyListeners()` ή προκαλεί rebuild του UI ενώ μια συντόμευση είναι ενεργή, η ενημέρωση του UI πρέπει να γίνεται μετά το release του key event (π.χ. μέσω `Future.microtask` ή `SchedulerBinding.instance.addPostFrameCallback`).

## Αποδέσμευση focus πριν από αλλαγή context

**Οποιοδήποτε widget που ακούει key events ή διατηρεί μόνιμη εστίαση πρέπει να αποδεσμεύει το focus πριν γίνει rebuild, αλλαγή σελίδας (page reload) ή αλλαγή context.**

Κατά την **αλλαγή διαδρομής βάσης δεδομένων** (Ρυθμίσεις → Αποθήκευση ρύθμισης) η εφαρμογή δεν κάνει αυτόματο κλείσιμο: εμφανίζεται ενημερωτικό μήνυμα ότι η νέα διαδρομή θα ισχύσει στην επόμενη εκκίνηση και ο χρήστης κλείνει χειροκίνητα (Alt+F4 ή κουμπί κλεισίματος).

## Root-level shortcuts

| Συντόμευση    | Intent              | Ενέργεια                    |
|---------------|---------------------|-----------------------------|
| Ctrl+Alt+L    | QuickCaptureIntent  | Εστίαση στο πεδίο Εσωτερικό |
| Ctrl+Alt+C    | QuickCaptureIntent  | Εστίαση στο πεδίο Εσωτερικό |

Οι ενέργειες ορίζονται στο `AppShortcuts` (root). Για reset UI μετά από αλλαγή path βάσης ή login χρησιμοποιείται `Future.microtask` (ή ανάλογα) ώστε να μην γίνεται μετάδοση key events κατά το rebuild.

## Unit tests και key events

Σε tests που χειρίζονται key events, το **keyUp πρέπει να συμβαίνει ΜΕΤΑ το keyDown** (π.χ. `tester.sendKeyDownEvent` ακολουθούμενο από `tester.sendKeyUpEvent`), ώστε να προσομοιώνεται σωστά η ακολουθία πληκτρολογίου.
