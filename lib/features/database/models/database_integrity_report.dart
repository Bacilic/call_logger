import 'package:intl/intl.dart';

import '../../../core/database/database_v1_schema.dart';
import 'database_integrity_finding.dart';

class DatabaseIntegrityReport {
  DatabaseIntegrityReport({
    required this.findings,
    DateTime? checkedAt,
    int? schemaVersion,
  })  : checkedAt = checkedAt ?? DateTime.now(),
        schemaVersion = schemaVersion ?? databaseSchemaVersionV1;

  final List<DatabaseIntegrityFinding> findings;
  final DateTime checkedAt;
  final int schemaVersion;

  bool get hasFindings => findings.isNotEmpty;

  int get criticalCount =>
      findings.where((f) => f.severity == IntegritySeverity.critical).length;

  int get warningCount =>
      findings.where((f) => f.severity == IntegritySeverity.warning).length;

  static String categoryLabelEl(IntegrityCategory category) {
    return switch (category) {
      IntegrityCategory.searchIndex => 'Ευρετήριο αναζήτησης',
      IntegrityCategory.referential => 'Αναφορές / ορφανές συσχετίσεις',
      IntegrityCategory.technicalFlow => 'Τεχνικά — λογική ροής',
      IntegrityCategory.temporal => 'Χρονικές ασυνέπειες',
    };
  }

  static String severityLabelEl(IntegritySeverity severity) {
    return switch (severity) {
      IntegritySeverity.warning => 'Προειδοποίηση',
      IntegritySeverity.critical => 'Κρίσιμο',
    };
  }

  /// Ελληνική απόδοση ονόματος πίνακα για UI / Markdown (το [tableName] παραμένει στα αγγλικά στη βάση).
  static String entityLabelEl(String? tableName) {
    if (tableName == null || tableName.isEmpty) return '—';
    return switch (tableName) {
      'user_phones' => 'Συσχέτιση χρήστη–τηλεφώνου',
      'user_equipment' => 'Συσχέτιση χρήστη–εξοπλισμού',
      'department_phones' => 'Συσχέτιση τμήματος–τηλεφώνου',
      'call_external_links' => 'Εξωτερικός σύνδεσμος κλήσης',
      'audit_log' => 'Αρχείο καταγραφής (audit)',
      'calls' => 'Κλήσεις',
      'tasks' => 'Εκκρεμότητες',
      'users' => 'Χρήστες',
      'phones' => 'Τηλέφωνα',
      'departments' => 'Τμήματα',
      'equipment' => 'Εξοπλισμός',
      _ => tableName,
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer();
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(checkedAt);

    buffer.writeln('# Έκθεση ακεραιότητας βάσης δεδομένων');
    buffer.writeln();
    buffer.writeln('- **Ημερομηνία ελέγχου:** $timestamp');
    buffer.writeln('- **Έκδοση σχήματος:** $schemaVersion');
    buffer.writeln();

    if (!hasFindings) {
      buffer.writeln('Δεν εντοπίστηκαν προβλήματα.');
      return buffer.toString();
    }

    for (final category in IntegrityCategory.values) {
      final inCategory =
          findings.where((f) => f.category == category).toList();
      if (inCategory.isEmpty) continue;

      buffer.writeln('## ${categoryLabelEl(category)}');
      buffer.writeln();

      for (final severity in IntegritySeverity.values) {
        final inSeverity =
            inCategory.where((f) => f.severity == severity).toList();
        if (inSeverity.isEmpty) continue;

        buffer.writeln('### ${severityLabelEl(severity)}');
        buffer.writeln();

        for (final finding in inSeverity) {
          buffer.writeln('- **${finding.title}**');
          buffer.writeln('  ${finding.description}');
          if (finding.affectedEntity != null || finding.affectedId != null) {
            final entity = entityLabelEl(finding.affectedEntity);
            final id = finding.affectedId?.toString() ?? '—';
            buffer.writeln('  _Οντότητα:_ $entity #$id');
          }
          buffer.writeln();
        }
      }
    }

    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('## Σύνοψη');
    buffer.writeln();
    buffer.writeln('- **Σύνολο ευρημάτων:** ${findings.length}');
    buffer.writeln('- **Κρίσιμα:** $criticalCount');
    buffer.writeln('- **Προειδοποιήσεις:** $warningCount');

    return buffer.toString();
  }
}
