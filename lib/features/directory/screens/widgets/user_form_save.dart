import 'package:flutter/material.dart';

import '../../../../core/database/audit_service.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/database/phone_repository.dart';
import '../../../../core/directory/phone_department_policy.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/services/save_confirmation_summary.dart';
import '../../../../core/utils/phone_list_parser.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/widgets/audit_summary_rich_text.dart';
import '../../../../core/widgets/database_persistence_error_snackbar.dart';
import '../../../calls/models/user_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../services/shared_asset_disconnect_apply.dart';
import 'department_transfer_confirm_dialog.dart';
import 'shared_asset_disconnect_dialog.dart';
import 'similar_department_suggestion_dialog.dart';
import 'similar_users_dialog.dart';
import 'user_form_dialog.dart';
import 'user_name_change_confirm_dialog.dart';
import 'user_no_department_warning_dialog.dart';

const _kUserFormDuplicateSnack = SnackBar(
  content: Text(
    'Υπάρχει ήδη υπάλληλος με το ίδιο ονοματεπώνυμο (ισοδύναμη γραφή), το ίδιο τηλέφωνο και τους ίδιους κωδικούς εξοπλισμού. Διορθώστε τα δεδομένα.',
  ),
  backgroundColor: Colors.orange,
);

/// Ροή αποθήκευσης της φόρμας υπαλλήλου: επιβεβαιώσεις (παρόμοιοι χρήστες,
/// αλλαγή ονόματος, μεταφορά τμήματος, πολιτική τηλεφώνων) και εγγραφή.
///
/// Συνεργάτης του [UserFormDialogState] (Σύνθεση).
class UserFormSave {
  UserFormSave(this.host);

  final UserFormDialogState host;

  Future<({int? id, String name})> resolveTargetDepartmentForSave() async {
    final name = host.departmentController.text.trim();
    if (name.isEmpty) return (id: null, name: '');

    final id = await _resolveDepartmentIdForSave(
      DepartmentRepository(await DatabaseHelper.instance.database),
    );
    return (id: id, name: name);
  }

  /// Αν το πεδίο τμήματος δείχνει σε υπάρχον τμήμα (ίδιο name_key), επιστρέφει το id του·
  /// όταν αλλάζει μόνο η εμφάνιση (τόνοι/κεφαλαία), ενημερώνει και το `departments.name`.
  Future<int?> _resolveDepartmentIdForSave(DepartmentRepository dir) async {
    final typed = host.departmentController.text.trim();
    if (typed.isEmpty) return null;

    final matched = host.phonePolicy.resolveSourceDepartmentForDisconnect();
    if (matched.id != null) {
      final stored = (matched.name ?? '').trim();
      if (stored != typed) {
        await dir.updateDepartment(matched.id!, {'name': typed});
      }
      return matched.id;
    }

    return dir.getOrCreateDepartmentIdByName(typed);
  }

  Future<void> save() async {
    if (!(host.formKey.currentState?.validate() ?? false)) return;
    if (!host.dismissGuard.isDirty) return;

    final similar = host.findSimilarUsers();
    if (similar.isNotEmpty) {
      if (!host.mounted) return;
      final result = await showDialog<SimilarUsersDialogResult>(
        context: host.context,
        barrierDismissible: true,
        builder: (ctx) => SimilarUsersDialog(
          matches: similar,
          allowPickExisting: false,
          typedDisplayName: host.buildUserDisplayName(),
          typedDepartmentName: host.departmentController.text.trim(),
        ),
      );
      if (!host.mounted) return;
      if (result == null || !result.continuedAsNew) return;
    }

    var cloneAsNewEmployee = false;

    if (host.isEdit && host.nameIdentityChanged()) {
      if (!host.mounted) return;
      final nameChoice = await showUserNameChangeConfirmDialog(
        context: host.context,
        oldDisplayName: host.snapDisplayName(),
        newDisplayName: host.buildUserDisplayName(),
      );
      if (!host.mounted) return;
      if (nameChoice == null) return;
      if (nameChoice == UserNameChangeDialogChoice.newEmployee) {
        cloneAsNewEmployee = true;
      }
    }

    try {
      final initialDeptNorm = SearchTextNormalizer.normalizeForSearch(
        host.initialDepartmentText,
      );
      final currentDeptNorm = SearchTextNormalizer.normalizeForSearch(
        host.departmentController.text,
      );
      if (initialDeptNorm != currentDeptNorm) {
        var existsInOrg = currentDeptNorm.isEmpty
            ? true
            : await DepartmentRepository(
                await DatabaseHelper.instance.database,
              ).departmentNameExists(host.departmentController.text);
        if (!host.mounted) return;

        if (!existsInOrg) {
          final suggestion = await showSimilarDepartmentSuggestionIfNeeded(
            context: host.context,
            departments: LookupService.instance.departments,
            typedName: host.departmentController.text,
          );
          if (!host.mounted) return;
          if (suggestion != null) {
            if (suggestion.isCancelled) {
              host.departmentController.text = host.initialDepartmentText;
              return;
            }
            final picked = suggestion.selectedDepartment;
            if (picked != null) {
              host.departmentController.text = picked.name;
              existsInOrg = true;
            }
          }
        }

        final useAddToDepartmentMessage =
            !host.isEdit ||
            host.widget.isClone ||
            host.initialDepartmentText.trim().isEmpty;
        final result = await showDepartmentTransferConfirmDialog(
          context: host.context,
          userDisplayName: host.buildUserDisplayName(),
          oldDepartment: host.initialDepartmentText,
          newDepartment: host.departmentController.text,
          newDepartmentExistsInOrg: existsInOrg,
          useAddToDepartmentMessage: useAddToDepartmentMessage,
        );
        final effective =
            result ?? DepartmentTransferDialogResult.cancelTransfer;
        if (effective == DepartmentTransferDialogResult.cancelTransfer) {
          host.departmentController.text = host.initialDepartmentText;
          return;
        }
      }

      if (!await _confirmMissingDepartmentForNewUser(
        cloneAsNewEmployee: cloneAsNewEmployee,
      )) {
        return;
      }

      SharedAssetDisconnectBatchResult? phoneDisconnectBatch;
      if (host.isEdit && !cloneAsNewEmployee) {
        phoneDisconnectBatch = await host.phonePolicy
            .confirmExclusiveRemovedPhonesDisconnect();
        if (!host.mounted) return;
        if (phoneDisconnectBatch == null) return;
      }

      final editingUserId =
          host.isEdit && !cloneAsNewEmployee && !host.widget.isClone
          ? host.widget.initialUser?.id
          : null;
      final phoneConflictBatch = await host.phonePolicy
          .confirmUserPhoneAssignmentConflicts(editingUserId: editingUserId);
      if (!host.mounted) return;
      if (phoneConflictBatch == null) return;

      await _persistUser(
        cloneAsNewEmployee: cloneAsNewEmployee,
        phoneDisconnectBatch: phoneDisconnectBatch,
        phoneConflictBatch: phoneConflictBatch,
      );
    } on PhoneDepartmentPolicyException catch (e) {
      if (!host.mounted) return;
      ScaffoldMessenger.of(host.context).showSnackBar(
        SnackBar(
          content: Text(
            'Απορρίφθηκε η αποθήκευση: το(α) τηλέφωνο(α) '
            '${e.conflicts.map((c) => c.phone).join(', ')} '
            'συγκρούεται με τμήμα άλλου καταλόγου.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e, st) {
      if (!host.mounted) return;
      showDatabasePersistenceErrorSnackBar(host.context, e, st);
    }
  }

  /// Φρουρός νέας εγγραφής χωρίς τμήμα — ο τελευταίος έλεγχος πριν την
  /// αποθήκευση, γι' αυτό προσφέρει εκχώρηση επιτόπου αντί να στέλνει τον
  /// χρήστη να ξανακάνει όλα τα βήματα. `false` = ακύρωση αποθήκευσης.
  Future<bool> _confirmMissingDepartmentForNewUser({
    required bool cloneAsNewEmployee,
  }) async {
    final isNewRegistration =
        !host.isEdit || host.widget.isClone || cloneAsNewEmployee;
    if (!isNewRegistration) return true;
    if (host.departmentController.text.trim().isNotEmpty) return true;

    if (!host.mounted) return false;
    final choice = await showUserNoDepartmentWarningDialog(
      host.context,
      userDisplayName: host.buildUserDisplayName(),
    );
    if (!host.mounted || choice == null) return false;
    if (choice == UserNoDepartmentWarningChoice.continueWithoutDepartment) {
      return true;
    }

    final departments = LookupService.instance.departments
        .where((d) => !d.isDeleted && d.name.trim().isNotEmpty)
        .toList();
    final target = await showAssetTransferTargetPicker(
      context: host.context,
      headerLabel: 'Εκχώρηση του «${host.buildUserDisplayName()}» σε τμήμα',
      availableDepartments: departments,
    );
    if (!host.mounted || target == null) return false;

    final newName = target.newDepartmentName?.trim() ?? '';
    var pickedName = newName;
    if (pickedName.isEmpty && target.departmentId != null) {
      for (final d in departments) {
        if (d.id == target.departmentId) {
          pickedName = d.name.trim();
          break;
        }
      }
    }
    if (pickedName.isEmpty) return false;

    // Ρητή επιλογή τμήματος: η αποθήκευση συνεχίζει με αυτό, χωρίς δεύτερη
    // επιβεβαίωση μεταφοράς — και οι έλεγχοι τηλεφώνων τρέχουν μετά από εδώ,
    // ώστε να δουν το σωστό τμήμα-στόχο.
    host.departmentController.text = pickedName;
    return true;
  }

  Future<void> _persistUser({
    bool cloneAsNewEmployee = false,
    SharedAssetDisconnectBatchResult? phoneDisconnectBatch,
    UserPhoneConflictBatchResult? phoneConflictBatch,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final dir = DepartmentRepository(db);
    final departmentId = await _resolveDepartmentIdForSave(dir);

    if (phoneConflictBatch != null && !phoneConflictBatch.isEmpty) {
      await PhoneDepartmentPolicy.applyUserPhoneConflictResolutions(
        phones: PhoneRepository(db),
        resolutions: phoneConflictBatch,
        targetDepartmentId: departmentId,
      );
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    }

    final user = UserModel(
      id: (host.isEdit && !cloneAsNewEmployee)
          ? host.widget.initialUser?.id
          : null,
      lastName: host.lastNameController.text.trim(),
      firstName: host.firstNameController.text.trim(),
      phones: PhoneListParser.splitPhones(host.phoneController.text),
      departmentId: departmentId,
      location: host.locationController.text.trim().isEmpty
          ? null
          : host.locationController.text.trim(),
      notes: host.notesController.text.trim().isEmpty
          ? null
          : host.notesController.text.trim(),
    );

    if (host.isEdit && cloneAsNewEmployee) {
      final sourceId = host.widget.initialUser?.id;
      if (sourceId == null) return;
      if (await host.widget.notifier.hasDuplicateUserFresh(
        user,
        mirrorEquipmentFromUserId: sourceId,
      )) {
        if (!host.mounted) return;
        ScaffoldMessenger.of(
          host.context,
        ).showSnackBar(_kUserFormDuplicateSnack);
        return;
      }
      await host.widget.notifier.addUserCloningEquipmentFrom(user, sourceId);
      host.ref.invalidate(lookupServiceProvider);
      await host.ref.read(lookupServiceProvider.future);
      if (!host.mounted) return;
      host.widget.onSaved?.call();
      Navigator.of(host.context).pop(true);
      ScaffoldMessenger.of(host.context).showSnackBar(
        const SnackBar(
          content: Text(
            'Δημιουργήθηκε νέος υπάλληλος· αντιγράφηκαν οι συνδέσεις εξοπλισμού.',
          ),
        ),
      );
      return;
    }

    if (host.isEdit) {
      if (user.id != null &&
          await host.widget.notifier.hasDuplicateUserFresh(
            user,
            excludeId: user.id,
          )) {
        if (!host.mounted) return;
        ScaffoldMessenger.of(
          host.context,
        ).showSnackBar(_kUserFormDuplicateSnack);
        return;
      }
      await host.widget.notifier.updateUser(user);
      if (phoneDisconnectBatch != null) {
        final db = await DatabaseHelper.instance.database;
        await applyPersonalPhoneDisconnectBatch(
          db,
          phoneDisconnectBatch,
          sourceDepartmentId: departmentId,
        );
        await host.widget.notifier.loadUsers();
      }
      host.ref.invalidate(lookupServiceProvider);
      await host.ref.read(lookupServiceProvider.future);
      if (!host.mounted) return;
      final saveMessage = buildSaveConfirmationMessage(
        entityType: AuditEntityTypes.user,
        entityLabel: host.buildUserDisplayName(),
        oldMap: _userMapForSaveConfirmation(
          host.widget.initialUser!.toMap(),
          departmentDisplayName:
              host.widget.initialUser!.departmentName?.trim() ??
              host.initialDepartmentText.trim(),
        ),
        newMap: _userMapForSaveConfirmation(
          user.toMap(),
          departmentDisplayName: host.departmentController.text.trim(),
        ),
        isNew: false,
      );
      host.widget.onSaved?.call();
      Navigator.of(host.context).pop(true);
      showSaveConfirmationSnackBar(host.context, saveMessage);
      return;
    }
    if (await host.widget.notifier.hasDuplicateUserFresh(user)) {
      if (!host.mounted) return;
      ScaffoldMessenger.of(host.context).showSnackBar(_kUserFormDuplicateSnack);
      return;
    }
    await host.widget.notifier.addUser(user);
    host.ref.invalidate(lookupServiceProvider);
    await host.ref.read(lookupServiceProvider.future);
    if (!host.mounted) return;
    final saveMessage = buildSaveConfirmationMessage(
      entityType: AuditEntityTypes.user,
      entityLabel: host.buildUserDisplayName(),
      oldMap: const {},
      newMap: user.toMap(),
      isNew: true,
    );
    host.widget.onSaved?.call();
    Navigator.of(host.context).pop(true);
    showSaveConfirmationSnackBar(host.context, saveMessage);
  }

  Map<String, dynamic> _userMapForSaveConfirmation(
    Map<String, dynamic> source, {
    required String departmentDisplayName,
  }) {
    final map = Map<String, dynamic>.from(source);
    if (map.containsKey('department_id')) {
      final name = departmentDisplayName.trim();
      map['department_id'] = name.isEmpty ? null : name;
    }
    return map;
  }
}
