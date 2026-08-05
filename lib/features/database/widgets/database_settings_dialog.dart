import 'package:flutter/material.dart';

import '../../../core/widgets/dialog_snackbar_scope.dart';
import 'database_settings_panel.dart';

/// Ανοίγει τον διάλογο «Ρυθμίσεις βάσης δεδομένων».
///
/// Το φράγμα ΔΕΝ κλείνει τον διάλογο: φιλοξενεί ρυθμίσεις και μακρές ροές
/// (αντίγραφα ασφαλείας, έλεγχος ακεραιότητας) όπου ένα κατά λάθος κλικ έξω θα
/// έχανε δουλειά. Μοναδικός τρόπος κλεισίματος: το κουμπί «Κλείσιμο».
Future<void> showDatabaseSettingsDialog(
  BuildContext context, {
  required Future<void> Function() onDatabaseLifecycleChanged,
  @visibleForTesting WidgetBuilder? panelBuilder,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DatabaseSettingsDialog(
      onDatabaseLifecycleChanged: onDatabaseLifecycleChanged,
      panelBuilder: panelBuilder,
    ),
  );
}

/// Διάλογος «Ρυθμίσεις βάσης δεδομένων» — φιλοξενεί το [DatabaseSettingsPanel]
/// μέσα σε [DialogSnackbarScope], ώστε τα snackbar των ροών του (χειροκίνητο
/// αντίγραφο, συνέχεια «χαμένου φακέλου») να εμφανίζονται στο επίπεδο του
/// διαλόγου και όχι πίσω από το φράγμα, στο ριζικό Scaffold.
class DatabaseSettingsDialog extends StatefulWidget {
  const DatabaseSettingsDialog({
    super.key,
    required this.onDatabaseLifecycleChanged,
    this.panelBuilder,
  });

  /// Μετά από επιτυχή αλλαγή διαδρομής ή δημιουργία νέου αρχείου βάσης.
  final Future<void> Function() onDatabaseLifecycleChanged;

  /// Μόνο για τεστ: ελαφρύ υποκατάστατο του πάνελ. Το πραγματικό πάνελ ανοίγει
  /// τη βάση και διαβάζει αρχεία στο initState, οπότε δεν γίνεται pump σε
  /// widget test χωρίς να κρεμάσει.
  @visibleForTesting
  final WidgetBuilder? panelBuilder;

  @override
  State<DatabaseSettingsDialog> createState() => _DatabaseSettingsDialogState();
}

class _DatabaseSettingsDialogState extends State<DatabaseSettingsDialog>
    with DialogSnackbarHost {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
          // Το [DialogSnackbarScope] φέρνει μαζί του Scaffold: μένει ΜΕΣΑ στο
          // πλαίσιο του διαλόγου αντί να απλώνεται αόρατα σε όλη την οθόνη.
          child: DialogSnackbarScope(
            messengerKey: dialogMessengerKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child:
                        widget.panelBuilder?.call(context) ??
                        DatabaseSettingsPanel(
                          onDatabaseLifecycleChanged:
                              widget.onDatabaseLifecycleChanged,
                        ),
                  ),
                ),
                // Στο κέλυφος και όχι μέσα στο πάνελ: το περιεχόμενο κυλάει,
                // το κλείσιμο πρέπει να μένει πάντα ορατό.
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Κλείσιμο'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
