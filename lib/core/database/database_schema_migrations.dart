import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_config.dart';
import 'audit_diff_helper.dart';
import 'audit_service.dart';
import '../utils/lexicon_word_metrics.dart';
import '../utils/search_text_normalizer.dart';
import 'database_init_result.dart';
import 'database_v1_schema.dart';
import 'dictionary_repository.dart';
import 'directory_audit_helpers.dart';

/// Squashed schema version (ίδιο με [databaseSchemaVersionV1]).
const int kDatabaseSchemaVersion = databaseSchemaVersionV1;

/// Επαληθεύει ότι υπάρχει ο πίνακας `calls`. Αλλιώς ρίχνει [DatabaseInitException].
Future<void> validateDatabaseSchema(Database db, String dbPath) async {
  final r = await db.rawQuery('PRAGMA table_info(calls)');
  if (r.isEmpty) {
    throw DatabaseInitException(
      DatabaseInitResult.corruptedOrInvalid(
        dbPath,
        'Λείπει ο πίνακας calls· το αρχείο δεν φαίνεται έγκυρη βάση.',
      ),
    );
  }
}

/// Δημιουργία σχήματος v1 (squashed): όλοι οι πίνακες σε μία δημιουργία.
Future<void> onDatabaseCreate(Database db, int version) async {
  await applyDatabaseV1Schema(db);
}

/// Μήνυμα αναντιστοιχίας user_version (αρχείο) έναντι έκδοσης σχήματος εφαρμογής.
String schemaVersionMismatchUserMessage(
  Database db,
  int fileUserVersion,
  int appSchemaVersion,
) {
  final fileName = p.basename(db.path);
  return 'Το αρχείο της βάσης σας $fileName είναι στην έκδοση '
      '$fileUserVersion. Η εφαρμογή τρέχει την έκδοση '
      '$appSchemaVersion.\n\n'
      'Μπορείτε να:\n'
      '• Μετασχηματίσετε την βάση σας στη σωστή έκδοση με κάποιο script.\n'
      '• Να εντοπίσετε το σωστό αρχείο βάσης (μέσα από τις ρυθμίσεις).\n'
      '• Να δημιουργήσετε μια νέα βάση χωρίς δεδομένα (μέσα από τις ρυθμίσεις).';
}

/// Αναβάθμιση squashed σχήματος (π.χ. v1 → v2: στήλες `equipment.department_id`, `location`).
Future<void> onDatabaseUpgradeSquashed(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion >= newVersion) return;
  if (oldVersion == 0) return;
  // Sequential, idempotent migrations για άλματα εκδόσεων (π.χ. 2 -> 5).
  if (oldVersion < 2 && newVersion >= 2) {
    await migrateEquipmentDepartmentLocationColumns(db);
  }
  if (oldVersion < 3 && newVersion >= 3) {
    await migrateDepartmentPhonesTable(db);
  }
  if (oldVersion < 4 && newVersion >= 4) {
    await migrateDepartmentNameKey(db);
  }
  if (oldVersion < 5 && newVersion >= 5) {
    await migratePhonesDepartmentColumn(db);
  }
  if (oldVersion < 6 && newVersion >= 6) {
    await migrateUserDictionaryTable(db);
  }
  if (oldVersion < 7 && newVersion >= 7) {
    await migrateFullDictionaryTable(db);
  }
  if (oldVersion < 8 && newVersion >= 8) {
    await migrateUserDictionaryLanguageColumn(db);
  }
  if (oldVersion < 9 && newVersion >= 9) {
    await migrateLexiconWordMetricsColumns(db);
  }
  if (oldVersion < 10 && newVersion >= 10) {
    await migrateEquipmentRemoteParamsColumn(db);
  }
  if (oldVersion < 11 && newVersion >= 11) {
    await migrateDatabaseToV11(db);
  }
  if (oldVersion < 12 && newVersion >= 12) {
    await migrateDatabaseToV12(db);
  }
  if (oldVersion < 13 && newVersion >= 13) {
    await migrateDatabaseToV13(db);
  }
  if (oldVersion < 14 && newVersion >= 14) {
    await migrateDatabaseToV14(db);
  }
  if (oldVersion < 15 && newVersion >= 15) {
    await migrateDatabaseToV15(db);
  }
  if (oldVersion < 16 && newVersion >= 16) {
    await migrateDatabaseToV16(db);
  }
  if (oldVersion < 17 && newVersion >= 17) {
    await migrateDatabaseToV17(db);
  }
  if (oldVersion < 18 && newVersion >= 18) {
    await migrateDatabaseToV18(db);
  }
  if (oldVersion < 19 && newVersion >= 19) {
    await migrateDatabaseToV19(db);
  }
  if (oldVersion < 20 && newVersion >= 20) {
    await migrateDatabaseToV20(db);
  }
  if (oldVersion < 21 && newVersion >= 21) {
    await migrateDatabaseToV21(db);
  }
  if (oldVersion < 22 && newVersion >= 22) {
    await migrateDatabaseToV22(db);
  }
  if (oldVersion < 23 && newVersion >= 23) {
    await migrateDatabaseToV23(db);
  }
  if (oldVersion < 24 && newVersion >= 24) {
    await migrateDatabaseToV24(db);
  }
  if (oldVersion < 25 && newVersion >= 25) {
    await migrateDatabaseToV25(db);
  }
  if (oldVersion < 26 && newVersion >= 26) {
    await migrateDatabaseToV26(db);
  }
  if (oldVersion < 27 && newVersion >= 27) {
    await migrateDatabaseToV27(db);
  }
  if (oldVersion < 28 && newVersion >= 28) {
    await migrateDatabaseToV28(db);
  }
  if (oldVersion < 29 && newVersion >= 29) {
    await migrateDatabaseToV29(db);
  }
  if (oldVersion < 30 && newVersion >= 30) {
    await migrateDatabaseToV30(db);
  }
  if (oldVersion < 31 && newVersion >= 31) {
    await migrateDatabaseToV31(db);
  }
  if (oldVersion < 32 && newVersion >= 32) {
    await migrateDatabaseToV32(db);
  }
  if (oldVersion < 33 && newVersion >= 33) {
    await migrateDatabaseToV33(db);
  }
  if (oldVersion < 34 && newVersion >= 34) {
    await migrateDatabaseToV34(db);
  }
  if (oldVersion < 35 && newVersion >= 35) {
    await migrateDatabaseToV35(db);
  }
  if (oldVersion < 36 && newVersion >= 36) {
    await migrateDatabaseToV36(db);
  }
}

/// v36: ανακατασκευή search_text με ελληνικές ετικέτες audit (idempotent).
Future<void> migrateDatabaseToV36(Database db) async {
  await AuditService.migrateRebuildAuditSearchTextIndex(db);
}

/// v35: αναδρομικός καθαρισμός παλιών εγγραφών audit (μόνο δεδομένα, idempotent).
Future<void> migrateDatabaseToV35(Database db) async {
  await db.transaction((txn) async {
    var mergedCount = 0;
    var deletedCount = 0;

    deletedCount += await _v35CleanupSideEntityLinkRows(txn);
    mergedCount += await _v35MergeEquipmentRemoteParamsPairs(txn);
    final mergeResult = await _v35MergeDuplicateModifyRows(txn);
    mergedCount += mergeResult.merged;
    deletedCount += mergeResult.deleted;

    await AuditService.rebuildAllSearchTexts(txn);

    if (mergedCount > 0 || deletedCount > 0) {
      final user = await AuditService.performingUser(txn);
      await AuditService.log(
        txn,
        action: 'ΕΠΙΔΙΟΡΘΩΣΗ ΑΚΕΡΑΙΟΤΗΤΑΣ',
        userPerforming: user,
        entityType: AuditEntityTypes.maintenance,
        details: 'auditHistoryCleanupV35',
        newValues: {
          'rows_merged': mergedCount,
          'rows_deleted': deletedCount,
        },
      );
    }
  });
}

const int _kAuditMergeWindowSeconds = 2;

bool _v35IsModifyAction(String? action) {
  if (action == null) return false;
  final t = action.trim();
  if (t.isEmpty) return false;
  if (AuditActions.isGenericModifyAction(t)) return true;
  return t.startsWith('ΤΡΟΠΟΠΟΙΗΣΗ');
}

DateTime? _v35ParseTimestamp(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim());
}

bool _v35WithinMergeWindow(String? tsA, String? tsB) {
  final a = _v35ParseTimestamp(tsA);
  final b = _v35ParseTimestamp(tsB);
  if (a == null || b == null) return false;
  return a.difference(b).inSeconds.abs() <= _kAuditMergeWindowSeconds;
}

bool _v35GroupWithinWindow(List<Map<String, Object?>> rows) {
  if (rows.length < 2) return false;
  DateTime? minTs;
  DateTime? maxTs;
  for (final row in rows) {
    final ts = _v35ParseTimestamp(row['timestamp'] as String?);
    if (ts == null) return false;
    minTs = minTs == null || ts.isBefore(minTs) ? ts : minTs;
    maxTs = maxTs == null || ts.isAfter(maxTs) ? ts : maxTs;
  }
  if (minTs == null || maxTs == null) return false;
  return maxTs.difference(minTs).inSeconds <= _kAuditMergeWindowSeconds;
}

Map<String, dynamic>? _v35DecodeJsonMap(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
  } catch (_) {}
  return null;
}

int _v35RowId(Map<String, Object?> row) {
  final idRaw = row['id'];
  if (idRaw is int) return idRaw;
  return (idRaw as num).toInt();
}

String _v35EntityTablePrefix(String entityType) {
  switch (entityType) {
    case AuditEntityTypes.user:
      return 'users';
    case AuditEntityTypes.department:
      return 'departments';
    case AuditEntityTypes.equipment:
      return 'equipment';
    case AuditEntityTypes.phone:
      return 'phones';
    case AuditEntityTypes.category:
      return 'categories';
    case AuditEntityTypes.call:
      return 'calls';
    case AuditEntityTypes.task:
      return 'tasks';
    default:
      return entityType;
  }
}

bool _v35HasLinkedUserPayload(
  Map<String, dynamic>? oldMap,
  Map<String, dynamic>? newMap,
) {
  return oldMap?.containsKey('linked_user_id') == true ||
      newMap?.containsKey('linked_user_id') == true;
}

bool _v35IsSideEntityLinkRow(Map<String, Object?> row) {
  final entityType = (row['entity_type'] as String?)?.trim();
  if (entityType != AuditEntityTypes.phone &&
      entityType != AuditEntityTypes.equipment) {
    return false;
  }
  final oldMap = _v35DecodeJsonMap(row['old_values_json'] as String?);
  final newMap = _v35DecodeJsonMap(row['new_values_json'] as String?);
  if (entityType == AuditEntityTypes.phone) {
    return _v35HasLinkedUserPayload(oldMap, newMap);
  }
  final details = (row['details'] as String?)?.toLowerCase() ?? '';
  if (details.contains('σύνδεση χρήστη') ||
      details.contains('αποσύνδεση χρήστη')) {
    return true;
  }
  return oldMap?.containsKey('linked_users') == true ||
      newMap?.containsKey('linked_users') == true;
}

bool _v35IsUserSideLinkRow(Map<String, Object?> row) {
  if ((row['entity_type'] as String?)?.trim() != AuditEntityTypes.user) {
    return false;
  }
  if (!_v35IsModifyAction(row['action'] as String?)) return false;
  final details = (row['details'] as String?) ?? '';
  if (details.contains('Προσθήκη τηλεφών') ||
      details.contains('Αποσύνδεση τηλεφών') ||
      details.contains('Προσθήκη εξοπλισμ') ||
      details.contains('Αποσύνδεση εξοπλισμ')) {
    return true;
  }
  final oldMap = _v35DecodeJsonMap(row['old_values_json'] as String?);
  final newMap = _v35DecodeJsonMap(row['new_values_json'] as String?);
  return oldMap?.containsKey('linked_phone_numbers') == true ||
      newMap?.containsKey('linked_phone_numbers') == true ||
      oldMap?.containsKey('linked_equipment') == true ||
      newMap?.containsKey('linked_equipment') == true;
}

String _v35MergeDetailsIfMissing(String? base, String? extra) {
  final b = base?.trim() ?? '';
  final e = extra?.trim() ?? '';
  if (e.isEmpty) return b;
  if (b.isEmpty) return e;
  if (b.contains(e)) return b;
  return '$b · $e';
}

Future<int> _v35CleanupSideEntityLinkRows(DatabaseExecutor txn) async {
  final rows = await txn.query(
    'audit_log',
    orderBy: 'timestamp ASC, id ASC',
  );
  if (rows.isEmpty) return 0;

  final userRows = rows.where(_v35IsUserSideLinkRow).toList();
  if (userRows.isEmpty) return 0;

  var deleted = 0;
  for (final sideRow in rows.where(_v35IsSideEntityLinkRow)) {
    final sideTs = sideRow['timestamp'] as String?;
    Map<String, Object?>? matchedUser;
    for (final userRow in userRows) {
      if (!_v35WithinMergeWindow(sideTs, userRow['timestamp'] as String?)) {
        continue;
      }
      if (sideRow['entity_type'] == AuditEntityTypes.phone) {
        final sideOld =
            _v35DecodeJsonMap(sideRow['old_values_json'] as String?);
        final sideNew =
            _v35DecodeJsonMap(sideRow['new_values_json'] as String?);
        final linkedUserId =
            sideNew?['linked_user_id'] ?? sideOld?['linked_user_id'];
        final userEntityId = userRow['entity_id'];
        if (linkedUserId != null &&
            userEntityId != null &&
            '$linkedUserId' == '$userEntityId') {
          matchedUser = userRow;
          break;
        }
      } else {
        matchedUser = userRow;
        break;
      }
    }
    if (matchedUser == null) continue;

    final sideDetails = sideRow['details'] as String?;
    final userDetails = matchedUser['details'] as String?;
    final mergedDetails = _v35MergeDetailsIfMissing(userDetails, sideDetails);
    if (mergedDetails != (userDetails ?? '')) {
      await txn.update(
        'audit_log',
        {'details': mergedDetails},
        where: 'id = ?',
        whereArgs: [_v35RowId(matchedUser)],
      );
    }

    await txn.delete(
      'audit_log',
      where: 'id = ?',
      whereArgs: [_v35RowId(sideRow)],
    );
    deleted++;
  }
  return deleted;
}

bool _v35IsRemoteParamsRemoval(
  Map<String, dynamic>? oldMap,
  Map<String, dynamic>? newMap,
) {
  if (oldMap == null || newMap == null) return false;
  if (!oldMap.containsKey('remote_params')) return false;
  if (!newMap.containsKey('remote_params')) return false;
  final oldVal = oldMap['remote_params'];
  final newVal = newMap['remote_params'];
  final oldEmpty = oldVal == null ||
      '$oldVal'.trim().isEmpty ||
      '$oldVal' == '{}' ||
      '$oldVal' == '[]';
  final newEmpty = newVal == null ||
      '$newVal'.trim().isEmpty ||
      '$newVal' == '{}' ||
      '$newVal' == '[]';
  return !oldEmpty && newEmpty;
}

bool _v35IsRemoteParamsAddition(
  Map<String, dynamic>? oldMap,
  Map<String, dynamic>? newMap,
) {
  if (oldMap == null || newMap == null) return false;
  if (!oldMap.containsKey('remote_params')) return false;
  if (!newMap.containsKey('remote_params')) return false;
  final oldVal = oldMap['remote_params'];
  final newVal = newMap['remote_params'];
  final oldEmpty = oldVal == null ||
      '$oldVal'.trim().isEmpty ||
      '$oldVal' == '{}' ||
      '$oldVal' == '[]';
  final newEmpty = newVal == null ||
      '$newVal'.trim().isEmpty ||
      '$newVal' == '{}' ||
      '$newVal' == '[]';
  return oldEmpty && !newEmpty;
}

Future<int> _v35MergeEquipmentRemoteParamsPairs(DatabaseExecutor txn) async {
  final rows = await txn.query(
    'audit_log',
    where: 'entity_type = ?',
    whereArgs: [AuditEntityTypes.equipment],
    orderBy: 'entity_id ASC, timestamp ASC, id ASC',
  );
  if (rows.length < 2) return 0;

  final byEntity = <int, List<Map<String, Object?>>>{};
  for (final row in rows) {
    if (!_v35IsModifyAction(row['action'] as String?)) continue;
    final entityId = row['entity_id'];
    if (entityId == null) continue;
    final id = entityId is int ? entityId : (entityId as num).toInt();
    byEntity.putIfAbsent(id, () => []).add(row);
  }

  var merged = 0;
  for (final group in byEntity.values) {
    if (group.length < 2) continue;
    for (var i = 0; i < group.length - 1; i++) {
      final a = group[i];
      for (var j = i + 1; j < group.length; j++) {
        final b = group[j];
        if (!_v35WithinMergeWindow(
          a['timestamp'] as String?,
          b['timestamp'] as String?,
        )) {
          continue;
        }
        final aOld = _v35DecodeJsonMap(a['old_values_json'] as String?);
        final aNew = _v35DecodeJsonMap(a['new_values_json'] as String?);
        final bOld = _v35DecodeJsonMap(b['old_values_json'] as String?);
        final bNew = _v35DecodeJsonMap(b['new_values_json'] as String?);

        Map<String, Object?>? removeRow;
        Map<String, Object?>? addRow;
        if (_v35IsRemoteParamsRemoval(aOld, aNew) &&
            _v35IsRemoteParamsAddition(bOld, bNew)) {
          removeRow = a;
          addRow = b;
        } else if (_v35IsRemoteParamsRemoval(bOld, bNew) &&
            _v35IsRemoteParamsAddition(aOld, aNew)) {
          removeRow = b;
          addRow = a;
        }
        if (removeRow == null || addRow == null) continue;

        final removeOld =
            _v35DecodeJsonMap(removeRow['old_values_json'] as String?);
        final addNew = _v35DecodeJsonMap(addRow['new_values_json'] as String?);
        final mergedOld = <String, dynamic>{
          if (removeOld != null) 'remote_params': removeOld['remote_params'],
        };
        final mergedNew = <String, dynamic>{
          if (addNew != null) 'remote_params': addNew['remote_params'],
        };
        final entityId = removeRow['entity_id'] as int?;
        final keepId = _v35RowId(removeRow);
        final deleteId = _v35RowId(addRow);
        final details = AuditDiffHelper.buildMultiChangeDetails(
          entityType: AuditEntityTypes.equipment,
          entityId: entityId ?? 0,
          oldDiff: mergedOld,
          newDiff: mergedNew,
          baseDetails: 'equipment id=${entityId ?? 0}',
        );

        await txn.update(
          'audit_log',
          {
            'old_values_json': jsonEncode(mergedOld),
            'new_values_json': jsonEncode(mergedNew),
            'details': details,
          },
          where: 'id = ?',
          whereArgs: [keepId],
        );
        await txn.delete(
          'audit_log',
          where: 'id = ?',
          whereArgs: [deleteId],
        );
        group.remove(addRow);
        merged++;
        break;
      }
    }
  }
  return merged;
}

Future<({int merged, int deleted})> _v35MergeDuplicateModifyRows(
  DatabaseExecutor txn,
) async {
  final rows = await txn.query(
    'audit_log',
    orderBy: 'entity_type ASC, entity_id ASC, timestamp ASC, id ASC',
  );
  if (rows.isEmpty) return (merged: 0, deleted: 0);

  final byEntity = <String, List<Map<String, Object?>>>{};
  for (final row in rows) {
    if (!_v35IsModifyAction(row['action'] as String?)) continue;
    final entityType = (row['entity_type'] as String?)?.trim();
    final entityId = row['entity_id'];
    if (entityType == null ||
        entityType.isEmpty ||
        entityId == null ||
        entityType == AuditEntityTypes.maintenance) {
      continue;
    }
    final key = '$entityType#$entityId';
    byEntity.putIfAbsent(key, () => []).add(row);
  }

  var merged = 0;
  var deleted = 0;
  for (final group in byEntity.values) {
    if (group.length < 2) continue;

    final clusters = <List<Map<String, Object?>>>[];
    for (final row in group) {
      var placed = false;
      for (final cluster in clusters) {
        if (_v35WithinMergeWindow(
              row['timestamp'] as String?,
              cluster.first['timestamp'] as String?,
            ) &&
            _v35GroupWithinWindow([...cluster, row])) {
          cluster.add(row);
          placed = true;
          break;
        }
      }
      if (!placed) {
        clusters.add([row]);
      }
    }

    for (final cluster in clusters) {
      if (cluster.length < 2) continue;
      cluster.sort((a, b) => _v35RowId(a).compareTo(_v35RowId(b)));
      final keep = cluster.first;
      final chain = cluster
          .map(
            (row) => (
              oldMap: _v35DecodeJsonMap(row['old_values_json'] as String?),
              newMap: _v35DecodeJsonMap(row['new_values_json'] as String?),
            ),
          )
          .toList();
      final diff = AuditDiffHelper.computeChainedDiff(chain);
      if (diff.oldDiff.isEmpty && diff.newDiff.isEmpty) continue;

      final entityType = (keep['entity_type'] as String?)?.trim() ?? '';
      final entityIdRaw = keep['entity_id'];
      final entityId = entityIdRaw is int
          ? entityIdRaw
          : (entityIdRaw as num?)?.toInt() ?? 0;
      final baseDetails = '${_v35EntityTablePrefix(entityType)} id=$entityId';
      final details = AuditDiffHelper.buildMultiChangeDetails(
        entityType: entityType,
        entityId: entityId,
        oldDiff: diff.oldDiff,
        newDiff: diff.newDiff,
        baseDetails: baseDetails,
      );

      await txn.update(
        'audit_log',
        {
          'old_values_json': jsonEncode(diff.oldDiff),
          'new_values_json': jsonEncode(diff.newDiff),
          'details': details,
        },
        where: 'id = ?',
        whereArgs: [_v35RowId(keep)],
      );

      for (var i = 1; i < cluster.length; i++) {
        await txn.delete(
          'audit_log',
          where: 'id = ?',
          whereArgs: [_v35RowId(cluster[i])],
        );
        deleted++;
      }
      merged++;
    }
  }
  return (merged: merged, deleted: deleted);
}

/// v34: μετονομασία γενικών ενεργειών audit σε ενέργειες ανά οντότητα (idempotent).
Future<void> migrateDatabaseToV34(Database db) async {
  final rows = await db.query(
    'audit_log',
    columns: ['id', 'action', 'entity_type'],
    where: "action IN ('ΤΡΟΠΟΠΟΙΗΣΗ', 'Τροποποίηση', 'τροποποίηση')",
  );
  if (rows.isEmpty) return;

  final batch = db.batch();
  var pending = 0;
  for (final row in rows) {
    final idRaw = row['id'];
    if (idRaw == null) continue;
    final id = idRaw is int ? idRaw : (idRaw as num).toInt();
    final entityType = row['entity_type'] as String?;
    final next = AuditActions.modifyActionForEntityType(entityType);
    if (next == null) continue;
    batch.update(
      'audit_log',
      {'action': next},
      where: 'id = ? AND action IN (?, ?, ?)',
      whereArgs: [id, 'ΤΡΟΠΟΠΟΙΗΣΗ', 'Τροποποίηση', 'τροποποίηση'],
    );
    pending++;
  }
  if (pending > 0) {
    await batch.commit(noResult: true);
  }
}

/// v33: ανακατασκευή ευρετηρίου `search_text` του audit_log (μόνο δεδομένα) —
/// καθαρίζει ετικέτες πεδίων που μπήκαν από ψευδο-αλλαγές αριθμητικών τιμών.
Future<void> migrateDatabaseToV33(Database db) async {
  await AuditService.migrateRebuildAuditSearchTextIndex(db);
}

/// v32: κανονικοποίηση παλιών εγγραφών audit «συσχέτιση από κλήση: …» (μόνο δεδομένα).
Future<void> migrateDatabaseToV32(Database db) async {
  const legacyPrefix = 'συσχέτιση από κλήση:';
  final rows = await db.query(
    'audit_log',
    columns: ['id', 'action', 'details'],
    where: 'action LIKE ?',
    whereArgs: ['$legacyPrefix%'],
  );
  if (rows.isEmpty) return;

  final batch = db.batch();
  var pending = 0;
  for (final row in rows) {
    final idRaw = row['id'];
    if (idRaw == null) continue;
    final id = idRaw is int ? idRaw : (idRaw as num).toInt();
    final action = (row['action'] as String?) ?? '';
    final normalized = normalizeLegacyCallAssociationAuditRow(
      action: action,
      details: row['details'] as String?,
    );
    if (normalized == null) continue;
    batch.update(
      'audit_log',
      {
        'action': normalized.action,
        'details': normalized.details,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    pending++;
  }
  if (pending > 0) {
    await batch.commit(noResult: true);
  }
}

/// Αρχείο με νεότερο user_version (π.χ. 17) ενώ η εφαρμογή αναμένει squashed v1.
Future<void> onDatabaseDowngradeSquashed(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  throw DatabaseInitException(
    DatabaseInitResult(
      status: DatabaseStatus.applicationError,
      message: schemaVersionMismatchUserMessage(db, oldVersion, newVersion),
    ),
  );
}

/// Πίνακας προσωπικών λέξεων ορθογραφίας (Windows / custom lexicon).
Future<void> migrateUserDictionaryTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS user_dictionary (
        word TEXT PRIMARY KEY
      )
    ''');
}

/// v8: στήλη `language` + backfill με [DictionaryRepository.detectDictionaryLanguage].
Future<void> migrateUserDictionaryLanguageColumn(Database db) async {
  final info = await db.rawQuery(
    'PRAGMA table_info(${AppConfig.userDictionaryTable})',
  );
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('language')) {
    await db.execute(
      'ALTER TABLE ${AppConfig.userDictionaryTable} ADD COLUMN language TEXT',
    );
  }
  final rows = await db.query(
    AppConfig.userDictionaryTable,
    columns: ['word', 'language'],
  );
  final batch = db.batch();
  var pending = 0;
  for (final r in rows) {
    final w = (r['word'] as String?)?.trim() ?? '';
    if (w.isEmpty) continue;
    final next = DictionaryRepository.detectDictionaryLanguage(w);
    final cur = r['language'] as String? ?? '';
    if (cur == next) continue;
    batch.update(
      AppConfig.userDictionaryTable,
      {'language': next},
      where: 'word = ?',
      whereArgs: [w],
    );
    pending++;
  }
  if (pending > 0) await batch.commit(noResult: true);
}

/// v9: `letters_count`, `diacritic_mark_count` + backfill + ευρετήρια.
Future<void> migrateLexiconWordMetricsColumns(Database db) async {
  Future<void> ensureColumns(String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final names = info.map((r) => r['name'] as String).toSet();
    if (!names.contains('letters_count')) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN letters_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!names.contains('diacritic_mark_count')) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN diacritic_mark_count INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  await ensureColumns(AppConfig.fullDictionaryTable);
  await ensureColumns(AppConfig.userDictionaryTable);

  Future<void> backfillTable(String table, {required bool hasRowId}) async {
    final rows = await db.query(
      table,
      columns: hasRowId ? ['id', 'word'] : ['word'],
    );
    const chunk = 400;
    for (var i = 0; i < rows.length; i += chunk) {
      final end = (i + chunk > rows.length) ? rows.length : i + chunk;
      final slice = rows.sublist(i, end);
      final batch = db.batch();
      for (final r in slice) {
        final w = (r['word'] as String?) ?? '';
        final m = LexiconWordMetrics.compute(w);
        if (hasRowId) {
          final idRaw = r['id'];
          final id = idRaw is int ? idRaw : (idRaw as num).toInt();
          batch.update(
            table,
            {
              'letters_count': m.lettersCount,
              'diacritic_mark_count': m.diacriticMarkCount,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          batch.update(
            table,
            {
              'letters_count': m.lettersCount,
              'diacritic_mark_count': m.diacriticMarkCount,
            },
            where: 'word = ?',
            whereArgs: [w],
          );
        }
      }
      await batch.commit(noResult: true);
    }
  }

  await backfillTable(AppConfig.fullDictionaryTable, hasRowId: true);
  await backfillTable(AppConfig.userDictionaryTable, hasRowId: false);

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_full_dictionary_letters_count ON ${AppConfig.fullDictionaryTable}(letters_count)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_full_dictionary_diacritic_mark_count ON ${AppConfig.fullDictionaryTable}(diacritic_mark_count)',
  );
}

/// Πίνακας master λεξικού (v7).
Future<void> migrateFullDictionaryTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS full_dictionary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL UNIQUE,
        normalized_word TEXT NOT NULL,
        source TEXT NOT NULL,
        language TEXT NOT NULL,
        category TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_full_dictionary_norm ON full_dictionary(normalized_word)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_full_dictionary_filters ON full_dictionary(language, source, category)',
  );
}

/// v10: στήλη `equipment.remote_params` για JSON παραμέτρων ανά εργαλείο.
Future<void> migrateEquipmentRemoteParamsColumn(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(equipment)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('remote_params')) {
    await db.execute('ALTER TABLE equipment ADD COLUMN remote_params TEXT');
  }
}

/// Προσθέτει στήλες τμήμα/τοποθεσία στον πίνακα `equipment` αν λείπουν (idempotent).
Future<void> migrateEquipmentDepartmentLocationColumns(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(equipment)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('department_id')) {
    await db.execute(
      'ALTER TABLE equipment ADD COLUMN department_id INTEGER',
    );
  }
  if (!names.contains('location')) {
    await db.execute('ALTER TABLE equipment ADD COLUMN location TEXT');
  }
}

/// Δημιουργεί πίνακα `department_phones` αν λείπει (idempotent).
Future<void> migrateDepartmentPhonesTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS department_phones (
        department_id INTEGER NOT NULL,
        phone_id INTEGER NOT NULL,
        PRIMARY KEY (department_id, phone_id)
      )
    ''');
}

const String _kDepartmentsNameKeyColumn = 'name_key';

/// Προσθέτει `departments.name_key` και το γεμίζει για υπάρχουσες εγγραφές.
Future<void> migrateDepartmentNameKey(Database db) async {
  const tableName = 'departments';
  final info = await db.rawQuery('PRAGMA table_info($tableName)');
  if (info.isEmpty) {
    throw Exception(
      'Μετάβαση σχήματος: δεν υπάρχει ο πίνακας `$tableName` (PRAGMA table_info '
      'επέστρεψε κενό). no such table: $tableName',
    );
  }
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains(_kDepartmentsNameKeyColumn)) {
    const stmt = 'ALTER TABLE departments ADD COLUMN name_key TEXT';
    try {
      await db.execute(stmt);
    } catch (e) {
      throw Exception(
        'Μετάβαση σχήματος απέτυχε: πίνακας `$tableName`, εντολή: `$stmt`. $e',
      );
    }
  }

  final rows = await db.query(
    'departments',
    columns: ['id', 'name', 'name_key'],
  );
  for (final r in rows) {
    final id = r['id'] as int?;
    if (id == null) continue;
    final existing = (r['name_key'] as String?)?.trim() ?? '';
    if (existing.isNotEmpty) continue;
    final name = (r['name'] as String?)?.trim() ?? '';
    final key = SearchTextNormalizer.normalizeForSearch(name);
    if (key.isEmpty) continue;
    await db.update(
      'departments',
      {_kDepartmentsNameKeyColumn: key},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_departments_name_key ON departments(name_key)',
  );
}

/// Προσθέτει `phones.department_id` για πολιτική shared-location.
Future<void> migratePhonesDepartmentColumn(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(phones)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('department_id')) {
    await db.execute('ALTER TABLE phones ADD COLUMN department_id INTEGER');
  }
}
