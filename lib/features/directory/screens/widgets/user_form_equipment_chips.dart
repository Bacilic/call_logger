import 'package:flutter/material.dart';

import '../../../calls/models/equipment_model.dart';
import '../../services/user_equipment_codes.dart';

/// Ένας εξοπλισμός της κάρτας μαζί με το πόσοι υπάλληλοι τον κρατούν.
typedef UserEquipmentChipEntry = ({EquipmentModel equipment, int ownerCount});

/// Ο εξοπλισμός του υπαλλήλου μέσα στη φόρμα του, ως chips με τον κωδικό.
///
/// Καθαρά παρουσιαστικό: δέχεται έτοιμα στοιχεία και ειδοποιεί για το κλικ —
/// δεν διαβάζει τη βάση και δεν ανοίγει διαλόγους μόνο του.
class UserFormEquipmentChips extends StatelessWidget {
  const UserFormEquipmentChips({
    super.key,
    required this.entries,
    required this.onTapEquipment,
  });

  final List<UserEquipmentChipEntry> entries;
  final void Function(EquipmentModel equipment) onTapEquipment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Row(
          children: [
            Icon(
              Icons.devices_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text('Εξοπλισμός', style: theme.textTheme.labelLarge),
            if (entries.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                '${entries.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text(
            'Δεν κουβαλά εξοπλισμό.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in entries)
                _EquipmentChip(
                  entry: entry,
                  onTap: () => onTapEquipment(entry.equipment),
                ),
            ],
          ),
      ],
    );
  }
}

/// Η υπόδειξη του chip: «Υπολογιστής — 1ος - Γραφεία», με τη γραμμή του
/// κοινόχρηστου όταν τον εξοπλισμό τον κρατούν περισσότεροι από ένας.
///
/// `null` όταν δεν υπάρχει τίποτα πέρα από τον κωδικό — αυτόν τον γράφει ήδη
/// το ίδιο το chip, και υπόδειξη που τον επαναλαμβάνει δεν λέει τίποτα.
String? userEquipmentChipTooltip(UserEquipmentChipEntry entry) {
  final equipment = entry.equipment;
  final parts = <String>[];
  final type = equipment.type?.trim();
  if (type != null && type.isNotEmpty) parts.add(type);
  final location = equipment.location?.trim();
  if (location != null && location.isNotEmpty) parts.add(location);
  final lines = <String>[
    if (parts.isNotEmpty) parts.join(' — '),
    if (entry.ownerCount > 1)
      'Κοινόχρηστος: τον κρατούν ${entry.ownerCount} υπάλληλοι.',
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

class _EquipmentChip extends StatelessWidget {
  const _EquipmentChip({required this.entry, required this.onTap});

  final UserEquipmentChipEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = ActionChip(
      label: Text(UserEquipmentCodes.codeLabel(entry.equipment)),
      avatar: entry.ownerCount > 1
          ? const Icon(Icons.people_outline, size: 18)
          : null,
      onPressed: onTap,
    );
    final tooltip = userEquipmentChipTooltip(entry);
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip, child: chip);
  }
}
