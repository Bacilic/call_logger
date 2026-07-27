import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ζεύγος νέου τύπου και στήλης για παλαιό `issue_type` στο `data_issues`.
class LampLegacyIssueTypeAlias {
  const LampLegacyIssueTypeAlias({
    required this.newIssueType,
    required this.newColumnName,
  });

  final String newIssueType;
  final String newColumnName;
}

/// Παλαιοί τύποι → σημερινοί τύποι/στήλες του importer.
///
/// Ο παλαιός τύπος προερχόταν από προγενέστερο ETL· ο σημερινός importer
/// γράφει `non_numeric_fk` για το ίδιο πρόβλημα. Ο χάρτης επεκτείνεται όποτε
/// βρεθεί άλλος ορφανός τύπος.
const Map<String, LampLegacyIssueTypeAlias> kLampLegacyIssueTypeAliases =
    <String, LampLegacyIssueTypeAlias>{
      'unmatched_office': LampLegacyIssueTypeAlias(
        newIssueType: 'non_numeric_fk',
        newColumnName: 'office',
      ),
    };

/// Κανονικοποιεί παλαιούς `issue_type` μέσα στη βάση.
///
/// Δεν δέχεται [BuildContext] και δεν εμφανίζει διαλόγους.
/// Διατηρεί ανέπαφα τα `row_number`, `raw_value` και `message`.
Future<int> normalizeLegacyDataIssueTypes(Database db) async {
  var totalChanged = 0;
  for (final entry in kLampLegacyIssueTypeAliases.entries) {
    final changed = await db.rawUpdate(
      'UPDATE data_issues SET issue_type = ?, column_name = ? '
      'WHERE issue_type = ?',
      <Object?>[
        entry.value.newIssueType,
        entry.value.newColumnName,
        entry.key,
      ],
    );
    totalChanged += changed;
  }
  return totalChanged;
}
