import 'package:flutter/material.dart';

import '../services/database_label.dart';

/// Το αποτέλεσμα του διαλόγου ονόματος βάσης.
///
/// Τυλιγμένο σε αντικείμενο επίτηδες: σκέτο `String?` δεν θα ξεχώριζε το
/// «ακύρωσα» από το «θέλω να σβήσω το όνομα» — δύο εντελώς διαφορετικές
/// προθέσεις που θα κατέληγαν στην ίδια τιμή.
class DatabaseLabelResult {
  const DatabaseLabelResult(this.value);

  /// Το νέο όνομα· `null` σημαίνει «χωρίς όνομα».
  final String? value;
}

/// Ζητά από τον χρήστη όνομα για την τρέχουσα βάση.
///
/// Επιστρέφει `null` όταν ο χρήστης ακύρωσε — τότε δεν αποθηκεύεται τίποτα.
Future<DatabaseLabelResult?> showDatabaseLabelDialog({
  required BuildContext context,
  required String? currentLabel,
}) {
  return showDialog<DatabaseLabelResult>(
    context: context,
    builder: (_) => _DatabaseLabelDialog(currentLabel: currentLabel),
  );
}

/// **Ο controller ζει μέσα στο widget, όχι στον καλούντα.** Ένα
/// `whenComplete(controller.dispose)` θα τον σκότωνε τη στιγμή του `pop`, ενώ
/// ο διάλογος φεύγει ακόμη με μετάβαση — και το πεδίο, που ξαναχτίζεται στο
/// μεταξύ, θα ξαναδενόταν σε νεκρό controller και θα έριχνε την εφαρμογή.
class _DatabaseLabelDialog extends StatefulWidget {
  const _DatabaseLabelDialog({required this.currentLabel});

  final String? currentLabel;

  @override
  State<_DatabaseLabelDialog> createState() => _DatabaseLabelDialogState();
}

class _DatabaseLabelDialogState extends State<_DatabaseLabelDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentLabel ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save(String value) => Navigator.of(
    context,
  ).pop(DatabaseLabelResult(normalizeDatabaseLabel(value)));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Όνομα βάσης'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Το όνομα αποθηκεύεται μέσα στη βάση και ταξιδεύει μαζί της. '
            'Βοηθά να ξεχωρίζετε ποιο αρχείο κοιτάτε — π.χ. «Παραγωγή ΓΝΚ» '
            'ή «Δοκιμαστική σπιτιού».',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: kDatabaseLabelMaxLength,
            decoration: const InputDecoration(
              labelText: 'Όνομα',
              hintText: 'Παραγωγή ΓΝΚ',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: _save,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: () => _save(_controller.text),
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
