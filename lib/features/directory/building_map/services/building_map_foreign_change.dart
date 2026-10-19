import '../../../../core/database/audit_service.dart';
import '../../../../core/utils/conflict_actor_text.dart';
import '../../models/department_model.dart';
import '../../services/directory_save_conflict.dart';

/// Άλλαξε άλλος σταθμός, στις [columns] που πάει να γράψει ο χάρτης, κάτι
/// που ο χάρτης δεν έχει δει;
///
/// Η αφετηρία είναι το τμήμα **όπως το δείχνει ο χάρτης** ([seen]): στην
/// επεξεργασία ο χάρτης δεν ανανεώνεται από άλλους σταθμούς (απόφαση
/// Διευθυντή 25/08/2026), οπότε η εικόνα του μένει όσο την είδε ο χρήστης.
///
/// Και οι δύο πλευρές περνούν από το ίδιο μοντέλο: η βάση κρατά π.χ. κενή
/// περιστροφή εκεί που ο χάρτης βλέπει 0 — χωρίς την ίδια μετατροπή, κάθε
/// τέτοια διαφορά θα έβγαινε ψεύτικη διένεξη.
/// «Ο χρήστης «Βασίλης» άλλαξε τη σχεδίαση του τμήματος «Γραφείο Κίνησης»
/// στις 15:04.» — το τμήμα ονομάζεται πάντα: στη μαζική αφαίρεση ή απόκρυψη
/// ο χρήστης έχει επιλέξει πολλά, και χωρίς όνομα δεν ξέρει ποιο αφορά.
String buildingMapConflictHeadline({
  required String departmentName,
  String? changedBy,
  DateTime? changedAt,
  required DateTime now,
}) {
  return '${conflictActorName(changedBy)} άλλαξε τη σχεδίαση του τμήματος '
      '«$departmentName»${conflictMomentSuffix(changedAt, now: now)}.';
}

DirectorySaveConflict? buildingMapForeignChange({
  required DepartmentModel seen,
  required Map<String, Object?> freshRow,
  required Iterable<String> columns,
}) {
  final asSeen = seen.toMap();
  final asStored = DepartmentModel.fromMap(freshRow).toMap();
  return DirectorySaveConflict.between(
    entityType: AuditEntityTypes.department,
    expected: {for (final c in columns) c: asSeen[c]},
    fresh: {for (final c in columns) c: asStored[c]},
    attempted: {for (final c in columns) c: null},
  );
}
