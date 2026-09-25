import 'package:flutter/material.dart';

import '../../../core/models/operator.dart';

/// Η ρητή συγκατάθεση για προφίλ διαχειριστή που είναι συνδεδεμένο αλλού.
///
/// **Γιατί υπάρχει εξαίρεση.** Τα προφίλ δεν έχουν κωδικούς, άρα η φραγή δεν
/// είναι κλειδαριά — είναι φρουρός που εμποδίζει το κατά λάθος. Αν ίσχυε και
/// για τους διαχειριστές, μια εφαρμογή που κόλλησε σε άλλο μηχάνημα θα
/// κρατούσε τον άνθρωπο έξω χωρίς κανέναν δρόμο επιστροφής.
///
/// **Γιατί ρωτά.** Δύο ανοιχτές συνεδρίες με το ίδιο προφίλ δεν είναι αθώες:
/// μοιράζονται τις προσωπικές ρυθμίσεις (όποιος αλλάξει τελευταίος νικά) και
/// υπογράφουν με το ίδιο όνομα στο Ιστορικό. Η απόφαση μένει στον άνθρωπο,
/// αλλά παύει να παίρνεται στα τυφλά.
Future<bool> confirmAdminProfileOpenElsewhere(
  BuildContext context, {
  required Operator operator,
  required String station,
}) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: theme.colorScheme.tertiary,
        ),
        title: const Text('Το προφίλ είναι ήδη συνδεδεμένο'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Το προφίλ «${operator.displayName}» είναι αυτή τη στιγμή '
                'συνδεδεμένο στον $station.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Δύο συνεδρίες με το ίδιο προφίλ μοιράζονται τις προσωπικές '
                'ρυθμίσεις — όποιος τις αλλάξει τελευταίος επικρατεί — και '
                'υπογράφουν με το ίδιο όνομα στο Ιστορικό.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Η ένδειξη είναι ίχνος, όχι βεβαιότητα: μετά από απότομο '
                'κλείσιμο κάποιος μπορεί να φαίνεται εδώ ως τρία λεπτά.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Συνέχεια'),
          ),
        ],
      );
    },
  );
  return proceed ?? false;
}
