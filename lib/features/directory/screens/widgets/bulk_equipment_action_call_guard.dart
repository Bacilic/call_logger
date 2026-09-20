import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'open_call_entity_guard.dart';

import '../../../calls/provider/smart_entity_selector_provider.dart';
import '../../models/equipment_column.dart';

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

/// Φρουρός πριν από ενέργεια του Καταλόγου: όταν η ανοιχτή κλήση αφορά ό,τι
/// πάει να αλλάξει ή να διαγραφεί, ο χρήστης αποφασίζει πρώτα για την κλήση.
///
/// Επιστρέφει true όταν η ενέργεια επιτρέπεται να προχωρήσει.
Future<bool> ensureBulkEquipmentActionAllowed(
  BuildContext context,
  WidgetRef ref,
  List<EquipmentRow> selectedRows,
) {
  return ensureOpenCallAllowsCatalogAction(
    context,
    ref,
    openCallInvolvesTarget: openCallInvolvesSelectedEquipment(
      ref,
      selectedRows,
    ),
    targetPhrase: 'επιλεγμένο εξοπλισμό',
  );
}
