import 'package:flutter/material.dart';

/// «Διαδρομή σε αυτόν τον υπολογιστή» — η τοπική παράκαμψη ενός εργαλείου.
///
/// Ο ορισμός του εργαλείου (όνομα, παράμετροι, εικονίδιο, σειρά) είναι κοινός
/// για όλη την ομάδα· μόνο το πού βρίσκεται το πρόγραμμα αλλάζει από μηχάνημα
/// σε μηχάνημα. Ως τώρα, όποιος διόρθωνε τη διαδρομή για το δικό του μηχάνημα
/// τη χαλούσε για όλους (Φάση 3).
///
/// Δείχνει τρεις καταστάσεις, γιατί ο χρήστης πρέπει να ξεχωρίζει το «δεν
/// δήλωσα τίποτα» από το «δήλωσα ρητά κενή»:
/// 1. **Χωρίς παράκαμψη** — ισχύει η κοινή διαδρομή.
/// 2. **Με παράκαμψη** — ισχύει η δική του, με κουμπί επιστροφής στην κοινή.
/// 3. **Με κενή παράκαμψη** — «κανένα πρόγραμμα εδώ», ρητά δηλωμένο.
///
/// **Αποθηκεύεται με το κουμπί «Αποθήκευση» του διαλόγου, όπως κάθε άλλο
/// πεδίο.** Ως τώρα γραφόταν μόνη της, και μάλιστα μόνο με Enter: όποιος
/// έγραφε τη διαδρομή και πήγαινε αλλού την έχανε σιωπηλά, ενώ το κουμπί
/// αποθήκευσης έμενε γκρι και δεν έδινε καμία απάντηση.
class LocalExecutablePathOverrideField extends StatelessWidget {
  const LocalExecutablePathOverrideField({
    super.key,
    required this.controller,
    required this.sharedPath,
    required this.hasOverride,
    required this.onOverridden,
    required this.onUseShared,
    this.visible = true,
    this.enabled = true,
    this.onPick,
  });

  final TextEditingController controller;

  /// Η κοινή διαδρομή του ορισμού, για να φαίνεται τι ισχύει χωρίς παράκαμψη.
  final String sharedPath;

  /// Η τρίτη κατάσταση δεν προκύπτει από το κείμενο: κενό πεδίο σημαίνει άλλο
  /// πράγμα όταν η παράκαμψη έχει δηλωθεί («κανένα πρόγραμμα εδώ») και άλλο
  /// όταν δεν έχει («ακολουθώ την κοινή»).
  final bool hasOverride;

  /// Πληκτρολόγηση στο πεδίο σημαίνει «θέλω δική μου».
  final VoidCallback onOverridden;

  final VoidCallback onUseShared;

  /// `false` για εργαλείο που δεν έχει αποθηκευτεί ακόμη, ή ώσπου να φορτώσουν
  /// οι τοπικές τιμές: δεν υπάρχει ταυτότητα για να δεθεί η παράκαμψη.
  final bool visible;

  final bool enabled;

  /// Επιλογή αρχείου· επιστρέφει τη διαδρομή ή `null` στην ακύρωση.
  final Future<String?> Function()? onPick;

  Future<void> _pick() async {
    final picked = await onPick?.call();
    if (picked == null) return;
    controller.text = picked;
    onOverridden();
  }

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final shared = sharedPath.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.computer_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'Διαδρομή σε αυτόν τον υπολογιστή',
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          hasOverride
              ? 'Ισχύει μόνο εδώ. Οι συνάδελφοι συνεχίζουν με την κοινή '
                    'διαδρομή.'
              : 'Αν το πρόγραμμα βρίσκεται αλλού σε αυτό το μηχάνημα, '
                    'δηλώστε το εδώ — η κοινή διαδρομή μένει ανέπαφη για τους '
                    'υπόλοιπους.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('remote_tool_local_path_override_field'),
                controller: controller,
                enabled: enabled,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: shared.isEmpty ? null : shared,
                  helperText: hasOverride
                      ? null
                      : 'Κενό = χρησιμοποιείται η κοινή διαδρομή',
                ),
                onChanged: enabled ? (_) => onOverridden() : null,
              ),
            ),
            if (onPick != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: enabled ? _pick : null,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Αναζήτηση'),
              ),
            ],
          ],
        ),
        if (hasOverride) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('remote_tool_use_shared_path_button'),
              onPressed: enabled ? onUseShared : null,
              icon: const Icon(Icons.settings_backup_restore, size: 18),
              label: const Text('Χρήση της κοινής διαδρομής'),
            ),
          ),
        ],
      ],
    );
  }
}
