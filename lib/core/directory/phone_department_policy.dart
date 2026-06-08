import '../database/directory_repository.dart';
import '../services/lookup_service.dart';
import '../../features/calls/models/user_model.dart';

/// Σύγκρουση ανάθεσης τηλεφώνου σε χρήστη (cross-department / άλλοι κάτοχοι).
class PhoneDepartmentConflict {
  const PhoneDepartmentConflict({
    required this.phone,
    this.existingDepartmentId,
    this.existingDepartmentName,
    this.otherUserOwnerLabels = const [],
    required this.hasDepartmentLocationConflict,
    required this.hasOtherUserOwners,
  });

  final String phone;
  final int? existingDepartmentId;
  final String? existingDepartmentName;
  final List<String> otherUserOwnerLabels;
  final bool hasDepartmentLocationConflict;
  final bool hasOtherUserOwners;

  bool get canTransferSharedLocation =>
      hasDepartmentLocationConflict && existingDepartmentId != null;
}

/// Αποτέλεσμα επιλογών χρήστη για επίλυση συγκρούσεων.
class UserPhoneConflictBatchResult {
  const UserPhoneConflictBatchResult({
    this.phonesToTransferShared = const {},
    this.phonesToRemoveFromOtherUsers = const {},
  });

  /// phone → τμήμα προέλευσης κοινόχρηστου που αφαιρείται.
  final Map<String, int> phonesToTransferShared;
  final Set<String> phonesToRemoveFromOtherUsers;

  bool get isEmpty =>
      phonesToTransferShared.isEmpty && phonesToRemoveFromOtherUsers.isEmpty;
}

/// Εξαίρεση όταν η αποθήκευση θα δημιουργούσε cross-department χωρίς επίλυση.
class PhoneDepartmentPolicyException implements Exception {
  PhoneDepartmentPolicyException(this.conflicts);

  final List<PhoneDepartmentConflict> conflicts;

  @override
  String toString() =>
      'PhoneDepartmentPolicyException: ${conflicts.map((c) => c.phone).join(', ')}';
}

/// Κεντρική πολιτική: ένα τηλέφωνο δεν συνυπάρχει σε διαφορετικά τμήματα.
class PhoneDepartmentPolicy {
  PhoneDepartmentPolicy._();

  /// Νέοι αριθμοί στο πεδίο (μετά \ πριν).
  static List<String> addedPhones({
    required Iterable<String> beforePhones,
    required Iterable<String> afterPhones,
  }) {
    final after = afterPhones
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toSet();
    final before = beforePhones
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toSet();
    final added = after.difference(before).toList()..sort();
    return added;
  }

  static List<PhoneDepartmentConflict> findConflictsForUserAssignment({
    required Iterable<String> phones,
    required int? targetDepartmentId,
    int? editingUserId,
    LookupService? lookup,
  }) {
    final svc = lookup ?? LookupService.instance;
    final conflicts = <PhoneDepartmentConflict>[];

    for (final raw in phones) {
      final phone = raw.trim();
      if (phone.isEmpty) continue;

      final usage = svc.checkPhoneUsage(phone);
      final otherOwners = <String>[];
      if (usage.hasUserOwners) {
        for (final u in svc.findUsersByPhone(phone)) {
          if (editingUserId != null && u.id == editingUserId) continue;
          final label = _userOwnerLabel(u);
          if (label.isNotEmpty) otherOwners.add(label);
        }
      }
      otherOwners.sort();

      final hasDeptConflict =
          usage.departmentId != null &&
          (targetDepartmentId == null || usage.departmentId != targetDepartmentId);
      final hasOtherOwners = otherOwners.isNotEmpty;

      if (!hasDeptConflict && !hasOtherOwners) continue;

      conflicts.add(
        PhoneDepartmentConflict(
          phone: phone,
          existingDepartmentId: usage.departmentId,
          existingDepartmentName: usage.departmentName,
          otherUserOwnerLabels: otherOwners,
          hasDepartmentLocationConflict: hasDeptConflict,
          hasOtherUserOwners: hasOtherOwners,
        ),
      );
    }
    return conflicts;
  }

  static void assertNoUnresolvedConflicts(List<PhoneDepartmentConflict> conflicts) {
    if (conflicts.isNotEmpty) {
      throw PhoneDepartmentPolicyException(conflicts);
    }
  }

  /// Εφαρμογή επιλογών πριν/μετά την αποθήκευση χρήστη.
  static Future<void> applyUserPhoneConflictResolutions({
    required DirectoryRepository dir,
    required UserPhoneConflictBatchResult resolutions,
    required int? targetDepartmentId,
  }) async {
    for (final phone in resolutions.phonesToRemoveFromOtherUsers) {
      await dir.removePhoneFromAllUsers(phone);
    }
    for (final entry in resolutions.phonesToTransferShared.entries) {
      await dir.removeDepartmentDirectPhone(entry.value, entry.key);
      if (targetDepartmentId != null) {
        await dir.addDepartmentDirectPhone(targetDepartmentId, entry.key);
      }
    }
  }

  static String _userOwnerLabel(UserModel u) {
    final name = (u.name ?? '').trim();
    if (name.isEmpty) return '';
    final dep = (u.departmentName ?? '').trim();
    return dep.isEmpty ? name : '$name ($dep)';
  }
}
