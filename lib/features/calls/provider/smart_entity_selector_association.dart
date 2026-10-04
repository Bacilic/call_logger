import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/directory/department_change_assets.dart';
import '../../../core/directory/equipment_department_policy.dart';
import '../../../core/directory/phone_department_policy.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/utils/name_parser.dart';
import '../../../core/utils/phone_list_parser.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../../directory/models/catalog_validation_rules.dart';
import '../../directory/models/department_kind.dart';
import '../../directory/services/phone_transfer_split.dart';
import '../../directory/providers/directory_cache_refresh.dart';
import '../../directory/screens/widgets/asset_fate_on_department_change.dart';
import '../../directory/screens/widgets/user_phone_department_conflict_dialog.dart';
import '../../directory/services/bulk_user_actions.dart';
import '../../tasks/models/task.dart';
import '../../directory/providers/catalog_validation_provider.dart';
import '../../tasks/providers/task_service_provider.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';
import '../screens/widgets/equipment_owner_move_dialog.dart';
import 'call_mutation_refresh.dart';
import 'lookup_provider.dart';
import 'orphan_quick_add_plan.dart';
import 'quick_add_undo_record.dart';
import 'smart_entity_selector_provider.dart';

/// Συσχετίσεις, quick-add orphan και γρήγορες εκκρεμότητες.
///
/// Συνεργάτης του [SmartEntitySelectorNotifier] (Σύνθεση): δουλεύει πάνω στην
/// κατάσταση του host μέσω των δημόσιων γεφυρών του — δεν κρατά δική του.
class SmartEntitySelectorAssociation {
  SmartEntitySelectorAssociation(this.host);

  final SmartEntitySelectorNotifier host;

  SmartEntitySelectorState get state => host.selectorState;
  set state(SmartEntitySelectorState value) => host.selectorState = value;

  Ref get ref => host.selectorRef;

  /// Ρωτά για τη σύγκρουση τηλεφώνου, αν υπάρχει — **χωρίς να γράψει τίποτα**.
  /// Η απάντηση εφαρμόζεται με [_applyPhoneResolutions], αφού έχουν γίνει όλες
  /// οι ερωτήσεις του «+».
  ///
  /// Δύο διαφορετικές απαντήσεις «χωρίς τηλέφωνο», που δεν επιτρέπεται να
  /// μπερδευτούν:
  /// - `phone == null` — ο χρήστης διάλεξε ρητά να μείνει το τηλέφωνο εκεί που
  ///   είναι· η υπόλοιπη καταχώρηση συνεχίζει.
  /// - `cancelled` — «Ακύρωση» ή καμία οθόνη για να ρωτηθεί· ο καλών δεν
  ///   γράφει **τίποτα**.
  ///
  /// [targetIsNewDepartment]: το τμήμα του υπαλλήλου θα δημιουργηθεί μετά την
  /// ερώτηση — η μεταφορά του τηλεφώνου εκεί προσφέρεται κανονικά.
  Future<
    ({bool cancelled, String? phone, UserPhoneConflictBatchResult? resolutions})
  >
  _askPhoneAssociation({
    required BuildContext? context,
    required String phone,
    required int? targetDepartmentId,
    required int? editingUserId,
    required String userDisplayName,
    required String targetDepartmentName,
    bool targetIsNewDepartment = false,
  }) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) {
      return (cancelled: false, phone: null, resolutions: null);
    }

    final conflicts = PhoneDepartmentPolicy.findConflictsForUserAssignment(
      phones: [trimmed],
      targetDepartmentId: targetDepartmentId,
      editingUserId: editingUserId,
    );
    if (conflicts.isEmpty) {
      return (cancelled: false, phone: trimmed, resolutions: null);
    }

    if (context == null || !context.mounted) {
      return (cancelled: true, phone: null, resolutions: null);
    }

    final result = await showUserPhoneDepartmentConflictDialog(
      context,
      conflicts: conflicts,
      userDisplayName: userDisplayName,
      targetDepartmentName: targetDepartmentName,
      targetDepartmentId: targetDepartmentId,
      targetIsNewDepartment: targetIsNewDepartment,
    );
    if (result == null) {
      return (cancelled: true, phone: null, resolutions: null);
    }

    // «Μένει στο τμήμα του» σημαίνει ότι δεν συνδέεται με τον καλούντα — αλλιώς
    // η επιλογή θα ζητιόταν και θα αγνοούνταν.
    if (result.detaches(trimmed)) {
      return (cancelled: false, phone: null, resolutions: null);
    }
    return (cancelled: false, phone: trimmed, resolutions: result);
  }

  /// Εξοπλισμός που ανήκει σε υπάλληλο **άλλου** τμήματος: ρητή ερώτηση πριν
  /// γραφτεί οτιδήποτε — για υπάρχοντα **και** για νέο καλούντα.
  ///
  /// `cancelled` = δεν απαντήθηκε «Ναι, μεταφορά» (ή δεν υπάρχει οθόνη για να
  /// ρωτηθεί): ο καλών δεν γράφει **τίποτα**. Με «Ναι» επιστρέφονται οι
  /// κάτοχοι που θα αφαιρεθούν με [_releaseMovedEquipment].
  ///
  /// [newOwnerId] είναι `null` για νέο καλούντα· [targetDepartmentId] `null`
  /// για νέο ή κενό τμήμα (τότε κάθε κάτοχος με τμήμα είναι ξένος).
  Future<_EquipmentMove> _askEquipmentMove({
    required BuildContext? context,
    required LookupService? lookup,
    required String equipmentCode,
    required int? newOwnerId,
    required int? targetDepartmentId,
    required String newOwnerName,
  }) async {
    const nothingToMove = (
      cancelled: false,
      equipmentId: null,
      ownersToRelease: <UserModel>[],
    );
    final code = equipmentCode.trim();
    if (lookup == null || code.isEmpty) return nothingToMove;
    final existing = lookup.findEquipmentsByCode(code);
    final equipmentId = existing.isEmpty ? null : existing.first.id;
    if (equipmentId == null) return nothingToMove;
    final foreignOwners = equipmentOwnersInOtherDepartments(
      owners: lookup.findUsersForEquipment(equipmentId),
      newOwnerId: newOwnerId,
      targetDepartmentId: targetDepartmentId,
    );
    if (foreignOwners.isEmpty) return nothingToMove;

    final approved = (context == null || !context.mounted)
        ? null
        : await showEquipmentOwnerMoveDialog(
            context: context,
            equipmentCode: code,
            currentOwnerLabels: [
              for (final owner in foreignOwners) _ownerLabel(owner, lookup),
            ],
            newOwnerName: newOwnerName,
          );
    if (approved != true) {
      return (
        cancelled: true,
        equipmentId: null,
        ownersToRelease: const <UserModel>[],
      );
    }
    return (
      cancelled: false,
      equipmentId: equipmentId,
      ownersToRelease: foreignOwners,
    );
  }

  /// Μεταφορά, όχι μοιρασιά: ο εξοπλισμός φεύγει από τους κατόχους του άλλου
  /// τμήματος, αφού ο χρήστης απάντησε ρητά «Ναι». Καλείται **μετά** τη
  /// σύνδεση με τον νέο κάτοχο, ώστε ο εξοπλισμός να μη μείνει ποτέ ορφανός.
  Future<void> _releaseMovedEquipment(
    EquipmentRepository equipmentRepo,
    _EquipmentMove move,
  ) async {
    final equipmentId = move.equipmentId;
    if (equipmentId == null) return;
    for (final owner in move.ownersToRelease) {
      final ownerId = owner.id;
      if (ownerId == null) continue;
      await equipmentRepo.unlinkUserFromEquipment(ownerId, equipmentId);
    }
  }

  /// Εφαρμόζει την απάντηση του [_askPhoneAssociation] — μόνο αφού έχουν
  /// απαντηθεί όλες οι ερωτήσεις και υπάρχει πια το τμήμα-στόχος.
  Future<void> _applyPhoneResolutions({
    required PhoneRepository phonesRepo,
    required UserPhoneConflictBatchResult? resolutions,
    required int? targetDepartmentId,
  }) async {
    if (resolutions == null) return;
    await PhoneDepartmentPolicy.applyUserPhoneConflictResolutions(
      phones: phonesRepo,
      resolutions: resolutions,
      targetDepartmentId: targetDepartmentId,
    );
    ref.invalidate(lookupServiceProvider);
    await ref.read(lookupServiceProvider.future);
  }

  /// Ρωτά τι απογίνονται τηλέφωνα και εξοπλισμός όταν ο καλών αλλάζει τμήμα.
  ///
  /// Επιστρέφει τι μένει πίσω, και ποια κοινά μηχανήματα ακολουθούν
  /// παίρνοντάς τα από τους υπόλοιπους κατόχους· `null` σημαίνει «ο χρήστης
  /// ακύρωσε» και τότε το τμήμα δεν αλλάζει καθόλου.
  ///
  /// Χωρίς παλιό τμήμα δεν υπάρχει μεταφορά — η πρώτη ανάθεση περνά αθόρυβα,
  /// όπως και πριν.
  Future<_AssetsOnDepartmentChange?> _confirmAssetsOnDepartmentChange({
    required BuildContext? context,
    required UserModel caller,

    /// Πού πάει ο υπάλληλος — το Είδος του προορισμού κρίνει αν ο εξοπλισμός
    /// επιτρέπεται να τον ακολουθήσει.
    required int? targetDepartmentId,
  }) async {
    final userId = caller.id;
    final oldDepartmentId = caller.departmentId;
    const nothingStays = (
      phones: <String>{},
      phonesLeftWithCoOwners: <String>{},
      phonesTakenFromCoOwners: <String>{},
      equipment: <EquipmentModel>[],
      takenFromCoOwners: <EquipmentModel>[],
    );
    if (userId == null || oldDepartmentId == null) return nothingStays;

    final lookup = ref.read(lookupServiceProvider).value?.service;
    final carriedPhones = caller.phones
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final carriedEquipment =
        lookup?.findEquipmentsForUser(userId) ?? const <EquipmentModel>[];
    if (carriedPhones.isEmpty && carriedEquipment.isEmpty) return nothingStays;
    final userName = bulkUserDisplayName(caller);
    // Ο κανόνας του εξοπλισμού τρέχει πριν από κάθε ερώτηση: ξεχωρίζει τα
    // κοινά μηχανήματα, για τα οποία ρωτιέται η τύχη του ίδιου του μηχανήματος.
    final equipmentPlan = planEquipmentStayBehind(
      equipment: carriedEquipment,
      userName: userName,
      oldDepartmentId: oldDepartmentId,
      editingUserId: userId,
      lookup: LookupService.instance,
    );
    // Χωρίς οθόνη δεν υπάρχει ποιον να ρωτήσουμε. Συνειδητή επιλογή: η αλλαγή
    // τμήματος προχωρά με τις προεπιλογές αντί να χαθεί η πρόθεση του χρήστη
    // επειδή έκλεισε η κλήση στο ενδιάμεσο — όλα ακολουθούν, εκτός από τα
    // κοινά τηλέφωνα και μηχανήματα, που συνήθως μένουν στο τμήμα τους.
    if (context == null || !context.mounted) {
      final sharedPhones = planPhoneStayBehind(
        phones: carriedPhones,
        userName: userName,
        oldDepartmentId: oldDepartmentId,
        editingUserId: userId,
        lookup: LookupService.instance,
      ).shared;
      return (
        phones: const <String>{},
        phonesLeftWithCoOwners: {for (final s in sharedPhones) s.phone},
        phonesTakenFromCoOwners: const <String>{},
        equipment: [for (final s in equipmentPlan.shared) s.equipment],
        takenFromCoOwners: const <EquipmentModel>[],
      );
    }

    // Άγνωστο ή νεοσύστατο τμήμα διαβάζεται ως νοσοκομείο — η ίδια παραδοχή
    // με τη μαζική μεταφορά και τη φόρμα υπαλλήλου.
    final targetKind =
        (targetDepartmentId == null
            ? null
            : lookup?.departmentKindById(targetDepartmentId)) ??
        DepartmentKind.hospital;
    final sourceDepartmentName = lookup?.departments
        .where((d) => d.id == oldDepartmentId)
        .firstOrNull
        ?.name
        .trim();

    final targetDepartmentName =
        (targetDepartmentId == null
            ? null
            : lookup?.departmentIdToName[targetDepartmentId]) ??
        state.departmentText.trim();

    PhoneDepartmentChangeAnswer phoneAnswer = (
      staying: const <String>{},
      leftWithCoOwners: const <String>{},
      takenFromCoOwners: const <String>{},
    );
    if (carriedPhones.isNotEmpty) {
      // Τα εσωτερικά του κέντρου μας δεν ακολουθούν έξω από το νοσοκομείο.
      final split = splitPhonesForDepartmentChange(
        phones: carriedPhones,
        targetKind: targetKind,
        rules:
            ref.read(catalogValidationRulesProvider).value ??
            const CatalogValidationRules(),
      );
      // Ο κανόνας τρέχει ΠΡΙΝ την ερώτηση, ώστε ο λόγος που ένας αριθμός δεν
      // μπορεί να μείνει πίσω να ειπωθεί όσο ο χρήστης ακόμη αποφασίζει.
      final plan = planPhoneStayBehind(
        phones: split.negotiable,
        userName: userName,
        oldDepartmentId: oldDepartmentId,
        editingUserId: userId,
        lookup: LookupService.instance,
      );
      // Ίδιες ερωτήσεις, ίδια σειρά με την καρτέλα υπαλλήλου.
      final answer = await askPhonesOnDepartmentChange(
        context,
        split: split,
        plan: plan,
        targetKind: targetKind,
        userDisplayName: userName,
        sourceDepartmentName: sourceDepartmentName,
        targetDepartmentName: targetDepartmentName,
      );
      if (answer == null) return null;
      phoneAnswer = answer;
    }

    // Ανάμεσα στις ερωτήσεις μεσολάβησε διάλογος: η οθόνη μπορεί να έχει
    // φύγει, οπότε ο φρουρός ξαναμπαίνει πριν από τις επόμενες.
    if (carriedEquipment.isEmpty || !context.mounted) {
      return (
        phones: phoneAnswer.staying,
        phonesLeftWithCoOwners: phoneAnswer.leftWithCoOwners,
        phonesTakenFromCoOwners: phoneAnswer.takenFromCoOwners,
        equipment: const <EquipmentModel>[],
        takenFromCoOwners: const <EquipmentModel>[],
      );
    }
    // Ίδιες ερωτήσεις, ίδια σειρά με την καρτέλα υπαλλήλου.
    final equipmentAnswer = await askEquipmentOnDepartmentChange(
      context,
      plan: equipmentPlan,
      targetKind: targetKind,
      userDisplayName: userName,
      sourceDepartmentName: sourceDepartmentName,
      targetDepartmentName: targetDepartmentName,
    );
    if (equipmentAnswer == null) return null;
    return (
      phones: phoneAnswer.staying,
      phonesLeftWithCoOwners: phoneAnswer.leftWithCoOwners,
      phonesTakenFromCoOwners: phoneAnswer.takenFromCoOwners,
      equipment: equipmentAnswer.staying,
      takenFromCoOwners: equipmentAnswer.takenFromCoOwners,
    );
  }

  /// Μηδενίζει τον κύκλο γρήγορης εκκρεμότητας (νέα φόρμα/καθαρισμός/submit).
  void resetQuickTaskCycle() {
    host.associationQuickTaskId = null;
    host.lastQuickAddUndo = QuickAddUndoRecord.empty;
    host.callerAwaitingPhoneAssociation = false;
    host.clearPendingAuditOrigins();
  }

  /// Καταχωρεί τηλέφωνο και/ή εξοπλισμό ως κοινόχρηστα ενός τμήματος, όταν η
  /// φόρμα δεν έχει καλούντα.
  ///
  /// Τέσσερα βήματα, με αυστηρή σειρά και χωρισμένες ευθύνες: **τι θα γραφτεί**
  /// (κρίση), **χρειάζεται έγκριση;** (καθαρός υπολογισμός), **γράψε**, και
  /// **φινάλε** (ανανέωση, οθόνη, μήνυμα, εκκρεμότητα). Το βήμα της εγγραφής
  /// δεν κρίνει τίποτα — διαβάζει μόνο το [OrphanQuickAddPlan].
  /// Αναιρεί ό,τι γέννησε η τελευταία γρήγορη καταχώρηση.
  ///
  /// Επιστρέφει το μήνυμα προς τον χρήστη· `null` όταν δεν υπάρχει τίποτα να
  /// αναιρεθεί (η προσφορά έχει ήδη σβήσει ή δεν δημιουργήθηκε ποτέ τίποτα).
  ///
  /// **Φεύγει και η εκκρεμότητα του κύκλου:** θα έμενε να δείχνει σε καρτέλες
  /// που μόλις σβήστηκαν, δηλαδή υπενθύμιση για δουλειά που δεν υπάρχει.
  ///
  /// Η φόρμα γυρίζει στο «πριν»: τα κείμενα που πληκτρολογήσατε μένουν, αλλά η
  /// ταυτοποίηση φεύγει — ακριβώς η κατάσταση πριν πατήσετε «Προσθήκη».
  Future<String?> undoLastQuickAdd() async {
    final record = host.lastQuickAddUndo;
    if (record.isEmpty) return null;
    host.lastQuickAddUndo = QuickAddUndoRecord.empty;

    final db = await DatabaseHelper.instance.database;
    try {
      await applyQuickAddUndo(
        record,
        executor: db,
        users: UserRepository(db),
        phones: PhoneRepository(db),
        equipment: EquipmentRepository(db),
        departments: DepartmentRepository(db),
      );
    } catch (e, st) {
      // Καμία δεύτερη προσπάθεια (απόφαση Διευθυντή 02/10): ο κατάλογος
      // ξαναδιαβάζεται, ώστε ό,τι έμεινε να φαίνεται και να σβήνεται από
      // τον Κατάλογο. Η εκκρεμότητα μένει — περιγράφει ό,τι υπάρχει ακόμη.
      await _refreshAfterFailure('quick add undo failed', e, st);
      final cause = humanizeUserFacingError(e).trim();
      final causeSentence = cause.endsWith('.') ? cause : '$cause.';
      return 'Η αναίρεση δεν ολοκληρώθηκε: $causeSentence '
          'Ό,τι πρόλαβε να σβηστεί έμεινε σβησμένο — ελέγξτε τον Κατάλογο.';
    }

    final taskId = host.associationQuickTaskId;
    if (taskId != null) {
      try {
        await ref.read(taskServiceProvider).deleteTask(taskId);
      } catch (e, st) {
        developer.log(
          'quick add undo: task delete failed',
          name: 'SmartEntitySelectorNotifier',
          error: e,
          stackTrace: st,
        );
      }
      host.associationQuickTaskId = null;
      invalidateTaskListProviders(ref);
    }

    await refreshDirectoryCaches(
      ref,
      users: true,
      equipment: true,
      departments: true,
    );
    if (!ref.mounted) return quickAddUndoSummary(record);

    state = state.copyWith(
      clearSelectedCaller: true,
      clearSelectedEquipment: true,
      callerNoMatch: true,
    );
    host.callerAwaitingPhoneAssociation = false;
    return quickAddUndoSummary(record);
  }

  Future<OrphanQuickAddResult?> quickAddOrphanToDepartment({
    bool forceSharedOnConflict = false,
  }) async {
    if (!state.needsOrphanDepartmentQuickAdd) return null;

    final lookup = (await ref.read(lookupServiceProvider.future)).service;
    final plan = await _planOrphanQuickAdd(lookup);

    if (!forceSharedOnConflict) {
      final confirmation = orphanQuickAddConflictMessage(plan);
      if (confirmation != null) {
        return OrphanQuickAddResult(
          requiresConfirmation: true,
          message: confirmation,
        );
      }
    }

    try {
      final departmentId = await _resolveOrphanDepartmentId(plan);
      if (departmentId == null) {
        return const OrphanQuickAddResult.failed(
          'Δεν βρέθηκε/δημιουργήθηκε τμήμα.',
        );
      }

      await _writeOrphanShared(plan, departmentId);
      // Ό,τι γεννήθηκε τώρα μπορεί να αναιρεθεί όσο κρατά η στιγμή. Η κρίση
      // «υπήρχε πριν;» έχει ήδη γίνει στο πλάνο — εδώ απλώς επιβιώνει.
      host.lastQuickAddUndo = QuickAddUndoRecord(
        createdDepartmentId: plan.departmentExistedBefore ? null : departmentId,
        createdDepartmentName: plan.departmentExistedBefore
            ? null
            : plan.departmentText,
        createdPhone: (plan.phoneNeedsShared && !plan.phoneExistedBefore)
            ? plan.phone
            : null,
        createdEquipmentCode:
            (plan.equipmentNeedsShared && !plan.equipmentExistedBefore)
            ? plan.equipmentCode
            : null,
      );
      return await _finishOrphanQuickAdd(plan, departmentId);
    } catch (e, st) {
      return OrphanQuickAddResult.failed(await _saveFailed(e, st));
    }
  }

  /// Βήμα 1 — τι υπάρχει σήμερα και τι πρόκειται να γραφτεί.
  ///
  /// Η απάντηση στο «τι θα γραφτεί» **δεν υπολογίζεται εδώ**: ζητείται από την
  /// ίδια κρίση που αποφασίζει αν θα εμφανιστεί η γρήγορη καταχώρηση.
  Future<OrphanQuickAddPlan> _planOrphanQuickAdd(LookupService lookup) async {
    final s = state;
    final deptText = s.departmentText.trim();
    final phoneText = s.selectedPhone?.trim();
    final phone = (phoneText != null && phoneText.isNotEmpty)
        ? phoneText
        : null;
    final equipmentText = s.equipmentText.trim();
    final equipmentCode = equipmentText.isEmpty ? null : equipmentText;
    final needsShared = s.orphanNeedsSharedFlags(lookup);

    final db = await DatabaseHelper.instance.database;

    return OrphanQuickAddPlan(
      departmentText: deptText,
      departmentId:
          s.selectedDepartmentId ?? lookup.findDepartmentByName(deptText)?.id,
      phone: phone,
      equipmentCode: equipmentCode,
      phoneUsage: phone == null ? null : lookup.checkPhoneUsage(phone),
      equipmentUsage: equipmentCode == null
          ? null
          : lookup.checkEquipmentUsage(equipmentCode),
      phoneNeedsShared: needsShared.phoneNeedsShared,
      equipmentNeedsShared: needsShared.equipmentNeedsShared,
      departmentExistedBefore:
          deptText.isNotEmpty &&
          await DepartmentRepository(db).departmentNameExists(deptText),
      phoneExistedBefore: phone == null
          ? true
          : await PhoneRepository(db).phoneNumberExists(phone),
      equipmentExistedBefore: equipmentCode == null
          ? true
          : await EquipmentRepository(db).equipmentCodeExists(equipmentCode),
    );
  }

  /// Βήμα 2 — το τμήμα της φόρμας, δημιουργημένο αν δεν υπήρχε.
  Future<int?> _resolveOrphanDepartmentId(OrphanQuickAddPlan plan) async {
    final known = plan.departmentId;
    if (known != null) return known;
    final db = await DatabaseHelper.instance.database;
    return DepartmentRepository(
      db,
    ).getOrCreateDepartmentIdByName(plan.departmentText);
  }

  /// Βήμα 3 — μόνο οι εγγραφές. Καμία κρίση, κανένα μήνυμα.
  Future<void> _writeOrphanShared(
    OrphanQuickAddPlan plan,
    int departmentId,
  ) async {
    if (!plan.writesAnything) return;

    final phone = plan.phone;
    final equipmentCode = plan.equipmentCode;
    final db = await DatabaseHelper.instance.database;
    if (plan.phoneNeedsShared && phone != null) {
      await PhoneRepository(db).updatePhoneDepartment(phone, departmentId);
    }
    if (plan.equipmentNeedsShared && equipmentCode != null) {
      await EquipmentRepository(
        db,
      ).updateEquipmentDepartment(equipmentCode, departmentId);
    }
  }

  /// Βήμα 4 — ανανέωση καταλόγων, ενημέρωση της φόρμας, μήνυμα, εκκρεμότητα.
  Future<OrphanQuickAddResult> _finishOrphanQuickAdd(
    OrphanQuickAddPlan plan,
    int departmentId,
  ) async {
    await refreshDirectoryCaches(
      ref,
      users: plan.phoneNeedsShared,
      equipment: plan.equipmentNeedsShared,
      departments: true,
    );
    if (!ref.mounted) {
      return const OrphanQuickAddResult(
        requiresConfirmation: false,
        message: 'Η συσχέτιση ολοκληρώθηκε αλλά το container δεν είναι ενεργό.',
      );
    }

    final refreshed = (await ref.read(lookupServiceProvider.future)).service;
    final finalDepartment = refreshed.findDepartmentByName(plan.departmentText);
    state = state.copyWith(
      selectedDepartmentId: finalDepartment?.id ?? departmentId,
      departmentText: finalDepartment?.name ?? plan.departmentText,
      callerNoMatch: false,
      equipmentNoMatch: false,
    );

    // Το τμήμα λέγεται πλέον όπως το γράφει ο κατάλογος, όχι όπως πληκτρολογήθηκε.
    final departmentName = state.departmentText.trim();
    final success = orphanQuickAddSuccessMessage(
      phoneWritten: plan.phoneNeedsShared,
      equipmentWritten: plan.equipmentNeedsShared,
      departmentName: departmentName,
    );

    await _syncOrphanQuickTask(
      plan: plan,
      departmentId: finalDepartment?.id ?? departmentId,
      departmentName: departmentName,
      refreshed: refreshed,
      summary: success,
    );

    return OrphanQuickAddResult(
      requiresConfirmation: false,
      message: success,
      successMessage: success,
    );
  }

  /// Η γρήγορη εκκρεμότητα του κύκλου — υπενθύμιση, ποτέ εμπόδιο.
  ///
  /// Η αποτυχία της δεν ακυρώνει καταχώρηση που ήδη γράφτηκε: καταγράφεται και
  /// η ροή συνεχίζει.
  Future<void> _syncOrphanQuickTask({
    required OrphanQuickAddPlan plan,
    required int departmentId,
    required String departmentName,
    required LookupService refreshed,
    required String summary,
  }) async {
    if (!plan.hasNewEntity && host.associationQuickTaskId == null) return;

    final equipmentCode = plan.equipmentCode;
    final resolved = (equipmentCode != null && equipmentCode.isNotEmpty)
        ? refreshed.findEquipmentsByCode(equipmentCode)
        : const <EquipmentModel>[];

    try {
      await _syncAssociationQuickTask(
        newEntityEligible: plan.hasNewEntity,
        associationWorkDone: plan.writesAnything,
        summaryText: summary,
        callerName: null,
        callerId: null,
        departmentId: departmentId,
        equipmentId: resolved.isNotEmpty ? resolved.first.id : null,
        phoneText: plan.phone,
        userText: null,
        equipmentText: equipmentCode,
        departmentText: departmentName.isEmpty ? null : departmentName,
      );
    } catch (e, st) {
      developer.log(
        'orphan quick add task sync failed',
        name: 'SmartEntitySelectorNotifier',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Το «+» της φόρμας κλήσης: καταχωρεί στον κατάλογο ό,τι η φόρμα ξέρει
  /// αλλά ο κατάλογος όχι. Επιστρέφει το μήνυμα για τον χρήστη· `null` όταν
  /// δεν υπήρχε δουλειά ή ο χρήστης ακύρωσε κάποια ερώτηση.
  ///
  /// Δύο ροές, ίδια σειρά: **πρώτα όλες οι ερωτήσεις** χωρίς καμία εγγραφή —
  /// η «Ακύρωση» αφήνει τη βάση ανέγγιχτη — **μετά οι εγγραφές**, και στο
  /// τέλος η φόρμα, το μήνυμα και η γρήγορη εκκρεμότητα.
  Future<String?> associateCurrentIfNeeded({
    bool updatePrimaryDepartment = false,
    BuildContext? context,
  }) async {
    final lookup = ref.read(lookupServiceProvider).value?.service;
    if (!state.needsAssociation(lookup)) return null;

    final db = await DatabaseHelper.instance.database;
    final auditSince = await host.maxAuditLogId(db);
    // Οθόνη που έκλεισε στο μεταξύ: καμία ερώτηση, καμία εγγραφή. Χωρίς
    // οθόνη καθόλου (`null`) κάθε ροή αποφασίζει μόνη της.
    if (context != null && !context.mounted) return null;
    if (state.needsNewCallerCreation) {
      return _associateNewCaller(
        db: db,
        lookup: lookup,
        auditSince: auditSince,
        context: context,
      );
    }
    if (state.selectedCaller?.id == null) return null;
    return _associateExistingCaller(
      db: db,
      lookup: lookup,
      auditSince: auditSince,
      updatePrimaryDepartment: updatePrimaryDepartment,
      context: context,
    );
  }

  /// Το τμήμα που εννοεί η φόρμα: το επιλεγμένο, αλλιώς [created] (μόλις
  /// δημιουργημένο), αλλιώς αυτό που ταιριάζει στο κείμενο του πεδίου.
  int? _formDepartmentId(LookupService? lookup, {int? created}) =>
      state.selectedDepartmentId ??
      created ??
      lookup?.findDepartmentByName(state.departmentText)?.id;

  /// Αποτυχία στη μέση του «+»: η αιτία γράφεται για διάγνωση, ο χρήστης
  /// παίρνει το ανθρώπινο μήνυμα.
  ///
  /// Ό,τι πρόλαβε να γραφτεί πριν από το σφάλμα μένει στη βάση· οι κατάλογοι
  /// ξαναδιαβάζονται, ώστε η φόρμα να δείχνει ό,τι πράγματι υπάρχει — αλλιώς
  /// το επόμενο «+» ρωτά ξανά για ό,τι έχει ήδη γίνει.
  Future<String> _saveFailed(Object error, StackTrace stackTrace) async {
    await _refreshAfterFailure('quick add failed', error, stackTrace);
    return 'Σφάλμα αποθήκευσης: ${humanizeUserFacingError(error)}';
  }

  /// Κοινό σε κάθε εγγραφή του «+» (καλούντας, κοινόχρηστα, αναίρεση) που
  /// σταμάτησε στη μέση: η αιτία γράφεται για διάγνωση και οι κατάλογοι
  /// ξαναδιαβάζονται.
  Future<void> _refreshAfterFailure(
    String what,
    Object error,
    StackTrace stackTrace,
  ) async {
    developer.log(
      what,
      name: 'SmartEntitySelectorNotifier',
      error: error,
      stackTrace: stackTrace,
    );
    try {
      await refreshDirectoryCaches(
        ref,
        users: true,
        equipment: true,
        departments: true,
      );
    } catch (e, st) {
      developer.log(
        '$what: catalog refresh failed too',
        name: 'SmartEntitySelectorNotifier',
        error: e,
        stackTrace: st,
      );
    }
  }

  static const _containerGone =
      'Σφάλμα αποθήκευσης: το container δεν είναι ενεργό.';

  // ── Νέος καλών ─────────────────────────────────────────────────────────

  Future<String?> _associateNewCaller({
    required Database db,
    required LookupService? lookup,
    required int auditSince,
    required BuildContext? context,
  }) async {
    final input = await _readNewCallerInput(db, lookup);
    if (context != null && !context.mounted) return null;
    try {
      final answers = await _askNewCallerQuestions(input, context);
      if (answers == null) return null;
      final created = await _writeNewCaller(db, input, answers);
      // Το μήνυμα λέει ό,τι ΕΓΙΝΕ — και το ίδιο κείμενο γίνεται περίληψη της
      // γρήγορης εκκρεμότητας, όπως και για τον υπάρχοντα καλούντα. Η
      // περιγραφή του κουμπιού είναι πρόβλεψη πριν από τις ερωτήσεις.
      final message = _newCallerMessage(input, answers);
      final error = await _showNewCallerInForm(
        input,
        answers,
        created,
        message,
      );
      if (error != null) return error;
      await host.trackDerivativeAuditsSince(auditSince);
      return message;
    } catch (e, st) {
      return await _saveFailed(e, st);
    }
  }

  /// Ό,τι γράφει η φόρμα, και τι **υπήρχε ήδη** — πριν αλλάξει οτιδήποτε,
  /// ώστε μήνυμα και αναίρεση να ξεχωρίζουν το νέο από το υπάρχον.
  Future<_NewCallerInput> _readNewCallerInput(
    Database db,
    LookupService? lookupBefore,
  ) async {
    final name = NameParserUtility.stripDisplayDecorations(
      state.normalizedCallerDisplayText,
    );
    final phone = state.selectedPhone?.trim();
    // Εταιρεία δεν γίνεται κάτοχος εξοπλισμού: ο νέος καλών δημιουργείται
    // κανονικά με το τηλέφωνό του, αλλά ο κωδικός του μηχανήματος μένει
    // αναφορά της κλήσης και δεν δένεται πάνω του.
    final equipmentCode = state.departmentAcceptsEquipment(lookupBefore)
        ? state.equipmentText.trim()
        : '';
    final departmentText = state.departmentText.trim();
    final departmentExisted =
        departmentText.isNotEmpty &&
        await DepartmentRepository(db).departmentNameExists(departmentText);
    final phoneExisted = (phone != null && phone.isNotEmpty)
        ? await PhoneRepository(db).phoneNumberExists(phone)
        : false;
    final equipmentExisted = equipmentCode.isNotEmpty
        ? await EquipmentRepository(db).equipmentCodeExists(equipmentCode)
        : false;

    final lookup = ref.read(lookupServiceProvider).value?.service;
    final departmentId = _formDepartmentId(lookup);
    return (
      name: name,
      parsed: NameParserUtility.parse(name),
      phone: phone,
      equipmentCode: equipmentCode,
      departmentText: departmentText,
      departmentExisted: departmentExisted,
      phoneExisted: phoneExisted,
      equipmentExisted: equipmentExisted,
      lookup: lookup,
      departmentId: departmentId,
      createsDepartment: departmentId == null && departmentText.isNotEmpty,
    );
  }

  /// Οι ερωτήσεις γίνονται ΠΡΙΝ δημιουργηθεί οτιδήποτε — και το νέο τμήμα:
  /// `null` = «Ακύρωση», και η βάση μένει ανέγγιχτη.
  Future<_NewCallerAnswers?> _askNewCallerQuestions(
    _NewCallerInput input,
    BuildContext? context,
  ) async {
    final equipmentMove = await _askEquipmentMove(
      context: context,
      lookup: input.lookup,
      equipmentCode: input.equipmentCode,
      newOwnerId: null,
      targetDepartmentId: input.departmentId,
      newOwnerName: input.name,
    );
    if (equipmentMove.cancelled) return null;

    final phones = PhoneListParser.splitPhones(input.phone);
    if (phones.isEmpty) {
      return (
        equipmentMove: equipmentMove,
        phones: phones,
        phoneForAssociation: input.phone,
        phoneResolutions: null,
      );
    }
    if (context != null && !context.mounted) return null;
    final departmentId = input.departmentId;
    final prepared = await _askPhoneAssociation(
      context: context,
      phone: phones.first,
      targetDepartmentId: departmentId,
      targetIsNewDepartment: input.createsDepartment,
      editingUserId: null,
      userDisplayName: input.name,
      targetDepartmentName: departmentId != null
          ? (input.lookup?.departmentIdToName[departmentId] ??
                input.departmentText)
          : input.departmentText,
    );
    if (prepared.cancelled) return null;
    final preparedPhone = prepared.phone;
    return (
      equipmentMove: equipmentMove,
      phones: preparedPhone == null
          ? <String>[]
          : PhoneListParser.splitPhones(preparedPhone),
      phoneForAssociation: preparedPhone,
      phoneResolutions: prepared.resolutions,
    );
  }

  /// Οι εγγραφές του νέου καλούντα, και η προσφορά αναίρεσης της στιγμής.
  Future<({int userId, int? departmentId})> _writeNewCaller(
    Database db,
    _NewCallerInput input,
    _NewCallerAnswers answers,
  ) async {
    var departmentId = input.departmentId;
    if (input.createsDepartment) {
      departmentId = await DepartmentRepository(
        db,
      ).getOrCreateDepartmentIdByName(state.departmentText.trim());
    }
    await _applyPhoneResolutions(
      phonesRepo: PhoneRepository(db),
      resolutions: answers.phoneResolutions,
      targetDepartmentId: departmentId,
    );
    final users = UserRepository(db);
    final userId = await users.insertUser(
      firstName: input.parsed.firstName,
      lastName: input.parsed.lastName,
      phones: answers.phones.isEmpty ? null : answers.phones,
      departmentId: departmentId,
    );
    await users.updateAssociationsIfNeeded(
      userId,
      answers.phoneForAssociation,
      input.equipmentCode.isNotEmpty ? input.equipmentCode : null,
    );
    await _releaseMovedEquipment(
      EquipmentRepository(db),
      answers.equipmentMove,
    );

    // Η προσφορά αναίρεσης της στιγμής: μόνο ό,τι δεν υπήρχε πριν.
    host.lastQuickAddUndo = QuickAddUndoRecord(
      createdUserId: userId,
      createdUserName: input.name,
      createdDepartmentId: input.departmentExisted ? null : departmentId,
      createdDepartmentName: input.departmentExisted
          ? null
          : input.departmentText,
      createdPhone: (!input.phoneExisted && answers.phones.isNotEmpty)
          ? answers.phones.first
          : null,
      createdEquipmentCode:
          (!input.equipmentExisted && input.equipmentCode.isNotEmpty)
          ? input.equipmentCode
          : null,
    );
    return (userId: userId, departmentId: departmentId);
  }

  /// Ο νέος καλών μπαίνει στη φόρμα, οι κατάλογοι ανανεώνονται, και γράφεται
  /// η γρήγορη εκκρεμότητα. Επιστρέφει μήνυμα σφάλματος μόνο αν η οθόνη
  /// έκλεισε στο μεταξύ.
  Future<String?> _showNewCallerInForm(
    _NewCallerInput input,
    _NewCallerAnswers answers,
    ({int userId, int? departmentId}) created,
    String message,
  ) async {
    final s = state;
    final lookupNow = ref.read(lookupServiceProvider).value?.service;
    final departmentIdNow = _formDepartmentId(
      lookupNow,
      created: created.departmentId,
    );
    final equipTrim = s.equipmentText.trim();
    final departmentTrim = s.departmentText.trim();
    // Όνομα τμήματος: από το lookup αν το ξέρει ήδη, αλλιώς από το πεδίο —
    // το νεοδημιουργημένο τμήμα δεν έχει προλάβει να μπει στο cache.
    final departmentNameNow = departmentIdNow == null
        ? null
        : (lookupNow?.departmentIdToName[departmentIdNow] ?? departmentTrim);
    state = state.copyWith(
      selectedCaller: UserModel(
        id: created.userId,
        firstName: input.parsed.firstName,
        lastName: input.parsed.lastName,
        phones: answers.phones,
        departmentId: departmentIdNow,
        departmentName: departmentNameNow,
      ),
      selectedDepartmentId: departmentIdNow,
      selectedEquipment: equipTrim.isNotEmpty
          ? EquipmentModel(code: equipTrim)
          : s.selectedEquipment,
      callerDisplayText: s.callerDisplayText.trim().isNotEmpty
          ? s.callerDisplayText
          : input.name,
      departmentText: s.departmentText,
    );
    host.callerAwaitingPhoneAssociation = answers.phones.isEmpty;
    await refreshDirectoryCaches(
      ref,
      users: true,
      equipment: input.equipmentCode.isNotEmpty,
      departments: input.departmentText.isNotEmpty,
    );
    if (!ref.mounted) return _containerGone;

    final refreshedLookup = (await ref.read(
      lookupServiceProvider.future,
    )).service;
    final matchedEquipment = equipTrim.isEmpty
        ? const <EquipmentModel>[]
        : refreshedLookup.findEquipmentsByCode(equipTrim);
    // Πλήρες EquipmentModel με id — αλλιώς το hasEquipmentAssociation μένει
    // false και το submit κλήσης ξανατρέχει συσχέτιση + δεύτερη γρήγορη
    // εκκρεμότητα.
    if (matchedEquipment.isNotEmpty) {
      state = state.copyWith(selectedEquipment: matchedEquipment.first);
    }
    await _syncAssociationQuickTask(
      newEntityEligible: true,
      associationWorkDone: true,
      summaryText: message,
      callerName: state.selectedCaller?.name ?? state.callerDisplayText.trim(),
      callerId: created.userId,
      departmentId:
          departmentIdNow ??
          refreshedLookup.findDepartmentByName(s.departmentText)?.id,
      equipmentId: matchedEquipment.isEmpty ? null : matchedEquipment.first.id,
      phoneText: s.selectedPhone?.trim(),
      userText: _nullIfEmpty(s.callerDisplayText),
      equipmentText: _nullIfEmpty(equipTrim),
      departmentText: _nullIfEmpty(departmentTrim),
    );
    return null;
  }

  /// Το μήνυμα για νέο καλούντα, γραμμή-γραμμή.
  String _newCallerMessage(_NewCallerInput input, _NewCallerAnswers answers) {
    final department = input.departmentText;
    // Το τηλέφωνο που ΣΥΝΔΕΘΗΚΕ, όχι αυτό της φόρμας: «μένει στο τμήμα
    // του» στην ερώτηση σύγκρουσης σημαίνει ότι δεν δέθηκε με τον καλούντα.
    final phone = answers.phones.isEmpty ? null : answers.phoneForAssociation;
    final code = input.equipmentCode;
    final released = answers.equipmentMove.ownersToRelease;
    final fullName =
        (UserModel(
                  firstName: input.parsed.firstName,
                  lastName: input.parsed.lastName,
                ).name ??
                state.callerDisplayText)
            .trim();
    return <String>[
      'Δημιουργήθηκε νέος χρήστης $fullName'
          '${department.isNotEmpty ? ' στο τμήμα: $department' : ''}',
      if (department.isNotEmpty && !input.departmentExisted)
        'Δημιουργήθηκε νέο τμήμα: $department',
      if (phone != null && phone.isNotEmpty)
        input.phoneExisted
            ? 'Συσχετίστηκε τηλέφωνο: $phone'
            : 'Δημιουργήθηκε νέο τηλέφωνο: $phone',
      if (code.isNotEmpty)
        input.equipmentExisted
            ? 'Συσχετίστηκε εξοπλισμός: $code'
            : 'Δημιουργήθηκε νέος εξοπλισμός: $code',
      if (released.isNotEmpty)
        'Ο εξοπλισμός $code αφαιρέθηκε από: '
            '${released.map((o) => o.name ?? '').join(', ')}',
    ].join('\n');
  }

  // ── Υπάρχων καλών ──────────────────────────────────────────────────────

  Future<String?> _associateExistingCaller({
    required Database db,
    required LookupService? lookup,
    required int auditSince,
    required bool updatePrimaryDepartment,
    required BuildContext? context,
  }) async {
    final work = await _readExistingCallerWork(
      db,
      lookup,
      updatePrimaryDepartment,
    );
    if (context != null && !context.mounted) return null;
    try {
      final answers = await _askExistingCallerQuestions(work, lookup, context);
      if (answers == null) return null;
      final written = await _writeExistingCaller(db, work, answers);
      return await _finishExistingCaller(work, answers, written, auditSince);
    } catch (e, st) {
      return await _saveFailed(e, st);
    }
  }

  /// Τι έχει να γίνει για τον υπάρχοντα καλούντα, και τι από αυτό είναι
  /// **νέα** εγγραφή (κρίνει αν γεννιέται γρήγορη εκκρεμότητα).
  Future<_ExistingCallerWork> _readExistingCallerWork(
    Database db,
    LookupService? lookup,
    bool updatePrimaryDepartment,
  ) async {
    final caller = state.selectedCaller!;
    final phone = state.hasPhoneAssociation(lookup)
        ? null
        : state.selectedPhone?.trim();
    final eqCode = state.hasEquipmentAssociation(lookup)
        ? null
        : state.equipmentText.trim();
    final hadPhoneWork = phone != null && phone.isNotEmpty;
    final hadEqWork = eqCode != null && eqCode.isNotEmpty;
    final newPhoneRow =
        hadPhoneWork && !await PhoneRepository(db).phoneNumberExists(phone);
    final newEquipmentRow =
        hadEqWork && !await EquipmentRepository(db).equipmentCodeExists(eqCode);
    final departmentText = state.departmentText.trim();
    final callerHadNoPrimaryDept =
        caller.departmentId == null &&
        (caller.departmentName ?? '').trim().isEmpty;
    // Όταν ο καλών δεν είχε κύριο τμήμα, η πρώτη ανάθεση τμήματος στο
    // πορτοκαλί βήμα δεν μπλοκάρεται από dialog «Όχι» (δεν υπάρχει παλιό
    // τμήμα προς διατήρηση).
    final updatesPrimaryDepartment =
        updatePrimaryDepartment ||
        (state.hasPendingDepartmentChange &&
            callerHadNoPrimaryDept &&
            departmentText.isNotEmpty);
    final newDepartmentRow =
        updatesPrimaryDepartment &&
        departmentText.isNotEmpty &&
        !await DepartmentRepository(db).departmentNameExists(departmentText);
    return (
      userId: caller.id!,
      phone: phone,
      eqCode: eqCode,
      hadEqWork: hadEqWork,
      updatesPrimaryDepartment: updatesPrimaryDepartment,
      newDepartmentRow: newDepartmentRow,
      newEntityEligible: newPhoneRow || newEquipmentRow || newDepartmentRow,
      // Κρατιέται ΠΡΙΝ από κάθε αλλαγή: μετά την εγγραφή ο καλών έχει ήδη
      // το νέο τμήμα και η γραμμή δεν θα έβγαινε. Μπαίνει στο μήνυμα μόνο
      // αν η μεταφορά έγινε πράγματι.
      departmentChangeLine: state.pendingDepartmentChangeTooltip(lookup),
      callerName: caller.name ?? 'άγνωστος',
    );
  }

  /// Όλες οι ερωτήσεις του «+», πριν από κάθε εγγραφή: `null` = «Ακύρωση»
  /// σε οποιαδήποτε, και τότε δεν γράφεται **τίποτα** — ούτε ο εξοπλισμός.
  Future<_ExistingCallerAnswers?> _askExistingCallerQuestions(
    _ExistingCallerWork work,
    LookupService? lookup,
    BuildContext? context,
  ) async {
    final caller = state.selectedCaller!;
    final departmentText = state.departmentText.trim();
    final knownTargetDepartmentId = _formDepartmentId(lookup);

    // Εξοπλισμός που ανήκει σε υπάλληλο άλλου τμήματος: ρητή ερώτηση.
    final equipmentMove = await _askEquipmentMove(
      context: context,
      lookup: lookup,
      equipmentCode: work.hadEqWork ? work.eqCode! : '',
      newOwnerId: work.userId,
      targetDepartmentId: work.updatesPrimaryDepartment
          ? knownTargetDepartmentId
          : caller.departmentId,
      newOwnerName: work.callerName,
    );
    if (equipmentMove.cancelled) return null;

    // Αλλαγή κύριου τμήματος: «τι απογίνονται όσα κουβαλά». Νέο τμήμα
    // (χωρίς id ακόμη) διαβάζεται ως νοσοκομείο από την ερώτηση.
    final movesDepartment =
        work.updatesPrimaryDepartment &&
        departmentText.isNotEmpty &&
        (knownTargetDepartmentId == null ||
            knownTargetDepartmentId != caller.departmentId);
    _AssetsOnDepartmentChange? stayingBehind;
    if (movesDepartment) {
      if (context != null && !context.mounted) return null;
      stayingBehind = await _confirmAssetsOnDepartmentChange(
        context: context,
        caller: caller,
        targetDepartmentId: knownTargetDepartmentId,
      );
      if (stayingBehind == null) return null;
    }

    final phone = work.phone;
    if (phone == null || phone.isEmpty) {
      return (
        equipmentMove: equipmentMove,
        stayingBehind: stayingBehind,
        phoneToLink: phone,
        phoneResolutions: null,
        phoneDepartmentId: null,
      );
    }
    final phoneDepartmentId = caller.departmentId ?? _formDepartmentId(lookup);
    if (context != null && !context.mounted) return null;
    final prepared = await _askPhoneAssociation(
      context: context,
      phone: phone,
      targetDepartmentId: phoneDepartmentId,
      editingUserId: work.userId,
      userDisplayName: caller.name ?? state.callerDisplayText.trim(),
      targetDepartmentName: phoneDepartmentId != null
          ? (lookup?.departmentIdToName[phoneDepartmentId] ?? departmentText)
          : departmentText,
    );
    if (prepared.cancelled) return null;
    return (
      equipmentMove: equipmentMove,
      stayingBehind: stayingBehind,
      phoneToLink: prepared.phone,
      phoneResolutions: prepared.resolutions,
      phoneDepartmentId: phoneDepartmentId,
    );
  }

  /// Οι εγγραφές του υπάρχοντος καλούντα. Επιστρέφει το τμήμα της φόρμας
  /// (δημιουργημένο, αν χρειάστηκε) και αν έγινε κύριο τμήμα του καλούντα.
  Future<_ExistingCallerWrite> _writeExistingCaller(
    Database db,
    _ExistingCallerWork work,
    _ExistingCallerAnswers answers,
  ) async {
    // Από εδώ και κάτω αρχίζουν οι εγγραφές.
    await _applyPhoneResolutions(
      phonesRepo: PhoneRepository(db),
      resolutions: answers.phoneResolutions,
      targetDepartmentId: answers.phoneDepartmentId,
    );
    await UserRepository(db).updateAssociationsIfNeeded(
      work.userId,
      answers.phoneToLink,
      work.hadEqWork ? work.eqCode : null,
    );
    await _releaseMovedEquipment(
      EquipmentRepository(db),
      answers.equipmentMove,
    );

    final lookup = ref.read(lookupServiceProvider).value?.service;
    var departmentId = _formDepartmentId(lookup);
    if (work.updatesPrimaryDepartment &&
        state.departmentText.trim().isNotEmpty) {
      // Αν το τμήμα δεν υπάρχει ακόμα στη βάση, το δημιουργούμε ώστε να
      // πάρουμε id.
      departmentId ??= await DepartmentRepository(
        db,
      ).getOrCreateDepartmentIdByName(state.departmentText.trim());
    }

    // Η ερώτηση «τι απογίνονται όσα κουβαλά» έγινε ήδη· εδώ εφαρμόζεται
    // μόνο η απάντηση.
    final caller = state.selectedCaller!;
    final decision = answers.stayingBehind;
    if (decision == null ||
        departmentId == null ||
        departmentId == caller.departmentId) {
      return (departmentId: departmentId, changed: false);
    }
    // Γράφεται ΜΟΝΟ το τμήμα. Ολόκληρη η καρτέλα από τη μνήμη της φόρμας θα
    // έσβηνε ό,τι δεν κρατά εκείνη (ψευδώνυμο) και θα ξεδένε το τηλέφωνο
    // που μόλις συνδέθηκε πιο πάνω.
    await UserRepository(db).updateUser(work.userId, <String, dynamic>{
      'department_id': departmentId,
    }, expected: null);
    await applyAssetsStayingBehind(
      db: db,
      userId: work.userId,
      oldDepartmentId: caller.departmentId,
      phones: decision.phones,
      equipment: decision.equipment,
      currentPhones: caller.phones,
      equipmentTakenFromCoOwners: decision.takenFromCoOwners,
      newDepartmentId: departmentId,
      phonesLeftWithCoOwners: decision.phonesLeftWithCoOwners,
      phonesTakenFromCoOwners: decision.phonesTakenFromCoOwners,
    );
    return (departmentId: departmentId, changed: true);
  }

  /// Η φόρμα, οι κατάλογοι, το μήνυμα και η γρήγορη εκκρεμότητα του
  /// υπάρχοντος καλούντα.
  Future<String?> _finishExistingCaller(
    _ExistingCallerWork work,
    _ExistingCallerAnswers answers,
    _ExistingCallerWrite written,
    int auditSince,
  ) async {
    final departmentChanged = written.changed;
    final newDepartmentId = departmentChanged ? written.departmentId : null;
    final lookup = ref.read(lookupServiceProvider).value?.service;
    final s = state;
    final phoneToLink = answers.phoneToLink;
    final phoneLinked = phoneToLink != null && phoneToLink.isNotEmpty;
    final currentPhones = List<String>.from(
      s.selectedCaller?.phones ?? const [],
    );
    final updatedPhones =
        phoneLinked &&
            !PhoneListParser.containsPhone(
              PhoneListParser.joinPhones(currentPhones),
              phoneToLink,
            )
        ? [...currentPhones, phoneToLink]
        : currentPhones;
    final eqCode = work.eqCode;
    state = state.copyWith(
      // Αντίγραφο με ΟΛΑ τα στοιχεία του καλούντα: ό,τι έλειπε εδώ
      // (ψευδώνυμο, τοποθεσία, Lansweeper) χανόταν στην επόμενη εγγραφή.
      selectedCaller: s.selectedCaller!.copyWith(
        phones: updatedPhones,
        departmentId: newDepartmentId ?? s.selectedCaller!.departmentId,
        // Αλλαγή κύριου τμήματος: νέο όνομα από lookup ή από το πεδίο
        // (το φρεσκοδημιουργημένο τμήμα λείπει ακόμα από το cache).
        departmentName: !departmentChanged
            ? null
            : (lookup?.departmentIdToName[newDepartmentId] ??
                  s.departmentText.trim()),
      ),
      selectedDepartmentId: newDepartmentId ?? s.selectedDepartmentId,
      selectedEquipment: work.hadEqWork
          ? EquipmentModel(
              id: s.selectedEquipment?.id,
              code: eqCode,
              type: s.selectedEquipment?.type,
              notes: s.selectedEquipment?.notes,
            )
          : s.selectedEquipment,
    );

    await refreshDirectoryCaches(
      ref,
      users: true,
      equipment: work.hadEqWork,
      departments: departmentChanged || work.newDepartmentRow,
    );
    if (!ref.mounted) return _containerGone;
    final refreshedLookup = (await ref.read(
      lookupServiceProvider.future,
    )).service;
    final matchedEquipment = work.hadEqWork
        ? refreshedLookup.findEquipmentsByCode(eqCode!)
        : const <EquipmentModel>[];
    if (matchedEquipment.isNotEmpty) {
      state = state.copyWith(selectedEquipment: matchedEquipment.first);
    }

    final resultMessage = _existingCallerMessage(
      work,
      answers,
      departmentChanged: departmentChanged,
    );
    await _syncAssociationQuickTask(
      newEntityEligible: work.newEntityEligible,
      associationWorkDone: phoneLinked || work.hadEqWork || departmentChanged,
      summaryText: resultMessage,
      callerName: s.selectedCaller?.name ?? s.callerDisplayText.trim(),
      callerId: s.selectedCaller?.id,
      departmentId:
          written.departmentId ??
          refreshedLookup.findDepartmentByName(s.departmentText)?.id,
      equipmentId: matchedEquipment.isNotEmpty
          ? matchedEquipment.first.id
          : s.selectedEquipment?.id,
      phoneText: s.selectedPhone?.trim(),
      userText: _nullIfEmpty(s.callerDisplayText),
      equipmentText: _nullIfEmpty(s.equipmentText),
      departmentText: _nullIfEmpty(s.departmentText),
    );
    await host.trackDerivativeAuditsSince(auditSince);
    return resultMessage;
  }

  /// Το μήνυμα για υπάρχοντα καλούντα — `null` όταν τελικά δεν έγινε τίποτα.
  ///
  /// Περιγράφει ό,τι ΕΓΙΝΕ, όχι ό,τι προβλεπόταν πριν από τις ερωτήσεις: ένα
  /// «Όχι» στη μεταφορά δεν αφήνει γραμμή αλλαγής τμήματος.
  String? _existingCallerMessage(
    _ExistingCallerWork work,
    _ExistingCallerAnswers answers, {
    required bool departmentChanged,
  }) {
    final phone = answers.phoneToLink;
    final code = work.eqCode;
    final released = answers.equipmentMove.ownersToRelease;
    final addedParts = <String>[
      if (phone != null && phone.isNotEmpty) 'τηλεφώνου: $phone',
      if (work.hadEqWork) 'εξοπλισμού: $code',
    ];
    final lines = <String>[
      if (addedParts.isNotEmpty)
        'Προσθήκη ${addedParts.join(' και ')} στο ${work.callerName}',
      if (released.isNotEmpty)
        'Ο εξοπλισμός $code αφαιρέθηκε από: '
            '${released.map((o) => o.name ?? '').join(', ')}',
      if (departmentChanged && work.departmentChangeLine != null)
        work.departmentChangeLine!,
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  static String? _nullIfEmpty(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Μία γρήγορη εκκρεμότητα ανά κύκλο: δημιουργία ή append/merge στην υπάρχουσα.
  Future<void> _syncAssociationQuickTask({
    required bool newEntityEligible,
    required bool associationWorkDone,
    required String? summaryText,
    required String? callerName,
    required int? callerId,
    required int? departmentId,
    required int? equipmentId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
  }) async {
    final taskService = ref.read(taskServiceProvider);
    final summary = summaryText?.trim();
    final hasSummary = summary != null && summary.isNotEmpty;
    final existingId = host.associationQuickTaskId;
    if (existingId != null) {
      var touched = false;
      if (hasSummary && (newEntityEligible || associationWorkDone)) {
        final appended = await taskService.appendToQuickAddDescription(
          existingId,
          summary,
        );
        if (appended) touched = true;
      }
      final merged = await taskService.mergeQuickAddEntitySnapshot(
        taskId: existingId,
        callerId: callerId,
        departmentId: departmentId,
        equipmentId: equipmentId,
        phoneText: phoneText,
        userText: userText,
        equipmentText: equipmentText,
        departmentText: departmentText,
      );
      if (merged) touched = true;
      if (touched) invalidateTaskListProviders(ref);
      return;
    }

    if (!newEntityEligible) return;

    final id = await _insertQuickAddTask(
      callerName: callerName,
      summaryText: summaryText,
      callerId: callerId,
      departmentId: departmentId,
      equipmentId: equipmentId,
      phoneText: phoneText,
      userText: userText,
      equipmentText: equipmentText,
      departmentText: departmentText,
    );
    host.associationQuickTaskId = id;
    invalidateTaskListProviders(ref);
  }

  /// Οι υποδείξεις κανόνων για τα πεδία της γρήγορης καταχώρησης.
  ///
  /// Αν οι κανόνες δεν φορτώνονται (π.χ. βάση σε μετάβαση), η καταχώρηση
  /// προχωρά κανονικά χωρίς υποδείξεις — ποτέ δεν εμποδίζεται.
  Future<List<String>> _quickAddValidationHints({
    String? callerName,
    String? phones,
    String? departmentName,
    String? equipmentCode,
  }) async {
    try {
      final service = await ref.read(catalogValidationServiceProvider.future);
      return service.quickAddHints(
        callerName: callerName,
        phones: phones,
        departmentName: departmentName,
        equipmentCode: equipmentCode,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<int> _insertQuickAddTask({
    required String? callerName,
    required String? summaryText,
    required int? callerId,
    required int? departmentId,
    required int? equipmentId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
  }) async {
    final cleanSummary = summaryText?.trim();
    final caller = callerName?.trim();
    final descriptionCore = cleanSummary?.isNotEmpty == true
        ? cleanSummary!
        : (caller?.isNotEmpty == true
              ? 'Ενημερώθηκε οντότητα καλούντα'
              : 'Quick add');
    // Οι κανόνες επικύρωσης δεν διακόπτουν τη γρήγορη καταχώρηση — οι
    // υποδείξεις τους ταξιδεύουν στην εκκρεμότητα, για έλεγχο με την ησυχία
    // του χρήστη. Καθαρή καταχώρηση δεν προσθέτει καμία γραμμή.
    final hints = await _quickAddValidationHints(
      callerName: userText ?? caller,
      phones: phoneText,
      departmentName: departmentText,
      equipmentCode: equipmentText,
    );
    final hintBlock = hints.isEmpty
        ? ''
        : '\n${Task.validationHintHeader}\n'
              '${hints.map((h) => '${Task.validationHintPrefix}$h').join('\n')}';
    final quickDescription = '${Task.quickAddTag} $descriptionCore$hintBlock';
    return ref
        .read(taskServiceProvider)
        .createFromCall(
          callId: null,
          callerName: caller,
          description: quickDescription,
          callDate: DateTime.now(),
          callerId: callerId,
          equipmentId: equipmentId,
          departmentId: departmentId,
          phoneId: null,
          phoneText: phoneText?.isEmpty == true ? null : phoneText,
          userText: userText?.isEmpty == true ? null : userText,
          equipmentText: equipmentText?.isEmpty == true ? null : equipmentText,
          departmentText: departmentText?.isEmpty == true
              ? null
              : departmentText,
          priority: SmartEntitySelectorNotifier.criticalTaskPriority,
          categoryName: Task.quickAddCategoryEl,
        );
  }
}

/// Η απάντηση στην ερώτηση «Εξοπλισμός άλλου τμήματος — να μεταφερθεί;».
typedef _EquipmentMove = ({
  bool cancelled,
  int? equipmentId,
  List<UserModel> ownersToRelease,
});

/// Ό,τι γράφει η φόρμα για τον νέο καλούντα, και τι υπήρχε ήδη στον
/// κατάλογο πριν από το «+».
typedef _NewCallerInput = ({
  String name,
  ({String firstName, String lastName}) parsed,
  String? phone,
  String equipmentCode,
  String departmentText,
  bool departmentExisted,
  bool phoneExisted,
  bool equipmentExisted,
  LookupService? lookup,
  int? departmentId,
  bool createsDepartment,
});

/// Οι απαντήσεις στις ερωτήσεις του «+» για νέο καλούντα.
typedef _NewCallerAnswers = ({
  _EquipmentMove equipmentMove,
  List<String> phones,
  String? phoneForAssociation,
  UserPhoneConflictBatchResult? phoneResolutions,
});

/// Τι έχει να γίνει για τον υπάρχοντα καλούντα.
typedef _ExistingCallerWork = ({
  int userId,
  String? phone,
  String? eqCode,
  bool hadEqWork,
  bool updatesPrimaryDepartment,
  bool newDepartmentRow,
  bool newEntityEligible,
  String? departmentChangeLine,
  String callerName,
});

/// Οι απαντήσεις στις ερωτήσεις του «+» για υπάρχοντα καλούντα.
typedef _ExistingCallerAnswers = ({
  _EquipmentMove equipmentMove,
  _AssetsOnDepartmentChange? stayingBehind,
  String? phoneToLink,
  UserPhoneConflictBatchResult? phoneResolutions,
  int? phoneDepartmentId,
});

/// Το τμήμα της φόρμας μετά τις εγγραφές, και αν έγινε κύριο του καλούντα.
typedef _ExistingCallerWrite = ({int? departmentId, bool changed});

/// Τι απογίνονται όσα κουβαλά ο καλών όταν αλλάζει τμήμα: τι μένει πίσω, και
/// ποια κοινά τηλέφωνα και μηχανήματα τον ακολουθούν φεύγοντας από τους
/// άλλους κατόχους.
typedef _AssetsOnDepartmentChange = ({
  Set<String> phones,
  Set<String> phonesLeftWithCoOwners,
  Set<String> phonesTakenFromCoOwners,
  List<EquipmentModel> equipment,
  List<EquipmentModel> takenFromCoOwners,
});

/// «Ελένη Πλακογιάννη (Βιοϊατρική)» — το τμήμα είναι ο λόγος της ερώτησης.
String _ownerLabel(UserModel owner, LookupService lookup) {
  final name = (owner.name ?? '').trim();
  final department =
      (owner.departmentName ??
              lookup.departmentIdToName[owner.departmentId] ??
              '')
          .trim();
  return department.isEmpty ? name : '$name ($department)';
}
