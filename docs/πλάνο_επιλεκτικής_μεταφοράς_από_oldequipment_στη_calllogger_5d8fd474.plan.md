---
name: Πλάνο Επιλεκτικής Μεταφοράς από oldequipment στη calllogger
overview: "Υλοποίηση ενός έξυπνου οδηγού μεταφοράς (Dual-Pane Wizard) που λειτουργεί ως μηχανισμός προτάσεων (suggestions). Το σύστημα διαβάζει τα παλιά δεδομένα, ψάχνει για αντιστοιχίες στη νέα βάση και προ-συμπληρώνει υπάρχουσες φόρμες. Ο χρήστης επικυρώνει ή διορθώνει (Human-in-the-loop) πριν την τελική εγγραφή, διασφαλίζοντας την ακεραιότητα της call_logger.db."
todos:
  - id: add-transfer-button-ui
    content: Σχεδίαση θέσης/κανόνων εμφάνισης του κουμπιού "Μεταφορά" στο Lamp result card (ενεργό μόνο για equipment, department, owner).
    status: pending
  - id: implement-migration-service
    content: Δημιουργία LampMigrationService για cross-referencing δεδομένων (παλιά -> νέα), με αξιοποίηση της ήδη υπάρχουσας ρουτίνας similarity/confidence score (αν υπάρχει) και παραγωγή pre-fill δεδομένων/hints.
    status: pending
  - id: implement-top3-fallback
    content: Εφαρμογή fallback Top-3 matches στο LampMigrationService όταν δεν υπάρχει 100% ταύτιση, ώστε να επιστρέφονται 3 candidate matches με confidence score.
    status: pending
  - id: implement-dual-pane-wizard
    content: Υλοποίηση UI διαλόγου (Dual-Pane) που εμφανίζει τα παλιά δεδομένα (Read-only) και μια επεξεργάσιμη φόρμα (Destination) κάνοντας compose τα υπάρχοντα input widgets, και παρουσιάζοντας Top-3 candidate matches στον χρήστη.
    status: pending
  - id: implement-sanitized-writes
    content: Σύνδεση της φόρμας του wizard με τις ΥΠΑΡΧΟΥΣΕΣ μεθόδους εισαγωγής/ενημέρωσης (directory_repository), εξασφαλίζοντας defaults (π.χ. is_deleted=0).
    status: pending
  - id: verify-scenarios
    content: Έλεγχος σεναρίων μεταφοράς (επιτυχές pre-fill, απουσία τμήματος στη νέα βάση, ενημέρωση ήδη υπάρχουσας εγγραφής).
    status: pending
isProject: false
---

# Πλάνο Επιλεκτικής Μεταφοράς από old_equipment στη call_logger

## Στόχος
- Προσθήκη κουμπιού μεταφοράς δίπλα στο κουμπί επεξεργασίας στο `lib/features/lamp/widgets/lamp_result_card.dart`.
- Η μεταφορά γίνεται μέσω ενός "Smart Wizard" (Dual-Pane UI):
  - **Αριστερά:** Read-only προβολή των δεδομένων από το `old_equipment.db`.
  - **Δεξιά:** Επεξεργάσιμη φόρμα που επαναχρησιμοποιεί τα existing UI components της εφαρμογής.
- Το σύστημα **προτείνει** (pre-fills) σχέσεις (π.χ. Τμήμα, Τηλέφωνα) ψάχνοντας τη νέα βάση.
- Για cross-referencing εφαρμόζεται ρητά ο κανόνας:
  1. **Πρώτα επαναχρησιμοποίηση** υπάρχοντος κώδικα/συναρτήσεων για similarity & confidence score.
  2. **Νέος scoring αλγόριθμος από το μηδέν μόνο αν δεν υπάρχει διαθέσιμη ρουτίνα**.
  3. **Fallback Top-3 Matches** όταν δεν υπάρχει 100% ταύτιση (π.χ. σε τμήματα/χρήστες): ο wizard προβάλλει 3 candidates με confidence score και ο χρήστης επιλέγει.
- Αν δεν βρει επαρκή αντιστοιχία, αφήνει το πεδίο κενό με hint (π.χ. "Παλιό τμήμα: Πληροφορική") και απαιτεί από τον χρήστη να επιλέξει από τα διαθέσιμα της νέας βάσης.
- **Καμία ορφανή εγγραφή:** Η τελική αποθήκευση περνάει από το standard validation της εφαρμογής.

## Αρχεία προς δημιουργία / αλλαγή
- `lib/features/lamp/widgets/lamp_result_card.dart`
  - Προσθήκη κουμπιού μεταφοράς (ορατό/ενεργό μόνο για equipment/department/owner).
- `lib/features/lamp/services/lamp_migration_service.dart` (ΝΕΟ)
  - Η λογική που αναλαμβάνει να κάνει query την παλιά βάση, να ψάξει για matches στην καινούργια (π.χ. name_keys) και να επιστρέψει DTO / State με suggestions.
  - Υποχρεωτική αξιοποίηση υπάρχουσας ρουτίνας similarity/confidence score (αν υπάρχει ήδη στο codebase).
  - Fallback μηχανισμός Top-3 candidate matches με confidence score όταν δεν υπάρχει ακριβής ταύτιση.
- `lib/features/lamp/widgets/lamp_transfer_wizard_dialog.dart` (ΝΕΟ)
  - Το Dual-Pane UI. Πρέπει να κάνει compose/επαναχρησιμοποιήσει τα υπάρχοντα TextFields, Dropdowns (π.χ. `DepartmentDropdown`) και Form Validators του συστήματος.
  - Προβολή Top-3 matches (με score) και ρητή επιλογή/επιβεβαίωση από χρήστη (Human-in-the-loop).
- `lib/features/lamp/screens/lamp_screen.dart`
  - Σύνδεση του κουμπιού με το άνοιγμα του νέου διαλόγου.

*(Σημείωση: Το `directory_repository.dart` ΔΕΝ θα πειραχτεί με λογική migration. Ο wizard θα καλεί απλώς τα ήδη υπάρχοντα methods `insertUser`, `insertEquipment` κλπ., στέλνοντας τα επικυρωμένα από τον χρήστη δεδομένα).*

## Edge Cases που θα καλυφθούν
- **Ορφανές Σχέσεις:** Ο παλιός χρήστης ανήκε σε τμήμα που δεν υπάρχει στη νέα βάση. Το UI δείχνει warning και αναγκάζει τον χρήστη να επιλέξει/δημιουργήσει ένα πριν το save.
- **Merge Conflict:** Η εγγραφή (π.χ. Βασίλης Δρόσος) υπάρχει ήδη στη νέα βάση. Ο δεξιός πίνακας γεμίζει με τα *τρέχοντα* νέα δεδομένα και το action γίνεται "Ενημέρωση" αντί για "Δημιουργία".
- **Μη 100% Ταύτιση:** Όταν το confidence είναι κάτω από το όριο ακριβούς ταύτισης, εμφανίζονται Top-3 candidates. Αν ο χρήστης δεν επιλέξει κανένα, η ροή συνεχίζει με κενό πεδίο και υποχρεωτική χειροκίνητη επιλογή.
- **Πολλαπλά κοντινά matches με παρόμοιο score:** Το UI προβάλλει καθαρά score + βασικά metadata για ασφαλή επιλογή και αποφυγή λάθους merge.
- **Απαραίτητα Defaults Schema:** Κατά την αποθήκευση διασφαλίζεται ότι πεδία όπως `is_deleted` γίνονται `0`, και `map_hidden` (στα departments) γίνονται `1`.
- **Απουσία Τηλεφώνου:** Αν η παλιά εγγραφή δεν είχε τηλέφωνο, το πεδίο μένει κενό και εφαρμόζονται οι standard κανόνες validation της εφαρμογής.

## Test Plan (Χειροκίνητο)
- Μεταφορά ενός χρήστη του οποίου το τμήμα **υπάρχει** ήδη στη νέα βάση (πρέπει να προ-επιλεγεί αυτόματα).
- Μεταφορά ενός χρήστη του οποίου το τμήμα **δεν υπάρχει** στη νέα βάση (πρέπει να εμφανίσει hint και να ζητήσει επιλογή).
- Προσπάθεια μεταφοράς εξοπλισμού που υπάρχει ήδη (πρέπει να μεταβεί σε λειτουργία merge/update).
- Έλεγχος ότι η νέα εγγραφή αναζητείται κανονικά στο κεντρικό Quick Capture / Search της εφαρμογής.