import 'package:flutter/material.dart';

import '../providers/active_sessions_provider.dart';
import '../services/active_sessions.dart';

/// Ρωτά «ποιος άλλος έχει τη βάση ανοιχτή;» πριν από επικίνδυνη ενέργεια.
///
/// **Ένα σημείο επιβολής για όλες τις ροές.** Το συμβόλαιο είναι: κάθε ενέργεια
/// που αναδιατάσσει ή αντικαθιστά ολόκληρο το αρχείο της βάσης λέει πρώτα ποια
/// άλλα μηχανήματα το κρατούν αυτή τη στιγμή. Αν ο έλεγχος ζούσε αντιγραμμένος
/// μέσα σε κάθε κουμπί, η επόμενη ροή που θα προστεθεί θα τον ξεχνούσε σιωπηλά.
///
/// **Προειδοποιεί, δεν κλειδώνει.** Η παρουσία είναι ίχνος, όχι βεβαιότητα: μετά
/// από απότομο κλείσιμο ένα φάντασμα ζει όσο το παράθυρο φρεσκάδας, και μια
/// απαγόρευση θα κρατούσε τον συντηρητή έξω για λόγο που δεν υπάρχει. Η απόφαση
/// μένει στον άνθρωπο, αλλά παύει να παίρνεται στα τυφλά.
///
/// Επιστρέφει `true` όταν η ενέργεια μπορεί να προχωρήσει — και **χωρίς καθόλου
/// διάλογο** όταν καμία άλλη συνεδρία δεν είναι ανοιχτή, ώστε όποιος δουλεύει
/// μόνος να μη μαθαίνει να πατά «Συνέχεια» χωρίς να διαβάζει.
Future<bool> confirmDespiteOtherSessions(
  BuildContext context, {
  required String actionLabel,
  Future<List<ActiveSession>> Function()? loadSessions,
}) async {
  final sessions = await (loadSessions ?? loadActiveSessions)();
  final others = otherSessions(sessions);
  if (others.isEmpty) return true;
  if (!context.mounted) return false;

  final now = DateTime.now();
  final mine = myAppVersion(sessions);

  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: theme.colorScheme.tertiary,
        ),
        title: const Text('Η βάση είναι ανοιχτή αλλού'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _openElsewhereSentence(others.length, actionLabel),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final session in others)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          describeActiveSession(
                            session,
                            now: now,
                            myAppVersion: mine,
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
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
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Συνέχεια παρ\' όλα αυτά'),
          ),
        ],
      );
    },
  );
  return proceed == true;
}

/// «Ένας ακόμη υπολογιστής έχει…» / «Δύο ακόμη υπολογιστές έχουν…»
///
/// Το πλήθος μετρά **συνεδρίες** και όχι μηχανήματα, γιατί αυτό ακριβώς ρωτά ο
/// συντηρητής: πόσες ανοιχτές εφαρμογές θα βρει η ενέργεια στη μέση της δουλειάς
/// τους.
String _openElsewhereSentence(int count, String actionLabel) {
  final subject = count == 1
      ? 'Μία ακόμη εφαρμογή έχει'
      : '$count ακόμη εφαρμογές έχουν';
  return '$subject τη βάση ανοιχτή αυτή τη στιγμή. '
      'Η ενέργεια «$actionLabel» θα τις βρει στη μέση της δουλειάς τους.';
}
