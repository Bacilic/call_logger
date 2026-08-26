import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// «Χρόνος αναμονής σε αυτόν τον υπολογιστή» — η τοπική παράκαμψη ενός
/// εργαλείου.
///
/// Πόσο κρατά κλειδωμένο το κουμπί σύνδεσης μέχρι να προλάβει να εμφανιστεί η
/// απομακρυσμένη επιφάνεια. Η αφετηρία είναι κοινή ανά εργαλείο (το RDP αργεί,
/// το AnyDesk όχι), αλλά ο πραγματικός χρόνος εξαρτάται από την ταχύτητα
/// **αυτού** του μηχανήματος: ο συνάδελφος με το γρήγορο PC δεν έχει λόγο να
/// περιμένει τον χρόνο του πιο αργού.
///
/// **Αποθηκεύεται με το κουμπί «Αποθήκευση» του διαλόγου, όπως κάθε άλλο
/// πεδίο.** Η τιμή ταξιδεύει αλλού από τον κοινό ορισμό — στις προτιμήσεις
/// αυτού του υπολογιστή — αλλά ο χρήστης βλέπει μία φόρμα και κάνει μία
/// κίνηση. Ως τώρα γραφόταν μόνη της μόλις έφευγε η εστίαση, με το κουμπί
/// αποθήκευσης να μένει γκρι: κανείς δεν μάθαινε ποτέ αν η τιμή πιάστηκε.
class LocalConnectWaitOverrideField extends StatelessWidget {
  const LocalConnectWaitOverrideField({
    super.key,
    required this.controller,
    required this.sharedSeconds,
    required this.onUseShared,
    this.visible = true,
    this.enabled = true,
  });

  final TextEditingController controller;

  /// Η κοινή τιμή του ορισμού, για να φαίνεται τι ισχύει χωρίς παράκαμψη.
  final int sharedSeconds;

  final VoidCallback onUseShared;

  /// `false` για εργαλείο που δεν έχει αποθηκευτεί ακόμη, ή ώσπου να φορτώσουν
  /// οι τοπικές τιμές: δεν υπάρχει ταυτότητα για να δεθεί η παράκαμψη.
  final bool visible;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final hasOverride = controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.hourglass_bottom,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'Χρόνος αναμονής σε αυτόν τον υπολογιστή',
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          hasOverride
              ? 'Ισχύει μόνο εδώ. Οι συνάδελφοι συνεχίζουν με τα '
                    '$sharedSeconds δευτερόλεπτα του ορισμού.'
              : 'Αν αυτό το μηχάνημα ανοίγει τη σύνδεση πιο γρήγορα ή πιο '
                    'αργά, δηλώστε τα δικά του δευτερόλεπτα — η κοινή τιμή '
                    'μένει ανέπαφη για τους υπόλοιπους.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('remote_tool_local_connect_wait_override_field'),
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            suffixText: 'δευτερόλεπτα',
            hintText: '$sharedSeconds',
            helperText: 'Κενό = χρησιμοποιείται η κοινή τιμή',
          ),
        ),
        if (hasOverride) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('remote_tool_use_shared_connect_wait_button'),
              onPressed: enabled ? onUseShared : null,
              icon: const Icon(Icons.settings_backup_restore, size: 18),
              label: const Text('Χρήση της κοινής τιμής'),
            ),
          ),
        ],
      ],
    );
  }
}
