// Οι καθολικές επιλογές («για όλα τα υπόλοιπα») και η επιβεβαίωσή τους.
//
// Το widget προσφέρει τις επιλογές· η [resolveAssetDisconnectQuickAction]
// τρέχει ό,τι χρειάζεται πριν γίνει απόφαση — επιλογή τμήματος στη μεταφορά,
// άντληση ιστορικού στη διαγραφή — και δείχνει την προεπισκόπηση.

import 'package:flutter/material.dart';

import '../../models/department_model.dart';
import '../../services/asset_disconnect_link_probe.dart';
import '../../services/asset_disconnect_models.dart';
import '../../services/asset_disconnect_session.dart';
import '../../services/asset_disconnect_texts.dart';
import 'asset_disconnect_action_section.dart';
import 'asset_disconnect_bulk_preview.dart';
import 'asset_transfer_target_dialog.dart';

/// Πρόθεση γρήγορης επιλογής — η επιβεβαίωσή της γίνεται έξω από τον διάλογο.
enum AssetDisconnectQuickActionIntent {
  deleteEverything,
  deletePhones,
  deleteEquipment,
  keepEverything,
  transferEverything,
}

/// Οι καθολικές επιλογές για όσα στοιχεία απομένουν.
///
/// Κρύβεται όταν απομένει λιγότερο από δύο στοιχεία: «για όλα» με ένα στοιχείο
/// είναι το ίδιο με την ατομική επιλογή.
class AssetDisconnectQuickActionsSection extends StatelessWidget {
  const AssetDisconnectQuickActionsSection({
    super.key,
    required this.session,
    required this.canKeepInDepartment,
    required this.onIntent,
  });

  final AssetDisconnectSession session;
  final bool canKeepInDepartment;
  final ValueChanged<AssetDisconnectQuickActionIntent> onIntent;

  @override
  Widget build(BuildContext context) {
    final remaining = session.remainingSteps;
    if (remaining < 2) return const SizedBox.shrink();

    final phoneCount = session.remainingPhoneCount;
    final equipmentCount = session.remainingEquipmentCount;
    final mixed = phoneCount > 0 && equipmentCount > 0;

    // «Παραμονή για όλα» μόνο όταν τα υπόλοιπα είναι όντως στο ίδιο τμήμα:
    // ένα τηλέφωνο των Αδειών δεν «παραμένει» στην Ψυχιατρική.
    final commonDept = session.commonRemainingDepartmentName;
    final canKeepEverything = canKeepInDepartment && commonDept != null;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AssetDisconnectActionSection(
        header: assetDisconnectQuickActionsHeader(
          remainingSteps: remaining,
          isAtFirstStep: session.isAtFirstStep,
        ),
        tinted: true,
        footnote: canKeepEverything
            ? null
            : _mixedDepartmentsFootnote(session, canKeepInDepartment),
        actions: [
          AssetDisconnectActionEntry(
            icon: Icons.delete_sweep_outlined,
            label: 'Διαγραφή όλων ($remaining)',
            danger: true,
            tooltip: deleteEverythingTooltip(
              count: remaining,
              scope: 'τηλέφωνα και εξοπλισμός μαζί',
            ),
            onTap: () =>
                onIntent(AssetDisconnectQuickActionIntent.deleteEverything),
          ),
          if (mixed)
            AssetDisconnectActionEntry(
              icon: Icons.phone_disabled_outlined,
              label: 'Διαγραφή όλων των τηλεφώνων ($phoneCount)',
              danger: true,
              tooltip: deleteEverythingTooltip(
                count: phoneCount,
                scope: 'μόνο τα τηλέφωνα· ο εξοπλισμός δεν θίγεται',
              ),
              onTap: () =>
                  onIntent(AssetDisconnectQuickActionIntent.deletePhones),
            ),
          if (mixed)
            AssetDisconnectActionEntry(
              icon: Icons.devices_other_outlined,
              label: 'Διαγραφή όλου του εξοπλισμού ($equipmentCount)',
              danger: true,
              tooltip: deleteEverythingTooltip(
                count: equipmentCount,
                scope: 'μόνο ο εξοπλισμός· τα τηλέφωνα δεν θίγονται',
              ),
              onTap: () =>
                  onIntent(AssetDisconnectQuickActionIntent.deleteEquipment),
            ),
          if (canKeepEverything)
            AssetDisconnectActionEntry(
              icon: Icons.check_circle_outline,
              label: 'Παραμονή στο $commonDept — όλα ($remaining)',
              tooltip: keepEverythingTooltip(
                count: remaining,
                departmentName: commonDept,
              ),
              onTap: () =>
                  onIntent(AssetDisconnectQuickActionIntent.keepEverything),
            ),
          AssetDisconnectActionEntry(
            icon: Icons.drive_file_move_outlined,
            label: 'Μεταφορά όλων σε ένα τμήμα ($remaining)',
            tooltip: transferEverythingTooltip(count: remaining),
            onTap: () =>
                onIntent(AssetDisconnectQuickActionIntent.transferEverything),
          ),
        ],
      ),
    );
  }

  String? _mixedDepartmentsFootnote(
    AssetDisconnectSession session,
    bool canKeepInDepartment,
  ) {
    if (!canKeepInDepartment) return null;
    final deptCount = session.remainingDepartmentCount;
    if (deptCount < 2) return null;
    return 'Τα στοιχεία ανήκουν σε $deptCount τμήματα, οπότε δεν μπορούν να '
        '«παραμείνουν» κάπου όλα μαζί. Στη μεταφορά μπορείτε να διαλέξετε '
        'και ένα από αυτά τα τμήματα.';
  }
}

/// Από την πρόθεση στην καθολική απόφαση: συμπληρώνει ό,τι λείπει και ζητά
/// επιβεβαίωση. Επιστρέφει null όταν ο χρήστης υπαναχωρήσει σε οποιοδήποτε βήμα.
Future<AssetDisconnectStandingDecision?> resolveAssetDisconnectQuickAction({
  required BuildContext context,
  required AssetDisconnectQuickActionIntent intent,
  required AssetDisconnectSession session,
  required List<DepartmentModel> availableDepartments,
  List<String> blockedDepartmentNames = const [],
  AssetHistoryLinksLookup? historyLookup,
}) async {
  final remaining = session.remainingItems;

  final List<AssetDisconnectItem> affected;
  final SharedAssetDisconnectChoice choice;
  switch (intent) {
    case AssetDisconnectQuickActionIntent.deleteEverything:
      affected = remaining;
      choice = SharedAssetDisconnectChoice.delete;
    case AssetDisconnectQuickActionIntent.deletePhones:
      affected = remaining.where((i) => i.isPhone).toList();
      choice = SharedAssetDisconnectChoice.delete;
    case AssetDisconnectQuickActionIntent.deleteEquipment:
      affected = remaining.where((i) => !i.isPhone).toList();
      choice = SharedAssetDisconnectChoice.delete;
    case AssetDisconnectQuickActionIntent.keepEverything:
      affected = remaining;
      choice = SharedAssetDisconnectChoice.keepInDepartment;
    case AssetDisconnectQuickActionIntent.transferEverything:
      affected = remaining;
      choice = SharedAssetDisconnectChoice.transfer;
  }
  if (affected.isEmpty) return null;

  SharedAssetTransferTarget? target;
  if (choice == SharedAssetDisconnectChoice.transfer) {
    target = await showAssetTransferTargetPicker(
      context: context,
      headerLabel: 'Μεταφορά ${affected.length} στοιχείων σε ένα τμήμα',
      availableDepartments: availableDepartments,
      // Στη μαζική μεταφορά ΔΕΝ αποκλείεται κανένα τμήμα-πηγή: όταν τα στοιχεία
      // ανήκουν σε πολλά τμήματα, «μεταφορά εκεί που ήδη ανήκει» είναι ο
      // μόνος τρόπος να μείνει κάτι στη θέση του. Τα τμήματα που ΔΙΑΓΡΑΦΟΝΤΑΙ
      // όμως μένουν απαγορευμένα — εκεί τα στοιχεία θα χάνονταν.
      sourceDepartmentId: null,
      blockedDepartmentNames: blockedDepartmentNames,
    );
    if (!context.mounted || target == null) return null;
  }

  // Το ιστορικό κάθε στοιχείου ξεχωριστά: ο κάτοχος δεν μετράει ως «σύνδεση»,
  // γιατί τον έχουν σχεδόν όλα και η προειδοποίηση θα ίσχυε πάντα.
  final histories = choice == SharedAssetDisconnectChoice.delete
      ? await assetHistoryLinksFor(affected, lookup: historyLookup)
      : const <AssetHistoryLinks>[];
  if (!context.mounted) return null;

  final headline = assetDisconnectBulkPreviewHeadline(
    choice: choice,
    items: affected,
    transferDepartmentName: target == null
        ? null
        : _transferTargetName(target, availableDepartments),
  );

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(
        assetDisconnectBulkTitle(choice: choice, itemCount: affected.length),
      ),
      content: AssetDisconnectBulkPreview(
        headline: headline,
        items: affected,
        histories: histories,
        showUndoReminder: choice == SharedAssetDisconnectChoice.delete,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Ναι, εφαρμογή σε όλα'),
        ),
      ],
    ),
  );
  if (confirmed != true) return null;

  switch (intent) {
    case AssetDisconnectQuickActionIntent.deleteEverything:
      return const AssetDisconnectStandingDecision.deleteEverything();
    case AssetDisconnectQuickActionIntent.deletePhones:
      return const AssetDisconnectStandingDecision.deletePhones();
    case AssetDisconnectQuickActionIntent.deleteEquipment:
      return const AssetDisconnectStandingDecision.deleteEquipment();
    case AssetDisconnectQuickActionIntent.keepEverything:
      return const AssetDisconnectStandingDecision.keepEverything();
    case AssetDisconnectQuickActionIntent.transferEverything:
      return AssetDisconnectStandingDecision.transferEverything(target);
  }
}

/// Ονομασία τμήματος-στόχου για το μήνυμα προεπισκόπησης.
String? _transferTargetName(
  SharedAssetTransferTarget target,
  List<DepartmentModel> availableDepartments,
) {
  final newName = target.newDepartmentName?.trim();
  if (newName != null && newName.isNotEmpty) return newName;
  final id = target.departmentId;
  if (id == null) return null;
  for (final dept in availableDepartments) {
    if (dept.id == id) return dept.name.trim();
  }
  return null;
}
