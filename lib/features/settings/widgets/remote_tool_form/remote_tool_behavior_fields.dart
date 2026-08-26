import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/remote_tool.dart';
import '../../../../core/models/remote_tool_role.dart';

class RoleDropdown extends StatelessWidget {
  const RoleDropdown({super.key, required this.value, required this.onChanged});

  final ToolRole value;
  final ValueChanged<ToolRole>? onChanged;

  static String _label(ToolRole r) {
    return switch (r) {
      ToolRole.generic => 'Κανένα – Χωρίς αυτόματο στόχο',
      ToolRole.anydesk => 'AnyDesk-like',
      ToolRole.rdp => 'RDP Hostname/IP',
      ToolRole.vnc => 'VNC Host',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<ToolRole>(
          key: ValueKey(value),
          initialValue: value,
          decoration: const InputDecoration(
            labelText: 'Ρόλος',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final r in ToolRole.values)
              DropdownMenuItem(value: r, child: Text(_label(r))),
          ],
          onChanged: onChanged == null
              ? null
              : (ToolRole? v) {
                  if (v != null) onChanged!(v);
                },
        ),
        if (value == ToolRole.generic) ...[
          const SizedBox(height: 8),
          Text(
            'Χρειάζεται χειροκίνητο στόχο (παράμετρο) ανά εξοπλισμό· χωρίς αυτόν δεν εμφανίζεται στην κλήση.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Εσωτερική ετικέτα συμβατότητας: καθορίζει πώς επιλύεται ο στόχος σύνδεσης μέσω '
                'CallRemoteTargets.resolvedLaunchTarget (όχι ελεύθερο κείμενο στη βάση).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}


/// Η **κοινή** αναμονή του εργαλείου μετά την εκκίνηση, σε δευτερόλεπτα.
///
/// Η απομακρυσμένη επιφάνεια αργεί να εμφανιστεί και η εφαρμογή δεν μαθαίνει
/// ποτέ πότε φόρτωσε: το πρόγραμμα ζωγραφίζει σε δικό του παράθυρο, χωρίς να
/// στέλνει σήμα. Στο ενδιάμεσο κενό, κάθε πάτημα του κουμπιού άνοιγε **νέα
/// συνεδρία**. Εδώ δηλώνεται πόσο μένει κλειδωμένο.
class SharedConnectWaitField extends StatelessWidget {
  const SharedConnectWaitField({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('remote_tool_shared_connect_wait_field'),
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Αναμονή μετά την εκκίνηση',
            border: OutlineInputBorder(),
            suffixText: 'δευτερόλεπτα',
            helperText:
                'Πόσο μένει κλειδωμένο το κουμπί ώσπου να ανοίξει η '
                'απομακρυσμένη επιφάνεια. 0 = χωρίς κλείδωμα.',
            helperMaxLines: 3,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Κοινή τιμή για όλη την ομάδα, ως αφετηρία — έως '
                '${RemoteTool.maxConnectWaitSeconds} δευτερόλεπτα. Ο κάθε '
                'υπολογιστής μπορεί να δηλώσει τη δική του παρακάτω.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
