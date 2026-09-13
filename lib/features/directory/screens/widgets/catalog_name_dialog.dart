import 'package:flutter/material.dart';

import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../providers/building_catalog_provider.dart';

/// Μικρή φόρμα ονόματος για τους διαχειριζόμενους καταλόγους (κτίρια, ομάδες).
///
/// **Ο controller ζει μέσα στο widget, όχι στον καλούντα.** Ο προφανής
/// τρόπος — `showDialog(...).whenComplete(controller.dispose)` — σκοτώνει τον
/// controller τη στιγμή του `pop`, ενώ ο διάλογος ζει ακόμη: φεύγει με
/// μετάβαση, και ο Navigator τον ξαναχτίζει μόλις πάψει να είναι ο τρέχων.
/// Το `TextField` τότε ξαναδένεται σε νεκρό controller και ρίχνει την
/// εφαρμογή. Με τον controller εδώ, ο θάνατός του συμπίπτει με τον θάνατο
/// του πεδίου — που είναι η μόνη στιγμή που είναι ασφαλής.
class _CatalogNameDialog extends StatefulWidget {
  const _CatalogNameDialog({
    required this.title,
    required this.actionLabel,
    required this.fieldLabel,
    required this.emptyMessage,
    required this.sameEntityPhrase,
    required this.catalog,
    this.initial,
    this.allowSelf,
  });

  final String title;
  final String actionLabel;
  final String fieldLabel;

  /// Τι λέει ο έλεγχος όταν το πεδίο είναι κενό.
  final String emptyMessage;

  /// Το κλείσιμο του μηνύματος διπλότυπου — «είναι το ίδιο κτίριο.» κ.λπ.
  final String sameEntityPhrase;

  final List<String> catalog;
  final String? initial;

  /// Το όνομα που επιτρέπεται να «συγκρουστεί» με τον εαυτό του, στη
  /// μετονομασία.
  final String? allowSelf;

  @override
  State<_CatalogNameDialog> createState() => _CatalogNameDialogState();
}

class _CatalogNameDialogState extends State<_CatalogNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  /// Ο έλεγχος αγνοεί αλφάβητο και τόνους: «Β» και «B» είναι το ίδιο πράγμα,
  /// και το να μπουν και τα δύο στη λίστα θα αναπαρήγαγε το πρόβλημα που
  /// λύνει ο κατάλογος.
  String? _validate(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return widget.emptyMessage;
    final clash = matchBuildingInCatalog(name, widget.catalog);
    if (clash == null || clash == widget.allowSelf) return null;
    return clash == name
        ? 'Υπάρχει ήδη στη λίστα.'
        : 'Υπάρχει ήδη ως «$clash» — ${widget.sameEntityPhrase}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableDialogShell(
      title: Text(widget.title),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 380,
          child: Form(
            key: _formKey,
            child: TextFormField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.fieldLabel,
                border: const OutlineInputBorder(),
              ),
              validator: _validate,
              onFieldSubmitted: (_) => _submit(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
        ],
      ),
    );
  }
}

/// Ανοίγει τη φόρμα ονόματος και επιστρέφει το όνομα, ή `null` στην ακύρωση.
Future<String?> showCatalogNameDialog({
  required BuildContext context,
  required String title,
  required String actionLabel,
  required String fieldLabel,
  required String emptyMessage,
  required String sameEntityPhrase,
  required List<String> catalog,
  String? initial,
  String? allowSelf,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CatalogNameDialog(
      title: title,
      actionLabel: actionLabel,
      fieldLabel: fieldLabel,
      emptyMessage: emptyMessage,
      sameEntityPhrase: sameEntityPhrase,
      catalog: catalog,
      initial: initial,
      allowSelf: allowSelf,
    ),
  );
}
