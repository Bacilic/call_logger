import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/main_nav_request_provider.dart';
import '../../../../core/widgets/main_nav_destination.dart';
import '../../../calls/layout/call_form_clear.dart';
import '../../../calls/provider/smart_entity_selector_provider.dart';
import '../../models/equipment_column.dart';

enum _BulkGuardChoice { cancel, discardCall, goToCall }

/// True όταν η ανοιχτή φόρμα κλήσης αναφέρεται σε κάποιον από τους
/// [selectedRows] (ως επιλεγμένος εξοπλισμός ή ως κείμενο κωδικού).
bool openCallInvolvesSelectedEquipment(
  WidgetRef ref,
  List<EquipmentRow> selectedRows,
) {
  final smart = ref.read(callSmartEntityProvider);
  if (!smart.hasAnyContent) return false;

  final selectedIds = {
    for (final row in selectedRows)
      if (row.$1.id != null) row.$1.id!,
  };
  if (selectedIds.isEmpty) return false;

  final equipmentId = smart.selectedEquipment?.id;
  if (equipmentId != null && selectedIds.contains(equipmentId)) return true;

  final typed = smart.equipmentText.trim().toLowerCase();
  if (typed.isEmpty) return false;
  for (final row in selectedRows) {
    final code = (row.$1.code ?? '').trim().toLowerCase();
    if (code.isNotEmpty && code == typed) return true;
  }
  return false;
}

/// Φρουρός πριν από μαζική ενέργεια εξοπλισμού: όταν η ανοιχτή κλήση αφορά
/// επιλεγμένο εξοπλισμό, ο χρήστης αποφασίζει πρώτα για την κλήση.
///
/// Επιστρέφει true όταν η ενέργεια επιτρέπεται να προχωρήσει.
Future<bool> ensureBulkEquipmentActionAllowed(
  BuildContext context,
  WidgetRef ref,
  List<EquipmentRow> selectedRows,
) async {
  if (!openCallInvolvesSelectedEquipment(ref, selectedRows)) return true;

  final choice = await showDialog<_BulkGuardChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Ανοιχτή κλήση'),
      content: const Text(
        'Η ανοιχτή κλήση αφορά επιλεγμένο εξοπλισμό. '
        'Ολοκληρώστε ή διακόψτε πρώτα την κλήση.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(_BulkGuardChoice.cancel),
          child: const Text('Άκυρο'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(_BulkGuardChoice.discardCall),
          child: const Text('Διακοπή κλήσης'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(_BulkGuardChoice.goToCall),
          child: const Text('Μετάβαση στην κλήση'),
        ),
      ],
    ),
  );

  switch (choice) {
    case _BulkGuardChoice.discardCall:
      clearCallFormCompletely(ref);
      return true;
    case _BulkGuardChoice.goToCall:
      if (context.mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      }
      ref
          .read(mainNavRequestProvider.notifier)
          .request(const MainNavRequest(destination: MainNavDestination.calls));
      return false;
    case _BulkGuardChoice.cancel:
    case null:
      return false;
  }
}
