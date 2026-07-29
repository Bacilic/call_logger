import '../../../core/database/sqlite_types.dart';
import '../models/department_model.dart';
import 'bulk_action_undo_record.dart';

/// Πεδίο-στόχος του μαζικού Καθαρισμού τμημάτων.
///
/// Απόφαση Διευθυντή 29/07: ο Καθαρισμός αγγίζει **μόνο δικά του πεδία** —
/// ποτέ υπαλλήλους, εξοπλισμό ή τηλέφωνα. Αυτά δεν είναι χαρακτηριστικά του
/// τμήματος αλλά ανεξάρτητες οντότητες που το αναφέρουν· η τύχη τους
/// αποφασίζεται στον οδηγό διαγραφής τμήματος, ένα τμήμα τη φορά.
///
/// Το **Χρώμα** δεν καθαρίζεται: κάθε τμήμα καταλήγει πάντα με χρώμα (αν λείπει,
/// ανατίθεται αυτόματα στον χάρτη), άρα ο καθαρισμός θα ήταν απλώς «αλλαγή σε
/// άγνωστο χρώμα».
enum BulkDepartmentClearField { building, group, notes }

/// Τρόπος εφαρμογής μαζικών σημειώσεων τμήματος.
enum BulkDepartmentNotesMode { append, replace }

/// Στήλη του πίνακα `departments` ανά πεδίο καθαρισμού.
String bulkDepartmentClearColumn(BulkDepartmentClearField field) {
  switch (field) {
    case BulkDepartmentClearField.building:
      return 'building';
    case BulkDepartmentClearField.group:
      return 'group_name';
    case BulkDepartmentClearField.notes:
      return 'notes';
  }
}

String bulkDepartmentClearLabel(BulkDepartmentClearField field) {
  switch (field) {
    case BulkDepartmentClearField.building:
      return 'κτίριο';
    case BulkDepartmentClearField.group:
      return 'ομάδα';
    case BulkDepartmentClearField.notes:
      return 'σημειώσεις';
  }
}

/// Τρέχουσα τιμή του πεδίου καθαρισμού (για να ξεχωρίσουμε τα ήδη κενά).
String? bulkDepartmentClearValue(
  DepartmentModel d,
  BulkDepartmentClearField field,
) {
  switch (field) {
    case BulkDepartmentClearField.building:
      return d.building;
    case BulkDepartmentClearField.group:
      return d.groupName;
    case BulkDepartmentClearField.notes:
      return d.notes;
  }
}

/// Λίστα ονομάτων για μηνύματα: έως 5 ονομαστικά, μετά «+Ν ακόμη».
String bulkDepartmentNamesPreview(Iterable<DepartmentModel> departments) {
  final names = [
    for (final d in departments)
      if (d.name.trim().isNotEmpty) d.name.trim() else '—',
  ];
  if (names.isEmpty) return '';
  if (names.length <= 5) return names.join(', ');
  return '${names.take(5).join(', ')} +${names.length - 5} ακόμη';
}

/// Υπάρχουσες ομάδες, για προτάσεις στο ελεύθερο πεδίο «Ομάδα».
List<String> existingDepartmentGroups(Iterable<DepartmentModel> all) {
  final seen = <String, String>{};
  for (final d in all) {
    final g = d.groupName?.trim();
    if (g == null || g.isEmpty) continue;
    seen.putIfAbsent(g.toLowerCase(), () => g);
  }
  final list = seen.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}

// ─────────────────────────── Σχέδιο καθαρισμού ───────────────────────────

/// Σχέδιο μαζικού καθαρισμού πεδίου τμήματος.
class BulkDepartmentClearPlan {
  const BulkDepartmentClearPlan({
    required this.field,
    required this.departments,
  });

  final BulkDepartmentClearField field;

  /// Μόνο όσα έχουν πράγματι τιμή στο πεδίο (τα ήδη κενά δεν μετράνε).
  final List<DepartmentModel> departments;

  bool get hasWork => departments.isNotEmpty;
}

BulkDepartmentClearPlan buildBulkDepartmentClearPlan({
  required List<DepartmentModel> selectedDepartments,
  required BulkDepartmentClearField field,
}) {
  return BulkDepartmentClearPlan(
    field: field,
    departments: [
      for (final d in selectedDepartments)
        if (d.id != null &&
            (bulkDepartmentClearValue(d, field) ?? '').trim().isNotEmpty)
          d,
    ],
  );
}

String bulkDepartmentClearConfirmationText(BulkDepartmentClearPlan plan) {
  final label = bulkDepartmentClearLabel(plan.field);
  return 'Θα καθαριστεί το πεδίο «$label» από ${plan.departments.length} '
      'τμήματα: ${bulkDepartmentNamesPreview(plan.departments)}.';
}

String bulkDepartmentClearResultMessage(BulkDepartmentClearPlan plan) {
  final label = bulkDepartmentClearLabel(plan.field);
  return 'Καθαρίστηκε το πεδίο «$label» από ${plan.departments.length} τμήματα.';
}

// ─────────────────────── Βοηθητικά ανάγνωσης σε txn ───────────────────────

const _kDepartmentUndoColumns = [
  'building',
  'color',
  'notes',
  'group_name',
  'map_hidden',
];

Future<Map<String, Object?>?> _departmentSnapshotInTxn(
  DatabaseExecutor txn,
  int departmentId,
) async {
  final rows = await txn.query(
    'departments',
    columns: _kDepartmentUndoColumns,
    where: 'id = ?',
    whereArgs: [departmentId],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return {for (final c in _kDepartmentUndoColumns) c: rows.first[c]};
}

// ─────────────────────── Εφαρμογές σε μία συναλλαγή ───────────────────────

/// Μαζική εγγραφή απλής στήλης τμήματος (κτίριο, χρώμα, ομάδα, σημειώσεις,
/// απόκρυψη χάρτη) ΜΕΣΑ στο [txn].
Future<BulkActionUndoRecord> applyBulkDepartmentFieldInTxn(
  DatabaseExecutor txn, {
  required List<DepartmentModel> departments,
  required String column,
  required Object? value,
  BulkDepartmentNotesMode? notesMode,
}) async {
  if (departments.isEmpty) return const BulkActionUndoRecord();
  final fieldsBefore = <int, Map<String, Object?>>{};

  for (final d in departments) {
    final id = d.id;
    if (id == null) continue;
    final snapshot = await _departmentSnapshotInTxn(txn, id);
    if (snapshot == null) continue;
    fieldsBefore[id] = snapshot;

    Object? next = value;
    if (notesMode == BulkDepartmentNotesMode.append) {
      final before = (snapshot[column] as String?)?.trim() ?? '';
      final addition = (value as String?)?.trim() ?? '';
      next = before.isEmpty ? addition : '$before\n$addition';
    }
    await txn.update(
      'departments',
      {column: next},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  return BulkActionUndoRecord(departmentFieldsBefore: fieldsBefore);
}

/// Μαζικός καθαρισμός πεδίου τμήματος ΜΕΣΑ στο [txn].
Future<BulkActionUndoRecord> applyBulkDepartmentClearInTxn(
  DatabaseExecutor txn,
  BulkDepartmentClearPlan plan,
) async {
  if (!plan.hasWork) return const BulkActionUndoRecord();
  return applyBulkDepartmentFieldInTxn(
    txn,
    departments: plan.departments,
    column: bulkDepartmentClearColumn(plan.field),
    value: null,
  );
}
