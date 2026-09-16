import 'package:flutter/material.dart';

import '../../../core/widgets/draggable_dialog_shell.dart';

/// Ρωτά πριν κλείσει εκκρεμότητα που **ανήκει σε άλλον**.
///
/// Δεν είναι κλειδαριά: η ομάδα δουλεύει με βάρδιες και όποιος λύνει ένα θέμα
/// πρέπει να μπορεί να το κλείσει. Είναι η στιγμή που το λέει δυνατά, ώστε το
/// κλείσιμο να γίνεται με ανοιχτά μάτια αντί να διαπιστώνεται αργότερα στο
/// Ιστορικό.
///
/// Το [closerName] είναι το όνομα με το οποίο θα σφραγιστεί το κλείσιμο —
/// `null` όταν δεν έχει αναγνωριστεί κανείς, οπότε η ερώτηση το παραλείπει
/// αντί να γράψει την παύλα του «άγνωστου» σαν να ήταν όνομα.
///
/// Επιστρέφει `true` μόνο με ρητή επιβεβαίωση — η φυγή με Escape ή κλικ έξω
/// μετρά ως «όχι», που είναι και η ασφαλής έκβαση.
Future<bool> confirmClosingForeignTask(
  BuildContext context, {
  required String assigneeName,
  String? closerName,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => _ForeignTaskCloseConfirmDialog(
      assigneeName: assigneeName,
      closerName: closerName,
    ),
  );
  return answer ?? false;
}

class _ForeignTaskCloseConfirmDialog extends StatelessWidget {
  const _ForeignTaskCloseConfirmDialog({
    required this.assigneeName,
    this.closerName,
  });

  final String assigneeName;
  final String? closerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bold = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );

    return DraggableDialogShell(
      title: const Text('Η εκκρεμότητα ανήκει σε άλλον'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Τα ονόματα μπαίνουν σε ονομαστική, χωρίς να τα κλίνει καμία
              // πρόταση: τα ελληνικά ονόματα δεν κλίνονται από τον κώδικα, και
              // ένα «ανατεθειμένη στον Βλάσης» θα ήταν χειρότερο από την
              // καθαρή παράθεση «ετικέτα: όνομα».
              Text.rich(
                TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    const TextSpan(text: 'Ανατεθειμένη σε: '),
                    TextSpan(text: assigneeName, style: bold),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    const TextSpan(text: 'Θέλετε να κλείσετε την εκκρεμότητα'),
                    if (closerName != null) ...[
                      const TextSpan(text: ' ως '),
                      TextSpan(text: closerName, style: bold),
                    ],
                    const TextSpan(text: ';'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Κλείσιμο εκκρεμότητας'),
          ),
        ],
      ),
    );
  }
}
