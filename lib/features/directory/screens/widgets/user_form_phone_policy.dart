import '../../../../core/directory/phone_department_policy.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/phone_list_parser.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import 'shared_asset_disconnect_dialog.dart';
import 'user_form_dialog.dart';
import 'user_phone_department_conflict_dialog.dart';

/// Πολιτική τηλεφώνων της φόρμας υπαλλήλου: συγκρούσεις τμήματος και
/// αποσύνδεση αποκλειστικών αριθμών που αφαιρέθηκαν.
///
/// Συνεργάτης του [UserFormDialogState] (Σύνθεση).
class UserFormPhonePolicy {
  UserFormPhonePolicy(this.host);

  final UserFormDialogState host;

  List<String> _removedPhonesFromField() {
    final before = PhoneListParser.splitPhones(host.snapPhone);
    final after = PhoneListParser.splitPhones(
      host.phoneController.text,
    ).toSet();
    return before.where((p) => !after.contains(p)).toList();
  }

  /// Τηλέφωνα που αφαιρούνται από το πεδίο και συνδέονται μόνο με τον τρέχοντα χρήστη.
  List<String> _exclusiveRemovedPhones() {
    final editingId = host.widget.initialUser?.id;
    if (!host.isEdit || editingId == null) return const [];

    final removed = _removedPhonesFromField();
    if (removed.isEmpty) return const [];

    final exclusive = <String>[];
    for (final phone in removed) {
      final owners = host.widget.notifier.allUsersForUi.where((u) {
        if (u.isDeleted) return false;
        return u.phones.any((p) => p.trim() == phone.trim());
      }).toList();
      if (owners.length == 1 && owners.first.id == editingId) {
        exclusive.add(phone);
      }
    }
    return exclusive;
  }

  ({int? id, String? name}) resolveSourceDepartmentForDisconnect() {
    final typed = host.departmentController.text.trim();
    if (typed.isEmpty) return (id: null, name: null);

    final key = SearchTextNormalizer.normalizeForSearch(typed);
    if (key.isEmpty) return (id: null, name: null);

    for (final d in LookupService.instance.departments) {
      if (d.isDeleted) continue;
      if (SearchTextNormalizer.normalizeForSearch(d.name) == key) {
        return (id: d.id, name: d.name.trim());
      }
    }
    return (id: null, name: null);
  }

  List<String> _phonesToValidateForPolicy() {
    final current = PhoneListParser.splitPhones(host.phoneController.text);
    if (!host.isEdit || host.widget.isClone) return current;
    final deptChanged =
        SearchTextNormalizer.normalizeForSearch(
          host.departmentController.text,
        ) !=
        host.snapDepartmentNorm;
    if (deptChanged) return current;
    return PhoneDepartmentPolicy.addedPhones(
      beforePhones: PhoneListParser.splitPhones(host.snapPhone),
      afterPhones: current,
    );
  }

  Future<UserPhoneConflictBatchResult?> confirmUserPhoneAssignmentConflicts({
    required int? editingUserId,
  }) async {
    final phones = _phonesToValidateForPolicy();
    if (phones.isEmpty) return const UserPhoneConflictBatchResult();

    final target = await host.saveFlow.resolveTargetDepartmentForSave();
    final conflicts = PhoneDepartmentPolicy.findConflictsForUserAssignment(
      phones: phones,
      targetDepartmentId: target.id,
      editingUserId: editingUserId,
    );
    if (conflicts.isEmpty) return const UserPhoneConflictBatchResult();

    if (!host.mounted) return null;
    return showUserPhoneDepartmentConflictDialog(
      host.context,
      conflicts: conflicts,
      userDisplayName: host.buildUserDisplayName(),
      targetDepartmentName: target.name,
      targetDepartmentId: target.id,
    );
  }

  Future<SharedAssetDisconnectBatchResult?>
  confirmExclusiveRemovedPhonesDisconnect() async {
    final phones = _exclusiveRemovedPhones();
    if (phones.isEmpty) return const SharedAssetDisconnectBatchResult();

    final lookup = LookupService.instance;
    final source = resolveSourceDepartmentForDisconnect();
    final departments = lookup.departments
        .where((d) => !d.isDeleted && d.name.trim().isNotEmpty)
        .toList();

    if (!host.mounted) return null;
    return showSharedAssetDisconnectFlow(
      context: host.context,
      sourceDepartmentId: source.id,
      sourceDepartmentName: source.name,
      phones: phones,
      availableDepartments: departments,
      mode: SharedAssetDisconnectMode.personalPhone,
      personalPhoneUserDisplayName: host.buildUserDisplayName(),
    );
  }
}
