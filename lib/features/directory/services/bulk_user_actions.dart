import '../../../core/database/department_repository.dart';
import '../../../core/database/directory_support.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/models/user_model.dart';
import '../screens/widgets/shared_asset_disconnect_dialog.dart';
import 'bulk_action_undo_record.dart';
import 'user_deletion_undo_record.dart';

/// Τύχη τηλεφώνων/εξοπλισμού στη μαζική μεταφορά υπαλλήλων σε τμήμα.
enum BulkTransferAssetFate {
  /// Ακολουθούν τον υπάλληλο (τηλέφωνα: καμία αλλαγή δεσμών· εξοπλισμός:
  /// αλλάζει και το τμήμα του εξοπλισμού στο νέο).
  follow,

  /// Μένουν πίσω: αποδέσμευση από τον υπάλληλο και κοινόχρηστα του ΠΑΛΙΟΥ
  /// τμήματος.
  stayInOldDepartment,
}

/// Πεδίο-στόχος του μαζικού Καθαρισμού.
enum BulkClearField { phones, equipment, notes }

/// Τύχη των στοιχείων στον μαζικό Καθαρισμό (τρίο οικογένειας διαγραφής).
enum BulkClearFate { deleteOutright, shareInOwnDepartment, transfer }

/// Τρόπος εφαρμογής μαζικών Σημειώσεων.
enum BulkNotesMode { append, replace }

/// Στοιχείο που εξαιρέθηκε από μαζική ενέργεια, με αιτιολογία για τον χρήστη.
class BulkActionExclusion {
  const BulkActionExclusion({
    required this.isPhone,
    required this.identifier,
    required this.reason,
  });

  final bool isPhone;
  final String identifier;
  final String reason;
}

/// Πληροφορίες κοινοχρησίας για τον υπολογισμό εξαιρέσεων: ποιοι ΜΗ επιλεγμένοι
/// χρησιμοποιούν κάθε στοιχείο και ποια νούμερα είναι ήδη κοινόχρηστα τμήματος.
class BulkAssetSharingInfo {
  const BulkAssetSharingInfo({
    this.phoneOtherUserNames = const {},
    this.phoneSharedDepartmentNames = const {},
    this.equipmentOtherUserNames = const {},
  });

  /// Αριθμός → ονόματα ΜΗ επιλεγμένων υπαλλήλων που τον έχουν επίσης.
  final Map<String, List<String>> phoneOtherUserNames;

  /// Αριθμός → όνομα τμήματος όταν είναι ήδη κοινόχρηστο τμήματος.
  final Map<String, String> phoneSharedDepartmentNames;

  /// Αναγνωριστικό εξοπλισμού → ονόματα ΜΗ επιλεγμένων συν-κατόχων.
  final Map<int, List<String>> equipmentOtherUserNames;
}

/// Εμφανίσιμο όνομα υπαλλήλου για μηνύματα.
String bulkUserDisplayName(UserModel u) {
  final name = (u.name ?? '${u.firstName ?? ''} ${u.lastName ?? ''}').trim();
  return name.isEmpty ? '—' : name;
}

/// Λίστα ονομάτων για μηνύματα: έως 5 ονομαστικά, μετά «+Ν ακόμη».
String bulkUserNamesPreview(Iterable<UserModel> users) {
  final names = [for (final u in users) bulkUserDisplayName(u)];
  if (names.isEmpty) return '';
  if (names.length <= 5) return names.join(', ');
  final rest = names.length - 5;
  return '${names.take(5).join(', ')} +$rest ακόμη';
}

String _joinNames(List<String> names) {
  if (names.length <= 2) return names.join(' και ');
  return '${names.take(2).join(', ')} κ.ά.';
}

// ─────────────────────────── Μεταφορά σε τμήμα ───────────────────────────

/// Πλήρες σχέδιο μαζικής μεταφοράς: ποιοι μετακινούνται, τι κάνει κάθε
/// τηλέφωνο/εξοπλισμός, τι εξαιρέθηκε και γιατί.
class BulkUserTransferPlan {
  const BulkUserTransferPlan({
    required this.target,
    required this.targetDisplayName,
    required this.phoneFate,
    required this.equipmentFate,
    required this.usersToMove,
    required this.usersAlreadyInTarget,
    required this.phonesToRelease,
    required this.equipmentToFollow,
    required this.equipmentToRelease,
    required this.exclusions,
  });

  final SharedAssetTransferTarget target;
  final String targetDisplayName;
  final BulkTransferAssetFate phoneFate;
  final BulkTransferAssetFate equipmentFate;
  final List<UserModel> usersToMove;
  final List<UserModel> usersAlreadyInTarget;

  /// userId → αριθμοί που αποδεσμεύονται και γίνονται κοινόχρηστοι του παλιού
  /// τμήματος (μόνο όταν phoneFate = stayInOldDepartment).
  final Map<int, List<String>> phonesToRelease;

  /// userId → εξοπλισμοί που αλλάζουν τμήμα μαζί με τον υπάλληλο.
  final Map<int, List<EquipmentModel>> equipmentToFollow;

  /// userId → εξοπλισμοί που αποδεσμεύονται από τον υπάλληλο και μένουν στο
  /// παλιό τμήμα.
  final Map<int, List<EquipmentModel>> equipmentToRelease;

  final List<BulkActionExclusion> exclusions;

  bool get hasWork => usersToMove.isNotEmpty;

  int get releasedPhoneCount => [
    for (final list in phonesToRelease.values) list.length,
  ].fold(0, (a, b) => a + b);

  int get followingEquipmentCount => _uniqueEquipmentCount(equipmentToFollow);

  int get releasedEquipmentCount => _uniqueEquipmentCount(equipmentToRelease);

  static int _uniqueEquipmentCount(Map<int, List<EquipmentModel>> byUser) {
    final seen = <int>{};
    for (final list in byUser.values) {
      for (final e in list) {
        final id = e.id;
        if (id != null) seen.add(id);
      }
    }
    return seen.length;
  }
}

/// Υπολογίζει το σχέδιο μεταφοράς ΧΩΡΙΣ να αγγίξει τη βάση (τεσταρίσιμο).
BulkUserTransferPlan buildBulkUserTransferPlan({
  required List<UserModel> selectedUsers,
  required SharedAssetTransferTarget target,
  required String targetDisplayName,
  required BulkTransferAssetFate phoneFate,
  required BulkTransferAssetFate equipmentFate,
  required Map<int, List<EquipmentModel>> equipmentByUserId,
  BulkAssetSharingInfo sharing = const BulkAssetSharingInfo(),
}) {
  final targetId = target.departmentId;
  final usersToMove = <UserModel>[];
  final usersAlreadyInTarget = <UserModel>[];
  for (final u in selectedUsers) {
    if (u.id == null) continue;
    if (targetId != null && u.departmentId == targetId) {
      usersAlreadyInTarget.add(u);
    } else {
      usersToMove.add(u);
    }
  }

  final phonesToRelease = <int, List<String>>{};
  final equipmentToFollow = <int, List<EquipmentModel>>{};
  final equipmentToRelease = <int, List<EquipmentModel>>{};
  final exclusions = <BulkActionExclusion>[];
  final seenEquipmentIds = <int>{};

  for (final u in usersToMove) {
    final userId = u.id!;
    final userName = bulkUserDisplayName(u);

    if (phoneFate == BulkTransferAssetFate.stayInOldDepartment) {
      for (final number in u.phones) {
        final n = number.trim();
        if (n.isEmpty) continue;
        final others = sharing.phoneOtherUserNames[n] ?? const [];
        final sharedDept = sharing.phoneSharedDepartmentNames[n];
        if (others.isNotEmpty) {
          exclusions.add(
            BulkActionExclusion(
              isPhone: true,
              identifier: n,
              reason:
                  'Το $n παραμένει στον υπάλληλο $userName — '
                  'το χρησιμοποιεί και ο ${_joinNames(others)}.',
            ),
          );
        } else if (sharedDept != null) {
          exclusions.add(
            BulkActionExclusion(
              isPhone: true,
              identifier: n,
              reason:
                  'Το $n παραμένει στον υπάλληλο $userName — '
                  'είναι ήδη κοινόχρηστο του τμήματος $sharedDept.',
            ),
          );
        } else if (u.departmentId == null) {
          exclusions.add(
            BulkActionExclusion(
              isPhone: true,
              identifier: n,
              reason:
                  'Το $n παραμένει στον υπάλληλο $userName — '
                  'δεν υπάρχει τμήμα-αφετηρία για να γίνει κοινόχρηστο.',
            ),
          );
        } else {
          phonesToRelease.putIfAbsent(userId, () => []).add(n);
        }
      }
    }

    for (final e in equipmentByUserId[userId] ?? const <EquipmentModel>[]) {
      final eqId = e.id;
      if (eqId == null || !seenEquipmentIds.add(eqId)) continue;
      final code = (e.code ?? '').trim();
      if (code.isEmpty) continue;
      final others = sharing.equipmentOtherUserNames[eqId] ?? const [];
      if (others.isNotEmpty) {
        exclusions.add(
          BulkActionExclusion(
            isPhone: false,
            identifier: code,
            reason:
                'Ο εξοπλισμός $code μένει ως έχει — '
                'τον χρησιμοποιεί και ο ${_joinNames(others)}.',
          ),
        );
        continue;
      }
      if (equipmentFate == BulkTransferAssetFate.follow) {
        equipmentToFollow.putIfAbsent(userId, () => []).add(e);
      } else {
        if (e.departmentId == null && u.departmentId == null) {
          exclusions.add(
            BulkActionExclusion(
              isPhone: false,
              identifier: code,
              reason:
                  'Ο εξοπλισμός $code παραμένει στον υπάλληλο $userName — '
                  'χωρίς τμήμα-αφετηρία θα έμενε ορφανός.',
            ),
          );
        } else {
          equipmentToRelease.putIfAbsent(userId, () => []).add(e);
        }
      }
    }
  }

  return BulkUserTransferPlan(
    target: target,
    targetDisplayName: targetDisplayName,
    phoneFate: phoneFate,
    equipmentFate: equipmentFate,
    usersToMove: usersToMove,
    usersAlreadyInTarget: usersAlreadyInTarget,
    phonesToRelease: phonesToRelease,
    equipmentToFollow: equipmentToFollow,
    equipmentToRelease: equipmentToRelease,
    exclusions: exclusions,
  );
}

/// Κείμενο επιβεβαίωσης ΠΡΙΝ την εκτέλεση της μεταφοράς: τι θα συμβεί σε ποιους.
String bulkTransferConfirmationText(BulkUserTransferPlan plan) {
  final buf = StringBuffer();
  final n = plan.usersToMove.length;
  buf.write(
    n == 1
        ? 'Θα μεταφερθεί 1 υπάλληλος στο «${plan.targetDisplayName}»'
        : 'Θα μεταφερθούν $n υπάλληλοι στο «${plan.targetDisplayName}»',
  );
  final names = bulkUserNamesPreview(plan.usersToMove);
  if (names.isNotEmpty) buf.write(': $names');
  buf.write('.');
  if (plan.target.departmentId == null) {
    buf.write('\nΤο τμήμα «${plan.targetDisplayName}» θα δημιουργηθεί τώρα.');
  }
  if (plan.usersAlreadyInTarget.isNotEmpty) {
    buf.write(
      '\n${plan.usersAlreadyInTarget.length} από τους επιλεγμένους '
      'είναι ήδη εκεί και δεν αλλάζουν: '
      '${bulkUserNamesPreview(plan.usersAlreadyInTarget)}.',
    );
  }
  buf.write(
    plan.phoneFate == BulkTransferAssetFate.follow
        ? '\nΤα τηλέφωνα ακολουθούν τους υπαλλήλους.'
        : '\nΤα τηλέφωνα μένουν κοινόχρηστα στο παλιό τους τμήμα'
              ' (${plan.releasedPhoneCount} αριθμοί).',
  );
  buf.write(
    plan.equipmentFate == BulkTransferAssetFate.follow
        ? '\nΟι εξοπλισμοί ακολουθούν στο νέο τμήμα'
              ' (${plan.followingEquipmentCount} εξοπλισμοί).'
        : '\nΟι εξοπλισμοί αποδεσμεύονται και μένουν στο παλιό τμήμα'
              ' (${plan.releasedEquipmentCount} εξοπλισμοί).',
  );
  for (final ex in plan.exclusions) {
    buf.write('\n• ${ex.reason}');
  }
  return buf.toString();
}

/// Μήνυμα αποτελέσματος ΜΕΤΑ τη μεταφορά (για τη μπάρα αναίρεσης).
String bulkTransferResultMessage(BulkUserTransferPlan plan) {
  final n = plan.usersToMove.length;
  final buf = StringBuffer(
    n == 1
        ? 'Μεταφέρθηκε 1 υπάλληλος στο «${plan.targetDisplayName}»'
        : 'Μεταφέρθηκαν $n υπάλληλοι στο «${plan.targetDisplayName}»',
  );
  if (plan.releasedPhoneCount > 0) {
    buf.write(
      ' · ${plan.releasedPhoneCount} τηλέφωνα έγιναν κοινόχρηστα '
      'στο παλιό τμήμα',
    );
  }
  if (plan.followingEquipmentCount > 0) {
    buf.write(' · ${plan.followingEquipmentCount} εξοπλισμοί ακολούθησαν');
  }
  if (plan.releasedEquipmentCount > 0) {
    buf.write(
      ' · ${plan.releasedEquipmentCount} εξοπλισμοί έμειναν στο παλιό τμήμα',
    );
  }
  if (plan.exclusions.isNotEmpty) {
    buf.write(' · ${plan.exclusions.length} εξαιρέσεις');
  }
  buf.write('.');
  return buf.toString();
}

// ─────────────────────────── Καθαρισμός πεδίου ───────────────────────────

/// Σχέδιο μαζικού Καθαρισμού πεδίου με ΜΙΑ απόφαση για όλους.
class BulkUserClearPlan {
  const BulkUserClearPlan({
    required this.field,
    required this.fate,
    this.transferTarget,
    this.transferTargetDisplayName,
    required this.users,
    required this.phonesByUser,
    required this.equipmentByUser,
    required this.exclusions,
  });

  final BulkClearField field;
  final BulkClearFate fate;
  final SharedAssetTransferTarget? transferTarget;
  final String? transferTargetDisplayName;
  final List<UserModel> users;
  final Map<int, List<String>> phonesByUser;
  final Map<int, List<EquipmentModel>> equipmentByUser;
  final List<BulkActionExclusion> exclusions;

  bool get hasWork {
    switch (field) {
      case BulkClearField.phones:
        return phonesByUser.values.any((l) => l.isNotEmpty);
      case BulkClearField.equipment:
        return equipmentByUser.values.any((l) => l.isNotEmpty);
      case BulkClearField.notes:
        return users.any((u) => (u.notes ?? '').trim().isNotEmpty);
    }
  }
}

/// Υπολογίζει το σχέδιο Καθαρισμού ΧΩΡΙΣ πρόσβαση στη βάση (τεσταρίσιμο).
BulkUserClearPlan buildBulkUserClearPlan({
  required List<UserModel> selectedUsers,
  required BulkClearField field,
  required BulkClearFate fate,
  SharedAssetTransferTarget? transferTarget,
  String? transferTargetDisplayName,
  Map<int, List<EquipmentModel>> equipmentByUserId = const {},
  BulkAssetSharingInfo sharing = const BulkAssetSharingInfo(),
}) {
  final users = [
    for (final u in selectedUsers)
      if (u.id != null) u,
  ];
  final phonesByUser = <int, List<String>>{};
  final equipmentByUser = <int, List<EquipmentModel>>{};
  final exclusions = <BulkActionExclusion>[];
  final seenEquipmentIds = <int>{};

  if (field == BulkClearField.phones) {
    for (final u in users) {
      final userName = bulkUserDisplayName(u);
      for (final number in u.phones) {
        final n = number.trim();
        if (n.isEmpty) continue;
        final others = sharing.phoneOtherUserNames[n] ?? const [];
        final sharedDept = sharing.phoneSharedDepartmentNames[n];
        if (others.isNotEmpty) {
          exclusions.add(
            BulkActionExclusion(
              isPhone: true,
              identifier: n,
              reason:
                  'Το $n δεν καθαρίζεται — '
                  'το χρησιμοποιεί και ο ${_joinNames(others)}.',
            ),
          );
        } else if (sharedDept != null) {
          exclusions.add(
            BulkActionExclusion(
              isPhone: true,
              identifier: n,
              reason:
                  'Το $n δεν καθαρίζεται — '
                  'είναι ήδη κοινόχρηστο του τμήματος $sharedDept.',
            ),
          );
        } else if (fate == BulkClearFate.shareInOwnDepartment &&
            u.departmentId == null) {
          exclusions.add(
            BulkActionExclusion(
              isPhone: true,
              identifier: n,
              reason:
                  'Το $n παραμένει στον υπάλληλο $userName — '
                  'δεν έχει τμήμα για να γίνει κοινόχρηστο.',
            ),
          );
        } else {
          phonesByUser.putIfAbsent(u.id!, () => []).add(n);
        }
      }
    }
  }

  if (field == BulkClearField.equipment) {
    for (final u in users) {
      final userName = bulkUserDisplayName(u);
      for (final e in equipmentByUserId[u.id!] ?? const <EquipmentModel>[]) {
        final eqId = e.id;
        if (eqId == null) continue;
        final code = (e.code ?? '').trim();
        if (code.isEmpty) continue;
        final others = sharing.equipmentOtherUserNames[eqId] ?? const [];
        if (others.isNotEmpty) {
          if (seenEquipmentIds.add(eqId)) {
            exclusions.add(
              BulkActionExclusion(
                isPhone: false,
                identifier: code,
                reason:
                    'Ο εξοπλισμός $code δεν καθαρίζεται — '
                    'τον χρησιμοποιεί και ο ${_joinNames(others)}.',
              ),
            );
          }
          continue;
        }
        if (fate == BulkClearFate.shareInOwnDepartment &&
            e.departmentId == null &&
            u.departmentId == null) {
          if (seenEquipmentIds.add(eqId)) {
            exclusions.add(
              BulkActionExclusion(
                isPhone: false,
                identifier: code,
                reason:
                    'Ο εξοπλισμός $code παραμένει στον υπάλληλο $userName — '
                    'χωρίς τμήμα θα έμενε ορφανός.',
              ),
            );
          }
          continue;
        }
        equipmentByUser.putIfAbsent(u.id!, () => []).add(e);
      }
    }
  }

  return BulkUserClearPlan(
    field: field,
    fate: fate,
    transferTarget: transferTarget,
    transferTargetDisplayName: transferTargetDisplayName,
    users: users,
    phonesByUser: phonesByUser,
    equipmentByUser: equipmentByUser,
    exclusions: exclusions,
  );
}

String _clearFateLabel(BulkUserClearPlan plan) {
  switch (plan.fate) {
    case BulkClearFate.deleteOutright:
      return 'θα διαγραφούν';
    case BulkClearFate.shareInOwnDepartment:
      return 'θα γίνουν κοινόχρηστα στο τμήμα του κάθε υπαλλήλου';
    case BulkClearFate.transfer:
      return 'θα μεταφερθούν στο «${plan.transferTargetDisplayName ?? ''}»';
  }
}

/// Κείμενο επιβεβαίωσης ΠΡΙΝ τον Καθαρισμό.
String bulkClearConfirmationText(BulkUserClearPlan plan) {
  final buf = StringBuffer();
  switch (plan.field) {
    case BulkClearField.notes:
      final withNotes = [
        for (final u in plan.users)
          if ((u.notes ?? '').trim().isNotEmpty) u,
      ];
      buf.write(
        'Θα διαγραφούν οι σημειώσεις ${withNotes.length} υπαλλήλων: '
        '${bulkUserNamesPreview(withNotes)}.',
      );
    case BulkClearField.phones:
      final count = [
        for (final l in plan.phonesByUser.values) l.length,
      ].fold(0, (a, b) => a + b);
      buf.write(
        'Θα αποδεσμευτούν $count τηλέφωνα από '
        '${plan.phonesByUser.length} υπαλλήλους και ${_clearFateLabel(plan)}.',
      );
    case BulkClearField.equipment:
      final seen = <int>{};
      for (final l in plan.equipmentByUser.values) {
        for (final e in l) {
          if (e.id != null) seen.add(e.id!);
        }
      }
      buf.write(
        'Θα αποδεσμευτούν ${seen.length} εξοπλισμοί από '
        '${plan.equipmentByUser.length} υπαλλήλους και ${_clearFateLabel(plan)}.',
      );
  }
  for (final ex in plan.exclusions) {
    buf.write('\n• ${ex.reason}');
  }
  return buf.toString();
}

/// Μήνυμα αποτελέσματος ΜΕΤΑ τον Καθαρισμό.
String bulkClearResultMessage(BulkUserClearPlan plan) {
  final buf = StringBuffer();
  switch (plan.field) {
    case BulkClearField.notes:
      buf.write('Διαγράφηκαν οι σημειώσεις ${plan.users.length} υπαλλήλων');
    case BulkClearField.phones:
      final count = [
        for (final l in plan.phonesByUser.values) l.length,
      ].fold(0, (a, b) => a + b);
      buf.write('Αποδεσμεύτηκαν $count τηλέφωνα');
    case BulkClearField.equipment:
      final seen = <int>{};
      for (final l in plan.equipmentByUser.values) {
        for (final e in l) {
          if (e.id != null) seen.add(e.id!);
        }
      }
      buf.write('Αποδεσμεύτηκαν ${seen.length} εξοπλισμοί');
  }
  if (plan.exclusions.isNotEmpty) {
    buf.write(' · ${plan.exclusions.length} εξαιρέσεις');
  }
  buf.write('.');
  return buf.toString();
}

// ─────────────────────── Βοηθητικά ανάγνωσης σε txn ───────────────────────

Future<Map<String, dynamic>?> _userRowInTxn(
  DatabaseExecutor txn,
  int userId,
) async {
  final rows = await txn.query(
    'users',
    columns: ['id', 'department_id', 'notes'],
    where: 'id = ?',
    whereArgs: [userId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<List<String>> _userPhonesInTxn(DatabaseExecutor txn, int userId) async {
  final rows = await txn.rawQuery(
    '''
    SELECT p.number AS number
    FROM user_phones up
    JOIN phones p ON p.id = up.phone_id
    WHERE up.user_id = ?
    ORDER BY p.number
  ''',
    [userId],
  );
  return [
    for (final r in rows)
      if ((r['number'] as String?)?.trim().isNotEmpty ?? false)
        (r['number'] as String).trim(),
  ];
}

Future<Map<String, dynamic>?> _equipmentRowInTxn(
  DatabaseExecutor txn,
  int equipmentId,
) async {
  final rows = await txn.query(
    'equipment',
    columns: ['id', 'code_equipment', 'department_id'],
    where: 'id = ?',
    whereArgs: [equipmentId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<int?> _activeDepartmentIdByNameInTxn(
  DatabaseExecutor txn,
  String name,
) async {
  final key = SearchTextNormalizer.normalizeForSearch(name.trim());
  if (key.isEmpty) return null;
  final rows = await txn.query(
    'departments',
    columns: ['id'],
    where: '${DirectorySupport.notDeletedClause} AND name_key = ?',
    whereArgs: [key],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first['id'] as int?;
}

/// Επιλύει τον προορισμό μεταφοράς μέσα στη συναλλαγή.
/// Επιστρέφει (id τμήματος, id ΜΟΝΟ αν δημιουργήθηκε τώρα).
Future<(int?, int?)> _resolveTransferTargetInTxn(
  DatabaseExecutor txn,
  DepartmentRepository departments,
  SharedAssetTransferTarget target,
) async {
  if (target.departmentId != null) return (target.departmentId, null);
  final name = target.newDepartmentName?.trim();
  if (name == null || name.isEmpty) return (null, null);
  final existing = await _activeDepartmentIdByNameInTxn(txn, name);
  final id = await departments.getOrCreateDepartmentIdByName(
    name,
    executor: txn,
  );
  return (id, existing == null ? id : null);
}

// ─────────────────────── Εφαρμογές σε μία συναλλαγή ───────────────────────

/// Εφαρμόζει τη μαζική μεταφορά ΜΕΣΑ στο [txn] και επιστρέφει πακέτο αναίρεσης.
Future<BulkActionUndoRecord> applyBulkUserTransferInTxn(
  DatabaseExecutor txn,
  Database db,
  BulkUserTransferPlan plan,
) async {
  if (!plan.hasWork) return const BulkActionUndoRecord();

  final users = UserRepository(db);
  final phones = PhoneRepository(db);
  final equipment = EquipmentRepository(db);
  final departments = DepartmentRepository(db);

  final (targetId, createdDepartmentId) = await _resolveTransferTargetInTxn(
    txn,
    departments,
    plan.target,
  );
  if (targetId == null) return const BulkActionUndoRecord();

  final userDepartmentBefore = <int, int?>{};
  final userPhonesBefore = <int, List<String>>{};
  final phoneDeptAdds = <PhoneDeptAdd>[];
  final equipmentDepartmentBefore = <String, int?>{};
  final equipmentDepartmentAfter = <String, int>{};
  final unlinked = <BulkUserEquipmentUnlink>[];

  for (final u in plan.usersToMove) {
    final userId = u.id!;
    final row = await _userRowInTxn(txn, userId);
    if (row == null) continue;
    final oldDept = row['department_id'] as int?;
    userDepartmentBefore[userId] = oldDept;

    final toRelease = plan.phonesToRelease[userId] ?? const <String>[];
    if (toRelease.isNotEmpty && oldDept != null) {
      final before = await _userPhonesInTxn(txn, userId);
      userPhonesBefore[userId] = before;
      final remaining = [
        for (final n in before)
          if (!toRelease.contains(n)) n,
      ];
      await users.replaceUserPhones(userId, remaining, executor: txn);
      for (final n in toRelease) {
        await phones.addDepartmentDirectPhone(oldDept, n, executor: txn);
        phoneDeptAdds.add(PhoneDeptAdd(departmentId: oldDept, phoneNumber: n));
      }
    }

    await users.updateUser(
      userId,
      {'department_id': targetId},
      executor: txn,
      skipPhonePolicyValidation: true,
    );

    for (final e in plan.equipmentToFollow[userId] ?? const []) {
      final eqRow = await _equipmentRowInTxn(txn, e.id!);
      if (eqRow == null) continue;
      final code = (eqRow['code_equipment'] as String?)?.trim() ?? '';
      if (code.isEmpty) continue;
      final before = eqRow['department_id'] as int?;
      if (before == targetId) continue;
      equipmentDepartmentBefore[code] = before;
      equipmentDepartmentAfter[code] = targetId;
      await equipment.updateEquipmentDepartment(code, targetId, executor: txn);
    }

    for (final e in plan.equipmentToRelease[userId] ?? const []) {
      final eqRow = await _equipmentRowInTxn(txn, e.id!);
      if (eqRow == null) continue;
      final code = (eqRow['code_equipment'] as String?)?.trim() ?? '';
      await equipment.unlinkUserFromEquipment(userId, e.id!, executor: txn);
      unlinked.add(BulkUserEquipmentUnlink(userId: userId, equipmentId: e.id!));
      final eqDept = eqRow['department_id'] as int?;
      if (eqDept == null && oldDept != null && code.isNotEmpty) {
        equipmentDepartmentBefore[code] = null;
        equipmentDepartmentAfter[code] = oldDept;
        await equipment.updateEquipmentDepartment(code, oldDept, executor: txn);
      }
    }
  }

  return BulkActionUndoRecord(
    userDepartmentBefore: userDepartmentBefore,
    userPhonesBefore: userPhonesBefore,
    phoneDeptAdds: phoneDeptAdds,
    equipmentDepartmentBefore: equipmentDepartmentBefore,
    equipmentDepartmentAfter: equipmentDepartmentAfter,
    unlinkedUserEquipment: unlinked,
    createdDepartmentId: createdDepartmentId,
  );
}

/// Εφαρμόζει μαζικές Σημειώσεις ΜΕΣΑ στο [txn].
Future<BulkActionUndoRecord> applyBulkUserNotesInTxn(
  DatabaseExecutor txn,
  Database db, {
  required List<UserModel> users,
  required String text,
  required BulkNotesMode mode,
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty && mode == BulkNotesMode.replace) {
    return const BulkActionUndoRecord();
  }
  final repo = UserRepository(db);
  final notesBefore = <int, String?>{};
  for (final u in users) {
    final userId = u.id;
    if (userId == null) continue;
    final row = await _userRowInTxn(txn, userId);
    if (row == null) continue;
    final before = (row['notes'] as String?)?.trim();
    notesBefore[userId] = row['notes'] as String?;
    final String next;
    if (mode == BulkNotesMode.replace) {
      next = trimmed;
    } else {
      next = (before == null || before.isEmpty) ? trimmed : '$before\n$trimmed';
    }
    await repo.updateUser(
      userId,
      {'notes': next},
      executor: txn,
      skipPhonePolicyValidation: true,
    );
  }
  return BulkActionUndoRecord(userNotesBefore: notesBefore);
}

/// Εφαρμόζει τον μαζικό Καθαρισμό ΜΕΣΑ στο [txn].
Future<BulkActionUndoRecord> applyBulkUserClearInTxn(
  DatabaseExecutor txn,
  Database db,
  BulkUserClearPlan plan,
) async {
  if (!plan.hasWork) return const BulkActionUndoRecord();

  final users = UserRepository(db);
  final phones = PhoneRepository(db);
  final equipment = EquipmentRepository(db);
  final departments = DepartmentRepository(db);

  final userPhonesBefore = <int, List<String>>{};
  final phoneDeptAdds = <PhoneDeptAdd>[];
  final softDeletedPhoneNumbers = <String>[];
  final softDeletedEquipmentCodes = <String>[];
  final equipmentDepartmentBefore = <String, int?>{};
  final equipmentDepartmentAfter = <String, int>{};
  final unlinked = <BulkUserEquipmentUnlink>[];
  final userNotesBefore = <int, String?>{};
  int? createdDepartmentId;

  int? transferTargetId;
  if (plan.fate == BulkClearFate.transfer && plan.transferTarget != null) {
    final (resolved, created) = await _resolveTransferTargetInTxn(
      txn,
      departments,
      plan.transferTarget!,
    );
    transferTargetId = resolved;
    createdDepartmentId = created;
    if (transferTargetId == null) return const BulkActionUndoRecord();
  }

  switch (plan.field) {
    case BulkClearField.notes:
      for (final u in plan.users) {
        final userId = u.id!;
        final row = await _userRowInTxn(txn, userId);
        if (row == null) continue;
        final before = row['notes'] as String?;
        if (before == null || before.trim().isEmpty) continue;
        userNotesBefore[userId] = before;
        await users.updateUser(
          userId,
          {'notes': null},
          executor: txn,
          skipPhonePolicyValidation: true,
        );
      }

    case BulkClearField.phones:
      final handledNumbers = <String>{};
      final handledDeptAdds = <String>{};
      for (final entry in plan.phonesByUser.entries) {
        final userId = entry.key;
        final toClear = entry.value;
        if (toClear.isEmpty) continue;
        final before = await _userPhonesInTxn(txn, userId);
        userPhonesBefore[userId] = before;
        final remaining = [
          for (final n in before)
            if (!toClear.contains(n)) n,
        ];
        await users.replaceUserPhones(userId, remaining, executor: txn);

        UserModel? owner;
        for (final u in plan.users) {
          if (u.id == userId) {
            owner = u;
            break;
          }
        }
        for (final n in toClear) {
          switch (plan.fate) {
            case BulkClearFate.deleteOutright:
              if (!handledNumbers.add(n)) continue;
              final id = await phones.getPhoneIdByNumber(n, executor: txn);
              if (id == null) continue;
              await phones.softDeletePhones([id], executor: txn);
              softDeletedPhoneNumbers.add(n);
            case BulkClearFate.shareInOwnDepartment:
              final deptId = owner?.departmentId;
              if (deptId == null) continue;
              if (!handledDeptAdds.add('$deptId|$n')) continue;
              await phones.addDepartmentDirectPhone(deptId, n, executor: txn);
              phoneDeptAdds.add(
                PhoneDeptAdd(departmentId: deptId, phoneNumber: n),
              );
            case BulkClearFate.transfer:
              if (!handledDeptAdds.add('$transferTargetId|$n')) continue;
              await phones.addDepartmentDirectPhone(
                transferTargetId!,
                n,
                executor: txn,
              );
              phoneDeptAdds.add(
                PhoneDeptAdd(departmentId: transferTargetId, phoneNumber: n),
              );
          }
        }
      }

    case BulkClearField.equipment:
      final handledEquipment = <int>{};
      for (final entry in plan.equipmentByUser.entries) {
        final userId = entry.key;
        UserModel? owner;
        for (final u in plan.users) {
          if (u.id == userId) {
            owner = u;
            break;
          }
        }
        for (final e in entry.value) {
          final eqId = e.id!;
          final eqRow = await _equipmentRowInTxn(txn, eqId);
          if (eqRow == null) continue;
          final code = (eqRow['code_equipment'] as String?)?.trim() ?? '';
          await equipment.unlinkUserFromEquipment(userId, eqId, executor: txn);
          unlinked.add(
            BulkUserEquipmentUnlink(userId: userId, equipmentId: eqId),
          );
          if (!handledEquipment.add(eqId)) continue;
          final eqDept = eqRow['department_id'] as int?;
          switch (plan.fate) {
            case BulkClearFate.deleteOutright:
              await equipment.deleteEquipments([eqId], executor: txn);
              if (code.isNotEmpty) softDeletedEquipmentCodes.add(code);
            case BulkClearFate.shareInOwnDepartment:
              final deptId = owner?.departmentId;
              if (eqDept == null && deptId != null && code.isNotEmpty) {
                equipmentDepartmentBefore[code] = null;
                equipmentDepartmentAfter[code] = deptId;
                await equipment.updateEquipmentDepartment(
                  code,
                  deptId,
                  executor: txn,
                );
              }
            case BulkClearFate.transfer:
              if (code.isEmpty || eqDept == transferTargetId) continue;
              equipmentDepartmentBefore[code] = eqDept;
              equipmentDepartmentAfter[code] = transferTargetId!;
              await equipment.updateEquipmentDepartment(
                code,
                transferTargetId,
                executor: txn,
              );
          }
        }
      }
  }

  return BulkActionUndoRecord(
    userPhonesBefore: userPhonesBefore,
    phoneDeptAdds: phoneDeptAdds,
    equipmentDepartmentBefore: equipmentDepartmentBefore,
    equipmentDepartmentAfter: equipmentDepartmentAfter,
    unlinkedUserEquipment: unlinked,
    softDeletedPhoneNumbers: softDeletedPhoneNumbers,
    softDeletedEquipmentCodes: softDeletedEquipmentCodes,
    userNotesBefore: userNotesBefore,
    createdDepartmentId: createdDepartmentId,
  );
}
