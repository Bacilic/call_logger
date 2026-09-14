import 'package:flutter/material.dart';

/// Το ωμό κείμενο ενός σφάλματος — ένα πάτημα μακριά, ποτέ μέσα στο μήνυμα.
///
/// **Γιατί υπάρχει (14/09/2026):** τρία σημεία της περιοχής «Βάση Δεδομένων»
/// έριχναν την εξαίρεση αυτούσια μέσα στην πρόταση που διαβάζει ο χειριστής:
/// «Δεν ήταν δυνατή η φόρτωση στατιστικών: SqfliteFfiException(sqlite_error:
/// 11, SqliteException(11): while selecting from statement, database disk
/// image is malformed… Causing statement: SELECT COUNT(*) AS c FROM
/// "audit_log"…». Τρεις σειρές αγγλικού SQL σε οθόνη που τη βλέπει χειριστής,
/// όχι προγραμματιστής.
///
/// Η λύση δεν είναι να πεταχτεί το ωμό κείμενο: είναι ό,τι θα ζητήσει όποιος
/// κληθεί να βοηθήσει. Είναι να μπει εκεί που το ψάχνει εκείνος και δεν το
/// συναντά ο χειριστής — ακριβώς όπως ήδη κάνει ο διάλογος «Η βάση δεν είναι
/// έγκυρη».
class RawErrorDetailsTile extends StatelessWidget {
  const RawErrorDetailsTile({required this.error, super.key, this.color});

  /// Το σφάλμα, όπως ήρθε. Δεν μεταφράζεται και δεν συνοψίζεται εδώ.
  final Object error;

  /// Χρώμα κειμένου, όταν ο τομέας κάθεται πάνω σε χρωματιστό φόντο.
  final Color? color;

  /// Η ετικέτα του πτυσσόμενου τομέα — ίδια λέξη με τον διάλογο ελέγχου
  /// βάσης, ώστε ο χρήστης να μη μαθαίνει δύο ονόματα για το ίδιο πράγμα.
  static const String label = 'Τεχνικές λεπτομέρειες';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = error.toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final foreground = color ?? theme.colorScheme.onSurfaceVariant;

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(color: foreground),
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: foreground,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
