import 'package:flutter/material.dart';

import '../../../../core/widgets/compact_tooltip.dart';
import '../../models/user_form_field_changes.dart';
import 'user_form_dialog.dart';

enum _UserFormDismissChoice { keep, discard, continueEditing }

enum _UserFormSideTripChoice { discard, continueEditing }

/// Φρουρός κλεισίματος της φόρμας υπαλλήλου: dirty έλεγχος + διάλογος
/// «Μη αποθηκευμένες αλλαγές».
///
/// Συνεργάτης του [UserFormDialogState] (Σύνθεση) — δουλεύει πάνω στα πεδία
/// της φόρμας μέσω του host, χωρίς δική του κατάσταση.
class UserFormDismissGuard {
  UserFormDismissGuard(this.host);

  final UserFormDialogState host;

  bool get isDirty {
    if (host.lastNameController.text.trim() != host.snapLastName) return true;
    if (host.firstNameController.text.trim() != host.snapFirstName) {
      return true;
    }
    if (host.phoneController.text.trim() != host.snapPhone) return true;
    if (host.notesController.text.trim() != host.snapNotes) return true;
    if (host.locationController.text.trim() != host.snapLocation) return true;
    if (host.lansweeperUsernameController.text.trim() !=
        host.snapLansweeperUsername) {
      return true;
    }
    // Εμφανιζόμενο κείμενο (όχι μόνο κανονικοποίηση): τόνοι/κεφαλαία μετράνε ως αλλαγή.
    if (host.departmentController.text.trim() != host.initialDepartmentText) {
      return true;
    }
    return false;
  }

  /// Νέος/αντίγραφο χρήστη: υποχρεωτικά όνομα και επώνυμο πριν εμφανιστεί προειδοποίηση.
  bool get _createHasRequiredFields =>
      host.lastNameController.text.trim().isNotEmpty &&
      host.firstNameController.text.trim().isNotEmpty;

  bool get _shouldConfirmDismiss =>
      host.isEdit ? isDirty : _createHasRequiredFields;

  /// Οι τιμές με τις οποίες άνοιξε η φόρμα.
  UserFormFields get _snapshotFields => (
    lastName: host.snapLastName,
    firstName: host.snapFirstName,
    phone: host.snapPhone,
    // Εμφανιζόμενο κείμενο (όχι μόνο κανονικοποίηση): τόνοι/κεφαλαία μετράνε.
    department: host.initialDepartmentText,
    location: host.snapLocation,
    notes: host.snapNotes,
    lansweeper: host.snapLansweeperUsername,
  );

  /// Οι τιμές που έχουν τώρα τα πεδία.
  UserFormFields get _currentFields => (
    lastName: host.lastNameController.text.trim(),
    firstName: host.firstNameController.text.trim(),
    phone: host.phoneController.text.trim(),
    department: host.departmentController.text.trim(),
    location: host.locationController.text.trim(),
    notes: host.notesController.text.trim(),
    lansweeper: host.lansweeperUsernameController.text.trim(),
  );

  List<String> _changedFieldLabels() =>
      changedUserFieldLabels(_snapshotFields, _currentFields);

  Future<_UserFormDismissChoice?> _showDismissConfirmationDialog() async {
    final changes = _changedFieldLabels();
    return showDialog<_UserFormDismissChoice>(
      context: host.context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Μη αποθηκευμένες αλλαγές'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Έχουν γίνει αλλαγές:'),
                const SizedBox(height: 8),
                for (final label in changes) Text('• $label'),
                const SizedBox(height: 12),
                const Text('Θέλεται να γίνει:'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_UserFormDismissChoice.continueEditing),
            child: const Text('Επεξεργασία'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_UserFormDismissChoice.discard),
            child: const Text('Ακύρωση Αλλαγών'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_UserFormDismissChoice.keep),
            child: const Text('Διατήρηση'),
          ),
        ],
      ),
    );
  }

  Future<void> requestClose() async {
    if (!_shouldConfirmDismiss) {
      if (host.mounted) Navigator.of(host.context).pop();
      return;
    }
    final choice = await _showDismissConfirmationDialog();
    if (!host.mounted ||
        choice == null ||
        choice == _UserFormDismissChoice.continueEditing) {
      return;
    }
    if (choice == _UserFormDismissChoice.discard) {
      Navigator.of(host.context).pop();
      return;
    }
    await host.saveFlow.save();
  }

  /// Κουμπί «Ακύρωση»: κλείσιμο χωρίς διάλογο επιβεβαίωσης (εκούσια απόρριψη).
  void cancelAndClose() {
    if (host.mounted) Navigator.of(host.context).pop();
  }

  /// Άδεια να ανοίξει η καρτέλα του εξοπλισμού πάνω από τη φόρμα.
  ///
  /// Διακόπτει **μόνο** για τις αλλαγές που φαίνονται μέσα στην καρτέλα του
  /// εξοπλισμού. Ένα μισογραμμένο τηλέφωνο ή μια σημείωση δεν εμφανίζονται
  /// εκεί, οπότε δεν υπάρχει λόγος να σταματήσουν τον χρήστη — και μένουν
  /// ανέγγιχτες όσο η καρτέλα είναι ανοιχτή.
  ///
  /// Επιστρέφει `true` όταν επιτρέπεται το άνοιγμα.
  Future<bool> requestSideTrip() async {
    final blocking = ownerFacingChangedLabels(_snapshotFields, _currentFields);
    if (blocking.isEmpty) return true;
    final choice = await _showSideTripDialog(blocking);
    if (!host.mounted || choice != _UserFormSideTripChoice.discard) {
      return false;
    }
    restoreOwnerFacingFields();
    return true;
  }

  /// Επαναφορά **μόνο** των πεδίων που φαίνονται στην καρτέλα του εξοπλισμού.
  ///
  /// Ό,τι έχει γραφτεί σε τηλέφωνο και σημειώσεις μένει στη θέση του — δεν
  /// υπάρχει λόγος να πεταχτεί δουλειά που δεν προκαλεί την ασυμφωνία.
  void restoreOwnerFacingFields() {
    host.lastNameController.text = host.snapLastName;
    host.firstNameController.text = host.snapFirstName;
    host.departmentController.text = host.initialDepartmentText;
    host.locationController.text = host.snapLocation;
  }

  Future<_UserFormSideTripChoice?> _showSideTripDialog(
    List<String> changes,
  ) async {
    final discardHint = changes.length == 1
        ? 'Το πεδίο «${changes.single}» επιστρέφει στην αποθηκευμένη τιμή του '
              'και ανοίγει η καρτέλα του εξοπλισμού.'
        : 'Τα πεδία ${changes.map((c) => '«$c»').join(', ')} επιστρέφουν στις '
              'αποθηκευμένες τιμές τους και ανοίγει η καρτέλα του εξοπλισμού.';
    return showDialog<_UserFormSideTripChoice>(
      context: host.context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Μη αποθηκευμένες αλλαγές'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Η καρτέλα του εξοπλισμού διαβάζει από τη βάση το όνομα, '
                  'το τμήμα και την τοποθεσία του κατόχου — όχι όσα γράφετε '
                  'τώρα εδώ. Θα έδειχνε λοιπόν άλλα στοιχεία από αυτή τη φόρμα.',
                ),
                const SizedBox(height: 12),
                const Text('Δεν έχουν αποθηκευτεί:'),
                const SizedBox(height: 8),
                for (final label in changes) Text('• $label'),
              ],
            ),
          ),
        ),
        actions: [
          CompactTooltip(
            message:
                'Κλείνει αυτό το μήνυμα και σας γυρίζει στη φόρμα του '
                'υπαλλήλου. Τίποτα δεν χάνεται και δεν ανοίγει τίποτα.',
            child: TextButton(
              onPressed: () => Navigator.of(
                ctx,
              ).pop(_UserFormSideTripChoice.continueEditing),
              child: const Text('Επιστροφή στη φόρμα'),
            ),
          ),
          Tooltip(
            message: discardHint,
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_UserFormSideTripChoice.discard),
              child: const Text('Απόρριψη αλλαγών και άνοιγμα'),
            ),
          ),
        ],
      ),
    );
  }
}
