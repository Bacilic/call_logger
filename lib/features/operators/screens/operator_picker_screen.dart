import 'package:flutter/material.dart';

import '../../../core/models/operator.dart';
import '../widgets/operator_picker_body.dart';

/// «Ποιος είστε;» — η οθόνη που εμφανίζεται όταν ο λογαριασμός Windows δεν
/// αρκεί για να αναγνωριστεί ο χρήστης.
///
/// Δεν είναι σύνδεση με κωδικό και δεν φυλάει τίποτα: επιλέγει ποιο όνομα θα
/// υπογράφει τις ενέργειες αυτής της συνεδρίας. Το περιεχόμενο (λίστα/φόρμα)
/// ζει στο [OperatorPickerBody], κοινό με τον διάλογο «Αλλαγή χρήστη».
class OperatorPickerScreen extends StatelessWidget {
  const OperatorPickerScreen({
    super.key,
    required this.profiles,
    required this.onPick,
    required this.onCreate,
    this.suggestedName = '',
    this.hasWindowsAccount = true,
  });

  /// Τα ενεργά προφίλ, προς επιλογή. Κενή λίστα στην πρώτη εκκίνηση.
  final List<Operator> profiles;

  final void Function(Operator operator) onPick;

  /// Δημιουργία νέου προφίλ· `bindCurrentAccount` το δένει στον λογαριασμό
  /// Windows ώστε να μην ξαναρωτηθεί.
  final Future<void> Function(String displayName, bool bindCurrentAccount)
  onCreate;

  /// Πρόταση ονόματος — ο λογαριασμός Windows, για να μην πληκτρολογείται.
  final String suggestedName;

  /// Όταν δεν υπάρχει καθόλου λογαριασμός Windows, το δέσιμο δεν προσφέρεται.
  final bool hasWindowsAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.groups_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Ποιος χρησιμοποιεί την εφαρμογή;',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Το όνομα που θα διαλέξετε υπογράφει κάθε ενέργεια στο '
                  'Ιστορικό. Δεν χρειάζεται κωδικός.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                OperatorPickerBody(
                  profiles: profiles,
                  onPick: onPick,
                  onCreate: onCreate,
                  suggestedName: suggestedName,
                  hasWindowsAccount: hasWindowsAccount,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
