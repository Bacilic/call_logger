import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/directory/department_change_assets.dart';
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

  /// Εμφανίζει τον υπάρχοντα διάλογο σύγκρουσης αν χρειάζεται· επιστρέφει το
  /// τηλέφωνο προς σύνδεση ή null αν ο χρήστης ακύρωσε / δεν υπάρχει context.
  Future<String?> _confirmAndPreparePhoneAssociation({
    required BuildContext? context,
    required PhoneRepository phonesRepo,
    required String phone,
    required int? targetDepartmentId,
    required int? editingUserId,
    required String userDisplayName,
    required String targetDepartmentName,
  }) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return null;

    final conflicts = PhoneDepartmentPolicy.findConflictsForUserAssignment(
      phones: [trimmed],
      targetDepartmentId: targetDepartmentId,
      editingUserId: editingUserId,
    );
    if (conflicts.isEmpty) return trimmed;

    if (context == null || !context.mounted) {
      return null;
    }

    final result = await showUserPhoneDepartmentConflictDialog(
      context,
      conflicts: conflicts,
      userDisplayName: userDisplayName,
      targetDepartmentName: targetDepartmentName,
      targetDepartmentId: targetDepartmentId,
    );
    if (result == null) return null;

    // «Μένει στο τμήμα του» σημαίνει ότι δεν συνδέεται με τον καλούντα — αλλιώς
    // η επιλογή θα ζητιόταν και θα αγνοούνταν.
    if (result.detaches(trimmed)) return null;

    await PhoneDepartmentPolicy.applyUserPhoneConflictResolutions(
      phones: phonesRepo,
      resolutions: result,
      targetDepartmentId: targetDepartmentId,
    );
    ref.invalidate(lookupServiceProvider);
    await ref.read(lookupServiceProvider.future);
    return trimmed;
  }

  /// Ρωτά τι απογίνονται τηλέφωνα και εξοπλισμός όταν ο καλών αλλάζει τμήμα.
  ///
  /// Επιστρέφει τι μένει πίσω· `null` σημαίνει «ο χρήστης ακύρωσε» και τότε το
  /// τμήμα δεν αλλάζει καθόλου.
  ///
  /// Χωρίς παλιό τμήμα δεν υπάρχει μεταφορά — η πρώτη ανάθεση περνά αθόρυβα,
  /// όπως και πριν.
  Future<({List<String> phones, List<EquipmentModel> equipment})?>
  _confirmAssetsOnDepartmentChange({
    required BuildContext? context,
    required UserModel caller,

    /// Πού πάει ο υπάλληλος — το Είδος του προορισμού κρίνει αν ο εξοπλισμός
    /// επιτρέπεται να τον ακολουθήσει.
    required int? targetDepartmentId,
  }) async {
    final userId = caller.id;
    final oldDepartmentId = caller.departmentId;
    if (userId == null || oldDepartmentId == null) {
      return (phones: const <String>[], equipment: const <EquipmentModel>[]);
    }

    final lookup = ref.read(lookupServiceProvider).value?.service;
    final carriedPhones = caller.phones
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final carriedEquipment =
        lookup?.findEquipmentsForUser(userId) ?? const <EquipmentModel>[];
    if (carriedPhones.isEmpty && carriedEquipment.isEmpty) {
      return (phones: const <String>[], equipment: const <EquipmentModel>[]);
    }
    // Χωρίς οθόνη δεν υπάρχει ποιον να ρωτήσουμε. Συνειδητή επιλογή: η αλλαγή
    // τμήματος προχωρά με την προεπιλογή (όλα ακολουθούν) αντί να χαθεί η
    // πρόθεση του χρήστη επειδή έκλεισε η κλήση στο ενδιάμεσο.
    if (context == null || !context.mounted) {
      return (phones: const <String>[], equipment: const <EquipmentModel>[]);
    }

    // Άγνωστο ή νεοσύστατο τμήμα διαβάζεται ως νοσοκομείο — η ίδια παραδοχή
    // με τη μαζική μεταφορά και τη φόρμα υπαλλήλου.
    final targetKind =
        (targetDepartmentId == null
            ? null
            : lookup?.departmentKindById(targetDepartmentId)) ??
        DepartmentKind.hospital;

    final userName = bulkUserDisplayName(caller);
    final phonesStaying = <String>[];
    if (carriedPhones.isNotEmpty) {
      // Τα εσωτερικά του κέντρου μας δεν ακολουθούν έξω από το νοσοκομείο.
      final split = splitPhonesForDepartmentChange(
        phones: carriedPhones,
        targetKind: targetKind,
        rules:
            ref.read(catalogValidationRulesProvider).value ??
            const CatalogValidationRules(),
      );
      final fate = await askPhoneFateOnDepartmentChange(
        context,
        split: split,
        targetKind: targetKind,
        userDisplayName: userName,
        sourceDepartmentName: lookup?.departments
            .where((d) => d.id == oldDepartmentId)
            .firstOrNull
            ?.name
            .trim(),
      );
      if (fate == null) return null;
      // Ό,τι δεν μπορεί να ακολουθήσει μένει πίσω ό,τι κι αν απαντήθηκε.
      phonesStaying.addAll(split.forcedToStay);
      if (fate == BulkTransferAssetFate.stayInOldDepartment) {
        for (final phone in split.negotiable) {
          final others = [
            for (final other in lookup?.findUsersByPhone(phone) ?? const [])
              if (other.id != null && other.id != userId && !other.isDeleted)
                bulkUserDisplayName(other),
          ];
          final dept = lookup?.getDepartmentByPhone(phone);
          final deptId = dept?.id;
          final deptName = dept?.name.trim() ?? '';
          final decision = judgePhoneStayBehind(
            phone: phone,
            userName: userName,
            oldDepartmentId: oldDepartmentId,
            otherOwnerNames: others,
            sharedDepartment: (deptId != null && deptName.isNotEmpty)
                ? (id: deptId, name: deptName)
                : null,
          );
          if (decision.releases) phonesStaying.add(phone);
        }
      }
    }

    final equipmentStaying = <EquipmentModel>[];
    // Ανάμεσα στις δύο ερωτήσεις μεσολάβησε διάλογος: η οθόνη μπορεί να έχει
    // φύγει, οπότε ο φρουρός ξαναμπαίνει πριν από τη δεύτερη.
    if (carriedEquipment.isNotEmpty && context.mounted) {
      final fate = await askEquipmentFateOnDepartmentChange(
        context,
        targetKind: targetKind,
        userDisplayName: userName,
      );
      if (fate == null) return null;
      if (fate == BulkTransferAssetFate.stayInOldDepartment) {
        for (final item in carriedEquipment) {
          final code = (item.code ?? '').trim();
          final itemId = item.id;
          if (code.isEmpty || itemId == null) continue;
          final others = [
            for (final other
                in lookup?.findUsersForEquipment(itemId) ?? const [])
              if (other.id != null && other.id != userId && !other.isDeleted)
                bulkUserDisplayName(other),
          ];
          final decision = judgeEquipmentStayBehind(
            code: code,
            userName: userName,
            oldDepartmentId: oldDepartmentId,
            equipmentDepartmentId: item.departmentId,
            otherOwnerNames: others,
          );
          if (decision.releases) equipmentStaying.add(item);
        }
      }
    }

    return (phones: phonesStaying, equipment: equipmentStaying);
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
    await applyQuickAddUndo(
      record,
      executor: db,
      users: UserRepository(db),
      phones: PhoneRepository(db),
      equipment: EquipmentRepository(db),
      departments: DepartmentRepository(db),
    );

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

    final departmentId = await _resolveOrphanDepartmentId(plan);
    if (departmentId == null) {
      return const OrphanQuickAddResult(
        requiresConfirmation: false,
        message: 'Δεν βρέθηκε/δημιουργήθηκε τμήμα.',
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
    return _finishOrphanQuickAdd(plan, departmentId);
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

  Future<String?> associateCurrentIfNeeded({
    bool updatePrimaryDepartment = false,
    BuildContext? context,
  }) async {
    final lookupForAssoc = ref.read(lookupServiceProvider).value?.service;
    if (!state.needsAssociation(lookupForAssoc)) return null;

    final msg = state.associationTooltip(lookupForAssoc);
    final dbAssoc = await DatabaseHelper.instance.database;
    final auditSince = await host.maxAuditLogId(dbAssoc);
    final departments = DepartmentRepository(dbAssoc);
    final phones = PhoneRepository(dbAssoc);
    final equipmentRepo = EquipmentRepository(dbAssoc);
    final users = UserRepository(dbAssoc);
    if (state.needsNewCallerCreation) {
      final name = NameParserUtility.stripDisplayDecorations(
        state.normalizedCallerDisplayText,
      );
      final phone = state.selectedPhone?.trim();
      // Εταιρεία δεν γίνεται κάτοχος εξοπλισμού: ο νέος καλών δημιουργείται
      // κανονικά με το τηλέφωνό του, αλλά ο κωδικός του μηχανήματος μένει
      // αναφορά της κλήσης και δεν δένεται πάνω του.
      final equipmentCode = state.departmentAcceptsEquipment(lookupForAssoc)
          ? state.equipmentText.trim()
          : '';
      final parsed = NameParserUtility.parse(name);
      final deptTextRaw = state.departmentText.trim();
      final departmentExistedBefore =
          deptTextRaw.isNotEmpty &&
          await departments.departmentNameExists(deptTextRaw);
      final phoneExistedBefore = (phone != null && phone.isNotEmpty)
          ? await phones.phoneNumberExists(phone)
          : false;
      final equipmentExistedBefore = equipmentCode.isNotEmpty
          ? await equipmentRepo.equipmentCodeExists(equipmentCode)
          : false;

      final lookup = ref.read(lookupServiceProvider).value?.service;
      var departmentId =
          state.selectedDepartmentId ??
          (state.departmentText.trim().isNotEmpty && lookup != null
              ? lookup.findDepartmentByName(state.departmentText)?.id
              : null);
      if (departmentId == null && state.departmentText.trim().isNotEmpty) {
        departmentId = await departments.getOrCreateDepartmentIdByName(
          state.departmentText.trim(),
        );
      }
      try {
        var parsedPhones = PhoneListParser.splitPhones(phone);
        String? phoneForAssociation = phone;
        if (parsedPhones.isNotEmpty) {
          final dialogContext = context;
          if (dialogContext != null && !dialogContext.mounted) {
            parsedPhones = <String>[];
            phoneForAssociation = null;
          } else {
            final prepared = await _confirmAndPreparePhoneAssociation(
              context: dialogContext,
              phonesRepo: phones,
              phone: parsedPhones.first,
              targetDepartmentId: departmentId,
              editingUserId: null,
              userDisplayName: name,
              targetDepartmentName: departmentId != null
                  ? (lookup?.departmentIdToName[departmentId] ?? deptTextRaw)
                  : deptTextRaw,
            );
            if (prepared == null) {
              parsedPhones = <String>[];
              phoneForAssociation = null;
            } else {
              parsedPhones = PhoneListParser.splitPhones(prepared);
              phoneForAssociation = prepared;
            }
          }
        }
        final userId = await users.insertUser(
          firstName: parsed.firstName,
          lastName: parsed.lastName,
          phones: parsedPhones.isEmpty ? null : parsedPhones,
          departmentId: departmentId,
        );

        await users.updateAssociationsIfNeeded(
          userId,
          phoneForAssociation,
          equipmentCode.isNotEmpty ? equipmentCode : null,
        );

        // Η προσφορά αναίρεσης της στιγμής: μόνο ό,τι δεν υπήρχε πριν.
        host.lastQuickAddUndo = QuickAddUndoRecord(
          createdUserId: userId,
          createdUserName: name,
          createdDepartmentId: departmentExistedBefore ? null : departmentId,
          createdDepartmentName: departmentExistedBefore ? null : deptTextRaw,
          createdPhone: (!phoneExistedBefore && parsedPhones.isNotEmpty)
              ? parsedPhones.first
              : null,
          createdEquipmentCode:
              (!equipmentExistedBefore && equipmentCode.isNotEmpty)
              ? equipmentCode
              : null,
        );

        final s = state;
        final lookupNow = ref.read(lookupServiceProvider).value?.service;
        final departmentIdNow =
            s.selectedDepartmentId ??
            departmentId ??
            (s.departmentText.trim().isNotEmpty && lookupNow != null
                ? lookupNow.findDepartmentByName(s.departmentText)?.id
                : null);
        final equipTrim = s.equipmentText.trim();
        // Όνομα τμήματος: από το lookup αν το ξέρει ήδη, αλλιώς από το πεδίο —
        // το νεοδημιουργημένο τμήμα δεν έχει προλάβει να μπει στο cache.
        final departmentNameNow = departmentIdNow == null
            ? null
            : (lookupNow?.departmentIdToName[departmentIdNow] ??
                  (s.departmentText.trim().isNotEmpty
                      ? s.departmentText.trim()
                      : ''));
        state = state.copyWith(
          selectedCaller: UserModel(
            id: userId,
            firstName: parsed.firstName,
            lastName: parsed.lastName,
            phones: parsedPhones,
            departmentId: departmentIdNow,
            departmentName: departmentNameNow,
          ),
          selectedDepartmentId: departmentIdNow,
          selectedEquipment: equipTrim.isNotEmpty
              ? EquipmentModel(code: equipTrim)
              : s.selectedEquipment,
          callerDisplayText: s.callerDisplayText.trim().isNotEmpty
              ? s.callerDisplayText
              : name,
          departmentText: s.departmentText,
        );
        host.callerAwaitingPhoneAssociation = parsedPhones.isEmpty;
        await refreshDirectoryCaches(
          ref,
          users: true,
          equipment: equipmentCode.isNotEmpty,
          departments: deptTextRaw.isNotEmpty,
        );
        if (!ref.mounted) {
          return 'Σφάλμα αποθήκευσης: το container δεν είναι ενεργό.';
        }
        final refreshedLookup = (await ref.read(
          lookupServiceProvider.future,
        )).service;
        final matchedNewCallerEquipment = equipTrim.isEmpty
            ? const <EquipmentModel>[]
            : refreshedLookup.findEquipmentsByCode(equipTrim);
        final resolvedEquipmentId = matchedNewCallerEquipment.isEmpty
            ? null
            : matchedNewCallerEquipment.first.id;
        final resolvedDepartmentId =
            departmentIdNow ??
            departmentId ??
            (s.departmentText.trim().isNotEmpty
                ? refreshedLookup.findDepartmentByName(s.departmentText)?.id
                : null);
        // Πλήρες EquipmentModel με id — αλλιώς το hasEquipmentAssociation μείνει false
        // και το submit κλήσης ξανατρέχει συσχέτιση + δεύτερη γρήγορη εκκρεμότητα.
        if (matchedNewCallerEquipment.isNotEmpty) {
          state = state.copyWith(
            selectedEquipment: matchedNewCallerEquipment.first,
          );
        }
        await _syncAssociationQuickTask(
          newEntityEligible: true,
          associationWorkDone: true,
          summaryText: msg,
          callerName:
              state.selectedCaller?.name ?? state.callerDisplayText.trim(),
          callerId: userId,
          departmentId: resolvedDepartmentId,
          equipmentId: resolvedEquipmentId,
          phoneText: s.selectedPhone?.trim(),
          userText: s.callerDisplayText.trim().isEmpty
              ? null
              : s.callerDisplayText.trim(),
          equipmentText: equipTrim.isEmpty ? null : equipTrim,
          departmentText: s.departmentText.trim().isEmpty
              ? null
              : s.departmentText.trim(),
        );
        final createdDeptNow =
            deptTextRaw.isNotEmpty && !departmentExistedBefore;
        final lines = <String>[];
        final fullName = (state.selectedCaller?.name ?? state.callerDisplayText)
            .trim();
        final deptSuffix = deptTextRaw.isNotEmpty
            ? ' στο τμήμα: $deptTextRaw'
            : '';
        lines.add('Δημιουργήθηκε νέος χρήστης $fullName$deptSuffix');
        if (createdDeptNow) {
          lines.add('Δημιουργήθηκε νέο τμήμα: $deptTextRaw');
        }
        if (phone != null && phone.isNotEmpty) {
          lines.add(
            phoneExistedBefore
                ? 'Συσχετίστηκε τηλέφωνο: $phone'
                : 'Δημιουργήθηκε νέο τηλέφωνο: $phone',
          );
        }
        if (equipmentCode.isNotEmpty) {
          lines.add(
            equipmentExistedBefore
                ? 'Συσχετίστηκε εξοπλισμός: $equipmentCode'
                : 'Δημιουργήθηκε νέος εξοπλισμός: $equipmentCode',
          );
        }
        // Αν υπάρχει επιπλέον "τεχνικό" tooltip μήνυμα, το αφήνουμε στο τέλος ως περίληψη.
        final summary = msg?.trim();
        if (summary != null && summary.isNotEmpty) {
          lines.add(summary);
        }
        await host.trackDerivativeAuditsSince(auditSince);
        return lines.join('\n');
      } catch (e) {
        await refreshDirectoryCaches(
          ref,
          users: true,
          equipment: true,
          departments: true,
        );
        return 'Σφάλμα αποθήκευσης: ${humanizeUserFacingError(e)}';
      }
    }

    if (state.selectedCaller?.id == null) return null;
    final userId = state.selectedCaller!.id!;
    final phone = state.hasPhoneAssociation
        ? null
        : state.selectedPhone?.trim();
    final eqCode = state.hasEquipmentAssociation(lookupForAssoc)
        ? null
        : state.equipmentText.trim();
    final hadPhoneWork = phone != null && phone.isNotEmpty;
    final hadEqWork = eqCode != null && eqCode.isNotEmpty;
    final newPhoneRow = hadPhoneWork && !await phones.phoneNumberExists(phone);
    final newEquipmentRow =
        hadEqWork && !await equipmentRepo.equipmentCodeExists(eqCode);
    final deptTrimAssoc = state.departmentText.trim();
    final callerHadNoPrimaryDept =
        state.selectedCaller?.departmentId == null &&
        (state.selectedCaller?.departmentName ?? '').trim().isEmpty;
    // Όταν ο καλών δεν είχε κύριο τμήμα, η πρώτη ανάθεση τμήματος στο πορτοκαλί
    // βήμα δεν μπλοκάρεται από dialog «Όχι» (δεν υπάρχει παλιό τμήμα προς διατήρηση).
    final effectiveUpdatePrimaryDepartment =
        updatePrimaryDepartment ||
        (state.hasPendingDepartmentChange &&
            callerHadNoPrimaryDept &&
            deptTrimAssoc.isNotEmpty);
    final willCreateDept =
        effectiveUpdatePrimaryDepartment && deptTrimAssoc.isNotEmpty;
    final newDepartmentRow =
        willCreateDept &&
        !await departments.departmentNameExists(deptTrimAssoc);
    final newEntityEligible =
        newPhoneRow || newEquipmentRow || newDepartmentRow;
    try {
      String? phoneToLink = phone;
      if (phoneToLink != null && phoneToLink.isNotEmpty) {
        final caller = state.selectedCaller;
        final targetDeptId =
            caller?.departmentId ??
            state.selectedDepartmentId ??
            (state.departmentText.trim().isNotEmpty && lookupForAssoc != null
                ? lookupForAssoc.findDepartmentByName(state.departmentText)?.id
                : null);
        final targetDeptName = targetDeptId != null
            ? (lookupForAssoc?.departmentIdToName[targetDeptId] ??
                  state.departmentText.trim())
            : state.departmentText.trim();
        final dialogContext = context;
        if (dialogContext != null && !dialogContext.mounted) {
          phoneToLink = null;
        } else {
          phoneToLink = await _confirmAndPreparePhoneAssociation(
            context: dialogContext,
            phonesRepo: phones,
            phone: phoneToLink,
            targetDepartmentId: targetDeptId,
            editingUserId: userId,
            userDisplayName: caller?.name ?? state.callerDisplayText.trim(),
            targetDepartmentName: targetDeptName,
          );
        }
      }
      await users.updateAssociationsIfNeeded(
        userId,
        phoneToLink,
        eqCode?.isNotEmpty == true ? eqCode : null,
      );

      final lookup = ref.read(lookupServiceProvider).value?.service;
      var selectedDepartmentId =
          state.selectedDepartmentId ??
          (state.departmentText.trim().isNotEmpty && lookup != null
              ? lookup.findDepartmentByName(state.departmentText)?.id
              : null);
      var updatedDepartmentId = state.selectedCaller?.departmentId;
      var primaryDepartmentChanged = false;
      if (effectiveUpdatePrimaryDepartment &&
          state.departmentText.trim().isNotEmpty &&
          state.selectedCaller?.id != null) {
        // Αν το τμήμα δεν υπάρχει ακόμα στη βάση, το δημιουργούμε ώστε να πάρουμε id.
        selectedDepartmentId ??= await departments
            .getOrCreateDepartmentIdByName(state.departmentText.trim());
      }

      if (effectiveUpdatePrimaryDepartment &&
          selectedDepartmentId != null &&
          selectedDepartmentId != state.selectedCaller?.departmentId &&
          state.selectedCaller?.id != null) {
        // Ο υπάλληλος μετακομίζει: ρωτιέται τι απογίνονται όσα κουβαλά, με
        // τους ΙΔΙΟΥΣ οδηγούς που δείχνουν η φόρμα και η μαζική μεταφορά. Η
        // γρήγορη προσθήκη δεν είναι εξαίρεση — μια σιωπηλή μεταφορά εδώ θα
        // ήταν τρύπα στα δεδομένα.
        //
        // Όταν ο καλών ΔΕΝ είχε τμήμα, δεν υπάρχει μεταφορά αλλά πρώτη
        // ανάθεση: τίποτα δεν μπορεί να «μείνει πίσω» και δεν ρωτιέται τίποτα.
        final assetDialogContext = context;
        final decision =
            (assetDialogContext != null && !assetDialogContext.mounted)
            ? null
            : await _confirmAssetsOnDepartmentChange(
                context: assetDialogContext,
                caller: state.selectedCaller!,
                targetDepartmentId: selectedDepartmentId,
              );
        if (decision == null) {
          // Ακύρωση: το τμήμα μένει ως έχει. Η υπόλοιπη συσχέτιση που έγινε
          // πιο πάνω (τηλέφωνο, εξοπλισμός) δεν αναιρείται.
          primaryDepartmentChanged = false;
        } else {
          final oldDepartmentId = state.selectedCaller!.departmentId;
          final updatedMap = Map<String, dynamic>.from(
            state.selectedCaller!.toMap(),
          );
          updatedMap['department_id'] = selectedDepartmentId;
          await users.updateUser(
            state.selectedCaller!.id!,
            updatedMap,
            expected: null,
          );
          await applyAssetsStayingBehind(
            db: dbAssoc,
            userId: state.selectedCaller!.id!,
            oldDepartmentId: oldDepartmentId,
            phones: decision.phones,
            equipment: decision.equipment,
            currentPhones: state.selectedCaller!.phones,
          );
          updatedDepartmentId = selectedDepartmentId;
          primaryDepartmentChanged = true;
        }
      }

      final s = state;
      final phoneNow = phoneToLink;
      final currentPhones = List<String>.from(
        s.selectedCaller?.phones ?? const [],
      );
      List<String> updatedPhones = currentPhones;
      if (phoneNow != null && phoneNow.isNotEmpty) {
        final joined = PhoneListParser.joinPhones(currentPhones);
        if (!PhoneListParser.containsPhone(joined, phoneNow)) {
          updatedPhones = [...currentPhones, phoneNow];
        }
      }
      state = state.copyWith(
        selectedCaller: UserModel(
          id: s.selectedCaller?.id,
          firstName: s.selectedCaller?.firstName,
          lastName: s.selectedCaller?.lastName,
          phones: updatedPhones,
          departmentId: updatedDepartmentId,
          // Αλλαγή κύριου τμήματος: νέο όνομα από lookup ή από το πεδίο
          // (το φρεσκοδημιουργημένο τμήμα λείπει ακόμα από το cache).
          departmentName: !primaryDepartmentChanged
              ? s.selectedCaller?.departmentName
              : (updatedDepartmentId == null
                    ? null
                    : (lookup?.departmentIdToName[updatedDepartmentId] ??
                          (s.departmentText.trim().isNotEmpty
                              ? s.departmentText.trim()
                              : ''))),
          notes: s.selectedCaller?.notes,
        ),
        selectedDepartmentId: primaryDepartmentChanged
            ? updatedDepartmentId
            : s.selectedDepartmentId,
        selectedEquipment: eqCode?.isNotEmpty == true
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
        equipment: hadEqWork,
        departments: primaryDepartmentChanged || newDepartmentRow,
      );
      if (!ref.mounted) {
        return 'Σφάλμα αποθήκευσης: το container δεν είναι ενεργό.';
      }
      final refreshedLookup = (await ref.read(
        lookupServiceProvider.future,
      )).service;
      final matchedEquipment = eqCode?.isNotEmpty == true
          ? refreshedLookup.findEquipmentsByCode(eqCode!)
          : const <EquipmentModel>[];
      final resolvedEquipmentId = matchedEquipment.isNotEmpty
          ? matchedEquipment.first.id
          : s.selectedEquipment?.id;
      final resolvedDepartmentId =
          selectedDepartmentId ??
          (s.departmentText.trim().isNotEmpty
              ? refreshedLookup.findDepartmentByName(s.departmentText)?.id
              : null);
      if (matchedEquipment.isNotEmpty) {
        state = state.copyWith(selectedEquipment: matchedEquipment.first);
      }
      await _syncAssociationQuickTask(
        newEntityEligible: newEntityEligible,
        associationWorkDone:
            hadPhoneWork || hadEqWork || primaryDepartmentChanged,
        summaryText: msg,
        callerName: s.selectedCaller?.name ?? s.callerDisplayText.trim(),
        callerId: s.selectedCaller?.id,
        departmentId: resolvedDepartmentId,
        equipmentId: resolvedEquipmentId,
        phoneText: s.selectedPhone?.trim(),
        userText: s.callerDisplayText.trim().isEmpty
            ? null
            : s.callerDisplayText.trim(),
        equipmentText: s.equipmentText.trim().isEmpty
            ? null
            : s.equipmentText.trim(),
        departmentText: s.departmentText.trim().isEmpty
            ? null
            : s.departmentText.trim(),
      );
      await host.trackDerivativeAuditsSince(auditSince);
      return (hadPhoneWork || hadEqWork || primaryDepartmentChanged)
          ? (msg ?? 'Προστέθηκε.')
          : null;
    } catch (e) {
      return 'Σφάλμα αποθήκευσης: ${humanizeUserFacingError(e)}';
    }
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
