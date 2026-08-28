import 'package:flutter/material.dart';

/// Πλαίσιο μηνύματος μέσα στους διαλόγους ενεργειών διακομιστή.
///
/// Ζει χωριστά επειδή το μοιράζονται όλοι: η επανεκκίνηση ουράς, ο καθαρισμός
/// ορφανών, η εκκαθάριση ουρών και η επανεκκίνηση διακομιστή. Το κείμενο είναι
/// **επιλέξιμο** επίτηδες — τα μηνύματα σφάλματος συχνά καταλήγουν σε αίτημα
/// προς το ΙΤ, και η αντιγραφή δεν πρέπει να απαιτεί πληκτρολόγηση.
class ServerActionBanner extends StatelessWidget {
  const ServerActionBanner({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(text, style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
