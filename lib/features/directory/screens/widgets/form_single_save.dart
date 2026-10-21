import 'package:flutter/material.dart';

/// Μία αποθήκευση τη φορά, για τις καρτέλες Καταλόγου (υπάλληλος, τμήμα,
/// εξοπλισμός).
///
/// Στη δικτυακή βάση η εγγραφή συνεχίζει για δευτερόλεπτα αφού απαντηθεί η
/// τελευταία ερώτηση. Χωρίς φρένο η φόρμα έμενε ανοιχτή με ενεργή την
/// «Αποθήκευση», και ένα δεύτερο πάτημα ξεκινούσε δεύτερη αποθήκευση πάνω στην
/// πρώτη. Η πρώτη τελείωνε, αλλά δεν μπορούσε να κλείσει τη φόρμα, γιατί από
/// πάνω της ήταν οι ερωτήσεις της δεύτερης. Η δεύτερη έβρισκε την καρτέλα
/// αλλαγμένη και ανακοίνωνε «Κάποιος πρόλαβε» για τη δουλειά του ίδιου του
/// χρήστη. Κάθε νέο πάτημα ξανάρχιζε τον κύκλο.
///
/// Όσο τρέχει μια αποθήκευση: η «Αποθήκευση» δεν δέχεται πάτημα, η «Ακύρωση»
/// και το κλείσιμο της φόρμας δεν γίνονται — η εγγραφή δεν σταματά στη μέση,
/// οπότε μια ακύρωση εκεί θα έλεγε ψέματα.
mixin FormSingleSave<T extends StatefulWidget> on State<T> {
  bool _saveInProgress = false;

  /// Τρέχει τώρα μια αποθήκευση αυτής της φόρμας.
  bool get saveInProgress => _saveInProgress;

  /// Εκτελεί το [save] — εκτός αν τρέχει ήδη άλλη αποθήκευση, οπότε δεν κάνει
  /// τίποτα.
  Future<void> runSingleSave(Future<void> Function() save) async {
    if (_saveInProgress) return;
    setState(() => _saveInProgress = true);
    try {
      await save();
    } finally {
      if (mounted) setState(() => _saveInProgress = false);
    }
  }
}

/// Το κουμπί «Αποθήκευση»/«Προσθήκη» των καρτελών Καταλόγου.
///
/// Όσο τρέχει η αποθήκευση [saving] είναι ανενεργό και, όταν η φόρμα είναι
/// μπροστά, γράφει «Αποθηκεύεται…» με ένα κυκλάκι που γυρίζει. Πίσω από τις
/// ερωτήσεις της αποθήκευσης το κυκλάκι δεν θα το έβλεπε κανείς, οπότε εκεί
/// μένει μόνο ανενεργό.
class FormSaveButton extends StatelessWidget {
  const FormSaveButton({
    super.key,
    required this.label,
    required this.saving,
    required this.onPressed,
  });

  final String label;
  final bool saving;

  /// `null` = ανενεργό για λόγο της φόρμας (π.χ. καμία αλλαγή).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final showProgress = saving && (ModalRoute.isCurrentOf(context) ?? true);
    return FilledButton(
      onPressed: saving ? null : onPressed,
      child: showProgress
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Αποθηκεύεται…'),
              ],
            )
          : Text(label),
    );
  }
}
