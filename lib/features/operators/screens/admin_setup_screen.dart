import 'package:flutter/material.dart';

import '../../../core/models/operator.dart';

/// «Αυτή η βάση δεν έχει διαχειριστή» — η οθόνη που ξεκλειδώνει τη διαχείριση
/// προφίλ όταν η σήμανση έχει χαθεί.
///
/// Δεν αποφασίζει τίποτα μόνη της: δείχνει τα ενεργά προφίλ και παραδίδει την
/// επιλογή. Η σιωπηρή αυτόματη προαγωγή απορρίφθηκε επίτηδες — θα έδινε την
/// εξουσία σε όποιον έτυχε να είναι πρώτος στη λίστα, χωρίς να το μάθει κανείς.
class AdminSetupScreen extends StatefulWidget {
  const AdminSetupScreen({
    super.key,
    required this.candidates,
    required this.onChoose,
  });

  /// Τα ενεργά προφίλ της βάσης. Ποτέ κενή — αλλιώς η οθόνη δεν εμφανίζεται.
  final List<Operator> candidates;

  /// Ορίζει το προφίλ ως διαχειριστή. Επιστρέφει μήνυμα σφάλματος όταν ο
  /// ορισμός δεν πέρασε, `null` όταν πέτυχε.
  final Future<String?> Function(Operator chosen) onChoose;

  @override
  State<AdminSetupScreen> createState() => _AdminSetupScreenState();
}

class _AdminSetupScreenState extends State<AdminSetupScreen> {
  Operator? _busyWith;

  Future<void> _choose(Operator candidate) async {
    if (_busyWith != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ορισμός διαχειριστή'),
        content: Text(
          'Να οριστεί «${candidate.displayName}» ως διαχειριστής αυτής της '
          'βάσης;\n\nΜόνο ο διαχειριστής μπορεί να δημιουργεί και να αλλάζει '
          'προφίλ χρηστών. Η αλλαγή καταγράφεται στο Ιστορικό.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ορισμός'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyWith = candidate);
    final problem = await widget.onChoose(candidate);
    if (!mounted) return;
    setState(() => _busyWith = null);

    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(problem),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _busyWith != null;

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
                  Icons.admin_panel_settings_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Αυτή η βάση δεν έχει διαχειριστή',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Χωρίς διαχειριστή κανείς δεν μπορεί να δημιουργήσει ή να '
                  'αλλάξει προφίλ χρηστών. Διαλέξτε ποιος θα είναι — μπορεί να '
                  'αλλάξει αργότερα από την οθόνη «Χρήστες».',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final candidate in widget.candidates)
                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(candidate.displayName),
                          subtitle: candidate.windowsAccount == null
                              ? null
                              : Text(candidate.windowsAccount!),
                          trailing: _busyWith == candidate
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.chevron_right),
                          enabled: !busy,
                          onTap: () => _choose(candidate),
                        ),
                    ],
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
