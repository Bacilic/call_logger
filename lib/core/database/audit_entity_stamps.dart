import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Χρονοσφραγίδες οντοτήτων καταλόγου από το Ιστορικό Εφαρμογής (audit_log):
/// πρώτη εγγραφή «ΔΗΜΙΟΥΡΓΙΑ…» = δημιουργία, τελευταία οποιαδήποτε =
/// τελευταία αλλαγή. Οι πίνακες του καταλόγου δεν κρατούν δικές τους
/// χρονοσφραγίδες — το Ιστορικό είναι η μόνη πηγή.
///
/// [involvedIdsByEntityType]: `entity_type` → σύνολο `entity_id`.
/// Κλειδί αποτελέσματος: `'<entity_type>#<entity_id>'`.
///
/// Ζει στο core/database — «SQL μόνο στα Repositories», ο αρχιτεκτονικός
/// κανόνας· οι υπηρεσίες των features δεν εκτελούν ερωτήματα.
Future<Map<String, (DateTime?, DateTime?)>> fetchAuditEntityStamps(
  Database db,
  Map<String, Set<int>> involvedIdsByEntityType,
) async {
  if (involvedIdsByEntityType.isEmpty) {
    return const <String, (DateTime?, DateTime?)>{};
  }

  final where = <String>[];
  final args = <Object?>[];
  involvedIdsByEntityType.forEach((type, ids) {
    final placeholders = List.filled(ids.length, '?').join(', ');
    where.add('(entity_type = ? AND entity_id IN ($placeholders))');
    args
      ..add(type)
      ..addAll(ids);
  });

  final rows = await db.rawQuery('''
    SELECT entity_type, entity_id,
           MIN(CASE WHEN action LIKE 'ΔΗΜΙΟΥΡΓΙΑ%' THEN timestamp END)
             AS created_at,
           MAX(timestamp) AS last_changed_at
    FROM audit_log
    WHERE ${where.join(' OR ')}
    GROUP BY entity_type, entity_id
  ''', args);

  final stamps = <String, (DateTime?, DateTime?)>{};
  for (final row in rows) {
    final key = '${row['entity_type']}#${row['entity_id']}';
    stamps[key] = (
      DateTime.tryParse(row['created_at']?.toString() ?? ''),
      DateTime.tryParse(row['last_changed_at']?.toString() ?? ''),
    );
  }
  return stamps;
}
