import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/main_nav_request_provider.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/phone_list_parser.dart';
import '../../../../core/widgets/main_nav_destination.dart';
import '../../../calls/layout/call_form_clear.dart';
import '../../../calls/provider/smart_entity_selector_provider.dart';
import '../../../calls/models/user_model.dart';

enum _BulkGuardChoice { cancel, discardCall, goToCall }

/// True όταν η ανοιχτή φόρμα κλήσης αναφέρεται σε κάποιον από τους
/// [selectedUsers] (ως καλών, μέσω τηλεφώνου του ή εξοπλισμού του).
bool openCallInvolvesSelectedUsers(
  WidgetRef ref,
  List<UserModel> selectedUsers,
) {
  final smart = ref.read(callSmartEntityProvider);
  if (!smart.hasAnyContent) return false;

  final selectedIds = {
    for (final u in selectedUsers)
      if (u.id != null) u.id!,
  };
  if (selectedIds.isEmpty) return false;

  final callerId = smart.selectedCaller?.id;
  if (callerId != null && selectedIds.contains(callerId)) return true;

  final phone = smart.phoneText?.trim() ?? '';
  if (phone.isNotEmpty) {
    for (final u in selectedUsers) {
      if (PhoneListParser.containsPhone(u.phoneJoined, phone)) return true;
    }
  }

  final equipmentId = smart.selectedEquipment?.id;
  if (equipmentId != null) {
    final owners = LookupService.instance.findUsersForEquipment(equipmentId);
    if (owners.any((o) => o.id != null && selectedIds.contains(o.id))) {
      return true;
    }
  }
  return false;
}

/// Φρουρός πριν από μαζική ενέργεια υπαλλήλων: όταν η ανοιχτή κλήση αφορά
/// επιλεγμένο υπάλληλο, ο χρήστης αποφασίζει πρώτα για την κλήση.
///
/// Επιστρέφει true όταν η ενέργεια επιτρέπεται να προχωρήσει.
Future<bool> ensureBulkUserActionAllowed(
  BuildContext context,
  WidgetRef ref,
  List<UserModel> selectedUsers,
) async {
  if (!openCallInvolvesSelectedUsers(ref, selectedUsers)) return true;

  final choice = await showDialog<_BulkGuardChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Ανοιχτή κλήση'),
      content: const Text(
        'Η ανοιχτή κλήση αφορά επιλεγμένο υπάλληλο. '
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
