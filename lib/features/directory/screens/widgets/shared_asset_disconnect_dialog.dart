// Η ενορχήστρωση της ροής αποδέσμευσης: ρωτά για κάθε στοιχείο με τη σειρά,
// σέβεται τις καθολικές αποφάσεις και συγκεντρώνει το αποτέλεσμα.
//
// Παραμένει και σημείο εισόδου της ροής: οι καλούντες εισάγουν μόνο αυτό το
// αρχείο και βλέπουν μοντέλα, συνεδρία, κείμενα και τον επιλογέα τμήματος.
// Τα widgets των διαλόγων ζουν σε δικά τους αρχεία:
//   asset_disconnect_item_dialog.dart    — απόφαση ανά στοιχείο
//   asset_disconnect_quick_actions.dart  — καθολικές επιλογές
//   asset_disconnect_bulk_preview.dart   — προεπισκόπηση «για όλα»
//   asset_disconnect_action_section.dart — οι λίστες ενεργειών
//   asset_transfer_target_dialog.dart    — επιλογή τμήματος προορισμού

import 'package:flutter/material.dart';

import '../../models/department_model.dart';
import '../../services/asset_disconnect_link_probe.dart';
import '../../services/asset_disconnect_models.dart';
import '../../services/asset_disconnect_session.dart';
import 'asset_disconnect_item_dialog.dart';

export '../../services/asset_disconnect_link_probe.dart'
    show AssetHistoryLinksLookup, AssetReferenceDescriptionsLookup;
export '../../services/asset_disconnect_models.dart';
export '../../services/asset_disconnect_session.dart';
export '../../services/asset_disconnect_texts.dart';
export 'asset_transfer_target_dialog.dart' show showAssetTransferTargetPicker;

/// Ροή αποδέσμευσης κοινόχρηστων τηλεφώνων/εξοπλισμού από τμήμα
/// ή προσωπικών τηλεφώνων χρήστη (αφαίρεση από φόρμα χρήστη).
///
/// Αν ο καλών δώσει [session], ο μετρητής βημάτων και οι γρήγορες επιλογές
/// καλύπτουν ΟΛΗ την ενέργειά του (π.χ. «Βήμα 6 από 24» για δέκα υπαλλήλους).
/// Χωρίς αυτήν, η ροή κρατά δικό της λογαριασμό μόνο για τα δικά της στοιχεία.
Future<SharedAssetDisconnectBatchResult?> showSharedAssetDisconnectFlow({
  required BuildContext context,
  int? sourceDepartmentId,
  String? sourceDepartmentName,
  List<String> phones = const [],
  List<String> equipmentCodes = const [],
  required List<DepartmentModel> availableDepartments,
  List<String> blockedDepartmentNames = const [],
  SharedAssetDisconnectMode mode = SharedAssetDisconnectMode.sharedAsset,
  String? personalPhoneUserDisplayName,
  bool allowKeepInDepartment = true,
  AssetDisconnectSession? session,
  AssetReferenceDescriptionsLookup? referenceLookup,
  AssetHistoryLinksLookup? historyLookup,
}) async {
  if (phones.isEmpty && equipmentCodes.isEmpty) {
    return const SharedAssetDisconnectBatchResult();
  }

  final items = <AssetDisconnectItem>[
    for (final phone in phones)
      if (phone.trim().isNotEmpty) AssetDisconnectItem.phone(phone),
    for (final code in equipmentCodes)
      if (code.trim().isNotEmpty) AssetDisconnectItem.equipment(code),
  ];
  final activeSession = session ?? AssetDisconnectSession(items: items);

  final keptPhones = <String>[];
  final keptEquipment = <String>[];
  final phoneTransfers = <String, SharedAssetTransferTarget>{};
  final equipmentTransfers = <String, SharedAssetTransferTarget>{};
  final phonesToDelete = <String>[];
  final equipmentToDelete = <String>[];
  final newDepartmentNames = <String>{};

  final canKeepInDepartment =
      allowKeepInDepartment &&
      sourceDepartmentId != null &&
      (sourceDepartmentName?.trim().isNotEmpty ?? false);

  for (final item in items) {
    if (!context.mounted) return null;

    final itemMode = item.isPhone
        ? mode
        : (mode == SharedAssetDisconnectMode.personalEquipment
              ? SharedAssetDisconnectMode.personalEquipment
              : SharedAssetDisconnectMode.sharedAsset);

    SharedAssetDisconnectItemResult? result;
    final standing = activeSession.standingDecisionFor(item.kind);
    if (standing != null &&
        _standingIsApplicable(
          standing,
          canKeepInDepartment: canKeepInDepartment,
        )) {
      result = standing.toItemResult();
    } else {
      final resolution = await resolveAssetDisconnectItem(
        context: context,
        item: item,
        sourceDepartmentId: sourceDepartmentId,
        sourceDepartmentName: sourceDepartmentName,
        availableDepartments: availableDepartments,
        blockedDepartmentNames: blockedDepartmentNames,
        mode: itemMode,
        personalPhoneUserDisplayName: personalPhoneUserDisplayName,
        canKeepInDepartment: canKeepInDepartment,
        session: activeSession,
        referenceLookup: referenceLookup,
        historyLookup: historyLookup,
      );
      if (resolution == null) return null;
      final newStanding = resolution.standing;
      if (newStanding != null) {
        activeSession.applyStandingDecision(newStanding);
        result = newStanding.toItemResult();
      } else {
        result = resolution.result;
      }
    }
    if (result == null) return null;

    activeSession.markResolved(item);

    switch (result.choice) {
      case SharedAssetDisconnectChoice.keepInDepartment:
        if (item.isPhone) {
          keptPhones.add(item.value);
        } else {
          keptEquipment.add(item.value);
        }
      case SharedAssetDisconnectChoice.transfer:
        final target = result.transferTarget;
        if (target == null) return null;
        if (item.isPhone) {
          phoneTransfers[item.value] = target;
        } else {
          equipmentTransfers[item.value] = target;
        }
        final newName = target.newDepartmentName?.trim();
        if (newName != null && newName.isNotEmpty) {
          newDepartmentNames.add(newName);
        }
      case SharedAssetDisconnectChoice.delete:
        if (item.isPhone) {
          phonesToDelete.add(item.value);
        } else {
          equipmentToDelete.add(item.value);
        }
    }
  }

  return SharedAssetDisconnectBatchResult(
    phonesToKeep: keptPhones,
    equipmentToKeep: keptEquipment,
    phoneTransfers: phoneTransfers,
    equipmentTransfers: equipmentTransfers,
    phonesToDelete: phonesToDelete,
    equipmentToDelete: equipmentToDelete,
    newDepartmentNamesToCreate: newDepartmentNames,
  );
}

/// Μια καθολική απόφαση δεν εφαρμόζεται σιωπηλά όπου δεν έχει νόημα: η
/// «παραμονή» χρειάζεται τμήμα-πηγή, η «μεταφορά» χρειάζεται στόχο.
bool _standingIsApplicable(
  AssetDisconnectStandingDecision decision, {
  required bool canKeepInDepartment,
}) {
  switch (decision.choice) {
    case SharedAssetDisconnectChoice.keepInDepartment:
      return canKeepInDepartment;
    case SharedAssetDisconnectChoice.transfer:
      return decision.transferTarget != null;
    case SharedAssetDisconnectChoice.delete:
      return true;
  }
}
