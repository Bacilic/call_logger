import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'open_call_entity_guard.dart';

import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/phone_list_parser.dart';
import '../../../calls/provider/smart_entity_selector_provider.dart';
import '../../../calls/models/user_model.dart';

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

/// Φρουρός πριν από ενέργεια του Καταλόγου: όταν η ανοιχτή κλήση αφορά ό,τι
/// πάει να αλλάξει ή να διαγραφεί, ο χρήστης αποφασίζει πρώτα για την κλήση.
///
/// Επιστρέφει true όταν η ενέργεια επιτρέπεται να προχωρήσει.
Future<bool> ensureBulkUserActionAllowed(
  BuildContext context,
  WidgetRef ref,
  List<UserModel> selectedUsers,
) {
  return ensureOpenCallAllowsCatalogAction(
    context,
    ref,
    openCallInvolvesTarget: openCallInvolvesSelectedUsers(ref, selectedUsers),
    targetPhrase: 'επιλεγμένο υπάλληλο',
  );
}
