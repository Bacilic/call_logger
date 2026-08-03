// Αναγνώσεις για τη σύνοψη μαζικής διαγραφής εξοπλισμού.
//
// Ζει εδώ γιατί εδώ ζει το SQL — ο κανόνας δεν κάμπτεται από το ότι τα
// ερωτήματα εξυπηρετούν έναν μόνο διάλογο. Το «σταθερός αριθμός ερωτημάτων
// ανεξάρτητα από το πλήθος των επιλεγμένων» είναι τρόπος **γραφής** του
// ερωτήματος, όχι λόγος να φύγει από το repository: το chunking ζει κι αυτό εδώ.

import 'package:sqflite_common/sqflite.dart';

import '../../features/directory/services/equipment_deletion_summary.dart';
import 'directory_support.dart';

/// Μέγιστα ids ανά ερώτημα `IN (...)`.
///
/// Το SQLite έχει σκληρό όριο παραμέτρων ανά δήλωση (999 στις προεπιλεγμένες
/// ρυθμίσεις). Με «επιλογή όλων» σε μεγάλο κατάλογο, ένα ενιαίο `IN` θα έσκαγε
/// — τα ids σπάνε σε ομάδες και τα αποτελέσματα ενώνονται.
const int _kMaxIdsPerQuery = 400;

Iterable<List<T>> _chunked<T>(List<T> items) sync* {
  for (var i = 0; i < items.length; i += _kMaxIdsPerQuery) {
    yield items.sublist(
      i,
      i + _kMaxIdsPerQuery > items.length ? items.length : i + _kMaxIdsPerQuery,
    );
  }
}

String _placeholders(int count) => List<String>.filled(count, '?').join(', ');

String? _ownerDisplayName(Map<String, dynamic> snapshot) {
  final first = (snapshot['first_name'] as String?)?.trim() ?? '';
  final last = (snapshot['last_name'] as String?)?.trim() ?? '';
  final name = '$first $last'.trim();
  return name.isEmpty ? null : name;
}

DateTime? _timestampOf(Map<String, dynamic> row, String column) {
  final raw = row[column]?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

DateTime? _laterOf(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}

/// Φορτώνει περίληψη διαγραφής για τα δοσμένα ids εξοπλισμού (σειρά εισόδου).
///
/// Σταθερός αριθμός ερωτημάτων ανά ομάδα των 400 — όχι ανά εξοπλισμό. Με 30
/// επιλεγμένους ο παλιός βρόχος έκανε πάνω από εκατό ερωτήματα, και γι' αυτό ο
/// διάλογος δεν τολμούσε να δείξει λεπτομέρειες πάνω από πέντε.
Future<List<EquipmentDeletionSummary>> deletionSummaries(
  Database db,
  List<int> equipmentIds,
) async {
  if (equipmentIds.isEmpty) return const [];

  final codeById = <int, String>{};
  final departmentIdByEquipment = <int, int>{};
  final ownerByEquipment = <int, Map<String, dynamic>>{};
  final callsByEquipment = <int, int>{};
  final lastCallByEquipment = <int, DateTime?>{};
  final tasksByEquipment = <int, int>{};
  final lastTaskByEquipment = <int, DateTime?>{};

  for (final chunk in _chunked(equipmentIds)) {
    final marks = _placeholders(chunk.length);

    final codeRows = await db.rawQuery('''
      SELECT id, code_equipment, department_id FROM equipment WHERE id IN ($marks)
      ''', chunk);
    for (final row in codeRows) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final raw = (row['code_equipment'] as String?)?.trim() ?? '';
      codeById[id] = raw.isEmpty ? id.toString() : raw;
      final deptId = row['department_id'] as int?;
      if (deptId != null) departmentIdByEquipment[id] = deptId;
    }

    // Πρώτος κάτοχος ανά εξοπλισμό, με σταθερή αλφαβητική σειρά.
    final ownerRows = await db.rawQuery('''
      SELECT ue.equipment_id AS eid, u.id AS uid,
             u.first_name AS first_name, u.last_name AS last_name
      FROM user_equipment ue
      JOIN users u ON u.id = ue.user_id AND COALESCE(u.is_deleted, 0) = 0
      WHERE ue.equipment_id IN ($marks)
      ORDER BY u.last_name COLLATE NOCASE ASC, u.first_name COLLATE NOCASE ASC
      ''', chunk);
    for (final row in ownerRows) {
      final eid = row['eid'] as int?;
      if (eid == null || ownerByEquipment.containsKey(eid)) continue;
      ownerByEquipment[eid] = row;
    }

    final callRows = await db.rawQuery('''
      SELECT equipment_id AS eid, COUNT(*) AS c, MAX(date) AS last_at
      FROM calls
      WHERE equipment_id IN ($marks) AND ${DirectorySupport.notDeletedClause}
      GROUP BY equipment_id
      ''', chunk);
    for (final row in callRows) {
      final eid = row['eid'] as int?;
      if (eid == null) continue;
      callsByEquipment[eid] = (row['c'] as int?) ?? 0;
      lastCallByEquipment[eid] = _timestampOf(row, 'last_at');
    }

    final taskRows = await db.rawQuery('''
      SELECT equipment_id AS eid, COUNT(*) AS c,
             MAX(COALESCE(updated_at, created_at)) AS last_at
      FROM tasks
      WHERE equipment_id IN ($marks) AND ${DirectorySupport.notDeletedClause}
      GROUP BY equipment_id
      ''', chunk);
    for (final row in taskRows) {
      final eid = row['eid'] as int?;
      if (eid == null) continue;
      tasksByEquipment[eid] = (row['c'] as int?) ?? 0;
      lastTaskByEquipment[eid] = _timestampOf(row, 'last_at');
    }
  }

  // Κλήσεις που αναφέρουν τον κωδικό ΜΟΝΟ ως κείμενο, χωρίς δεσμό. Μετράνε
  // εξίσου ως χρήση: ο εξοπλισμός δούλευε, απλώς δεν είχε καταχωρηθεί σωστά.
  final equipmentIdsByCode = <String, List<int>>{};
  for (final entry in codeById.entries) {
    equipmentIdsByCode.putIfAbsent(entry.value, () => []).add(entry.key);
  }
  final codes = equipmentIdsByCode.keys.toList();
  for (final chunk in _chunked(codes)) {
    final textRows = await db.rawQuery('''
      SELECT TRIM(COALESCE(equipment_text, '')) AS code,
             COUNT(*) AS c, MAX(date) AS last_at
      FROM calls
      WHERE ${DirectorySupport.notDeletedClause}
        AND equipment_id IS NULL
        AND TRIM(COALESCE(equipment_text, '')) IN (${_placeholders(chunk.length)})
      GROUP BY TRIM(COALESCE(equipment_text, ''))
      ''', chunk);
    for (final row in textRows) {
      final code = (row['code'] as String?)?.trim() ?? '';
      final ids = equipmentIdsByCode[code];
      if (ids == null) continue;
      final count = (row['c'] as int?) ?? 0;
      final at = _timestampOf(row, 'last_at');
      for (final id in ids) {
        callsByEquipment[id] = (callsByEquipment[id] ?? 0) + count;
        lastCallByEquipment[id] = _laterOf(lastCallByEquipment[id], at);
      }
    }
  }

  final departmentNameById = <int, String>{};
  final departmentIds = departmentIdByEquipment.values.toSet().toList();
  for (final chunk in _chunked(departmentIds)) {
    final deptRows = await db.rawQuery('''
      SELECT id, name FROM departments WHERE id IN (${_placeholders(chunk.length)})
      ''', chunk);
    for (final row in deptRows) {
      final id = row['id'] as int?;
      final name = (row['name'] as String?)?.trim() ?? '';
      if (id != null && name.isNotEmpty) departmentNameById[id] = name;
    }
  }

  final ownerIds = ownerByEquipment.values
      .map((r) => r['uid'] as int?)
      .whereType<int>()
      .toSet()
      .toList();
  final phoneByOwner = <int, String>{};
  for (final chunk in _chunked(ownerIds)) {
    final phoneRows = await db.rawQuery('''
      SELECT up.user_id AS uid, p.number AS number
      FROM user_phones up
      JOIN phones p ON p.id = up.phone_id
      WHERE up.user_id IN (${_placeholders(chunk.length)})
      ORDER BY p.number COLLATE NOCASE ASC
      ''', chunk);
    for (final row in phoneRows) {
      final uid = row['uid'] as int?;
      if (uid == null || phoneByOwner.containsKey(uid)) continue;
      final number = (row['number'] as String?)?.trim() ?? '';
      if (number.isNotEmpty) phoneByOwner[uid] = number;
    }
  }

  return [
    // Σειρά εισόδου — ο χρήστης βλέπει τα στοιχεία όπως τα επέλεξε.
    for (final id in equipmentIds)
      EquipmentDeletionSummary(
        equipmentId: id,
        code: codeById[id] ?? id.toString(),
        ownerName: ownerByEquipment[id] == null
            ? null
            : _ownerDisplayName(ownerByEquipment[id]!),
        departmentName: departmentNameById[departmentIdByEquipment[id] ?? -1],
        phone: phoneByOwner[ownerByEquipment[id]?['uid'] as int? ?? -1],
        callCount: callsByEquipment[id] ?? 0,
        taskCount: tasksByEquipment[id] ?? 0,
        lastCallAt: lastCallByEquipment[id],
        lastTaskAt: lastTaskByEquipment[id],
      ),
  ];
}
