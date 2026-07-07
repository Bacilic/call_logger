import 'package:flutter/material.dart';

import '../../../../core/models/remote_tool_role.dart';

class RoleDropdown extends StatelessWidget {
  const RoleDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

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
            Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
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
