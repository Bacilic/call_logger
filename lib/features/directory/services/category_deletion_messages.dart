import '../../../core/utils/count_phrase.dart';

/// Ο τίτλος του διαλόγου διαγραφής των επιλεγμένων κατηγοριών.
String categoryDeleteDialogTitle(int count) =>
    byCount(count, one: 'Διαγραφή κατηγορίας', many: 'Διαγραφή κατηγοριών');

/// Η ερώτηση πριν από τη διαγραφή των επιλεγμένων κατηγοριών.
String categoryDeleteConfirmMessage(int count) => byCount(
  count,
  one: 'Μόνιμη σήμανση 1 κατηγορίας ως διαγραμμένης;',
  many: 'Μόνιμη σήμανση $count κατηγοριών ως διαγραμμένων;',
);

/// Το μήνυμα μετά τη διαγραφή· τα [displayNames] (ήδη κομμένα στο μήκος
/// της οθόνης) προστίθενται μετά την άνω κάτω τελεία όταν υπάρχουν.
String categoryDeletedMessage(int count, String displayNames) {
  final sentence = byCount(
    count,
    one: 'Σημειώθηκε ως διαγραμμένη 1 κατηγορία',
    many: 'Σημειώθηκαν ως διαγραμμένες $count κατηγορίες',
  );
  return displayNames.isEmpty ? '$sentence.' : '$sentence: $displayNames';
}
