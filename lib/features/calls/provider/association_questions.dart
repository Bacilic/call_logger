import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/directory/equipment_department_policy.dart';
import '../../../core/directory/phone_department_policy.dart';
import '../../../core/services/lookup_service.dart';
import '../../directory/models/catalog_validation_rules.dart';
import '../../directory/models/department_kind.dart';
import '../../directory/services/phone_transfer_split.dart';
import '../../directory/screens/widgets/asset_fate_on_department_change.dart';
import '../../directory/screens/widgets/user_phone_department_conflict_dialog.dart';
import '../../directory/services/bulk_user_actions.dart';
import '../../directory/providers/catalog_validation_provider.dart';
import '../models/equipment_model.dart';
import '../models/user_model.dart';
import '../screens/widgets/equipment_owner_move_dialog.dart';
import 'lookup_provider.dart';

/// Η απάντηση στην ερώτηση σύγκρουσης τηλεφώνου του «+».
///
/// Δύο διαφορετικές απαντήσεις «χωρίς τηλέφωνο», που δεν επιτρέπεται να
/// μπερδευτούν:
/// - `phone == null` — ο χρήστης διάλεξε ρητά να μείνει το τηλέφωνο εκεί που
///   είναι· η υπόλοιπη καταχώρηση συνεχίζει.
/// - `cancelled` — «Ακύρωση» ή καμία οθόνη για να ρωτηθεί· ο καλών δεν
///   γράφει **τίποτα**.
typedef PhoneAssociationAnswer = ({
  bool cancelled,
  String? phone,
  UserPhoneConflictBatchResult? resolutions,
});

/// Η απάντηση στην ερώτηση «Εξοπλισμός άλλου τμήματος — να μεταφερθεί;».
typedef EquipmentMoveAnswer = ({
  bool cancelled,
  int? equipmentId,
  List<UserModel> ownersToRelease,
});

/// Τι απογίνονται όσα κουβαλά ο καλών όταν αλλάζει τμήμα: τι μένει πίσω, και
/// ποια κοινά τηλέφωνα και μηχανήματα τον ακολουθούν φεύγοντας από τους
/// άλλους κατόχους.
typedef AssetsOnDepartmentChange = ({
  Set<String> phones,
  Set<String> phonesLeftWithCoOwners,
  Set<String> phonesTakenFromCoOwners,
  List<EquipmentModel> equipment,
  List<EquipmentModel> takenFromCoOwners,
});

/// Οι ερωτήσεις του «+» — **καμία εγγραφή**.
///
/// Κάθε ερώτηση επιστρέφει μόνο την απάντηση· την εφαρμόζουν οι ροές του
/// καλούντα, αφού έχουν απαντηθεί όλες. Έτσι η «Ακύρωση» σε οποιαδήποτε
/// αφήνει τη βάση ανέγγιχτη.
class AssociationQuestions {
  AssociationQuestions(this.ref);

  final Ref ref;

  /// Ρωτά για τη σύγκρουση τηλεφώνου, αν υπάρχει — **χωρίς να γράψει τίποτα**.
  /// Η απάντηση εφαρμόζεται από τον καλούντα, αφού έχουν γίνει όλες οι
  /// ερωτήσεις του «+».
  ///
  /// [targetIsNewDepartment]: το τμήμα του υπαλλήλου θα δημιουργηθεί μετά την
  /// ερώτηση — η μεταφορά του τηλεφώνου εκεί προσφέρεται κανονικά.
  Future<PhoneAssociationAnswer> askPhoneAssociation({
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
  /// κάτοχοι που θα αφαιρεθούν μετά τη σύνδεση με τον νέο κάτοχο.
  ///
  /// [newOwnerId] είναι `null` για νέο καλούντα· [targetDepartmentId] `null`
  /// για νέο ή κενό τμήμα (τότε κάθε κάτοχος με τμήμα είναι ξένος).
  Future<EquipmentMoveAnswer> askEquipmentMove({
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

  /// Ρωτά τι απογίνονται τηλέφωνα και εξοπλισμός όταν ο καλών αλλάζει τμήμα.
  ///
  /// Επιστρέφει τι μένει πίσω, και ποια κοινά μηχανήματα ακολουθούν
  /// παίρνοντάς τα από τους υπόλοιπους κατόχους· `null` σημαίνει «ο χρήστης
  /// ακύρωσε» και τότε το τμήμα δεν αλλάζει καθόλου.
  ///
  /// Χωρίς παλιό τμήμα δεν υπάρχει μεταφορά — η πρώτη ανάθεση περνά αθόρυβα,
  /// όπως και πριν.
  Future<AssetsOnDepartmentChange?> confirmAssetsOnDepartmentChange({
    required BuildContext? context,
    required UserModel caller,

    /// Πού πάει ο υπάλληλος — το Είδος του προορισμού κρίνει αν ο εξοπλισμός
    /// επιτρέπεται να τον ακολουθήσει.
    required int? targetDepartmentId,

    /// Το όνομα του προορισμού όταν ο κατάλογος δεν τον ξέρει ακόμη: το
    /// κείμενο του πεδίου τμήματος της φόρμας.
    required String fallbackTargetDepartmentName,
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
        fallbackTargetDepartmentName;

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
}

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
