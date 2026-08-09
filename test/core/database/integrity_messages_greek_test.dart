import 'package:call_logger/core/database/database_table_labels.dart';
import 'package:call_logger/features/database/models/database_integrity_finding.dart';
import 'package:call_logger/features/database/models/database_integrity_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ονόματα πινάκων και στηλών που δεν επιτρέπεται να φτάσουν στον χρήστη.
const List<String> _technicalTerms = [
  'search_index',
  'search_text',
  'department_id',
  'call_id',
  'user_id',
  'phone_id',
  'equipment_id',
  'floor_id',
  'category_id',
  'entity_type',
  'name_key',
  'created_at',
  'updated_at',
  'is_deleted',
  'department_phones',
  'user_phones',
  'user_equipment',
  'call_external_links',
  'building_map_floors',
  'audit_log',
  'app_settings',
  'id=',
];

/// Ρητή εξαίρεση: το εύρημα των σχέσεων δείχνει σκόπιμα τον τεχνικό όρο δίπλα
/// στο ελληνικό όνομα, ώστε να παραμένει διαγνώσιμο.
const _typesAllowedTechnicalNames = {IntegrityCheckType.foreignKeyViolations};

List<String> _offendingTermsIn(String text) =>
    [for (final t in _technicalTerms) if (text.contains(t)) t];

void main() {
  group('Τίτλοι ομάδων Ελέγχου Ακεραιότητας', () {
    test('κανένας δεν κουβαλά όνομα πίνακα ή στήλης', () {
      final offenders = <String>[];
      for (final type in IntegrityCheckType.values) {
        final label = type.displayNameEl;
        for (final term in _offendingTermsIn(label)) {
          offenders.add('${type.name} → «$label» ($term)');
        }
      }

      expect(offenders, isEmpty);
    });

    test('κάθε τύπος ελέγχου έχει δικό του ελληνικό όνομα', () {
      for (final type in IntegrityCheckType.values) {
        expect(type.displayNameEl, isNot(type.name));
        expect(type.displayNameEl.trim(), isNotEmpty);
      }
    });
  });

  group('Λεξιλόγιο πινάκων', () {
    test('κάθε πίνακας του σχήματος έχει ελληνικό όνομα', () {
      const schemaTables = [
        'calls',
        'tasks',
        'users',
        'phones',
        'departments',
        'equipment',
        'categories',
        'user_phones',
        'user_equipment',
        'department_phones',
        'call_external_links',
        'building_map_floors',
        'audit_log',
        'app_settings',
        'remote_tools',
        'remote_tool_args',
        'full_dictionary',
        'user_dictionary',
        'knowledge_base',
      ];

      final untranslated = [
        for (final t in schemaTables)
          if (databaseTableLabelEl(t) == t) t,
      ];

      expect(untranslated, isEmpty);
    });

    test('άγνωστος πίνακας επιστρέφεται ως έχει, δεν εξαφανίζεται', () {
      expect(databaseTableLabelEl('κάτι_άγνωστο'), 'κάτι_άγνωστο');
      expect(databaseTableLabelEl(null), '—');
    });

    test('η μορφή με τεχνικό όρο κρατά και τα δύο ονόματα', () {
      expect(
        databaseTableLabelWithTechnicalEl('departments'),
        'Τμήματα (departments)',
      );
      // Άγνωστος πίνακας: χωρίς διπλή αναφορά του ίδιου ονόματος.
      expect(databaseTableLabelWithTechnicalEl('κάτι'), 'κάτι');
    });
  });

  group('Λεξιλόγιο οντοτήτων ιστορικού', () {
    test('κάθε τύπος οντότητας έχει ελληνικό όνομα', () {
      const types = [
        'user',
        'department',
        'equipment',
        'category',
        'task',
        'call',
        'phone',
        'bulk_users',
        'bulk_departments',
        'bulk_equipment',
        'import_data',
        'maintenance',
        'backup',
      ];

      final untranslated = [
        for (final t in types)
          if (databaseEntityTypeLabelEl(t) == t) t,
      ];

      expect(untranslated, isEmpty);
    });
  });

  group('Ετικέτα οντότητας ευρήματος', () {
    test('περνά από το κοινό λεξιλόγιο', () {
      expect(
        DatabaseIntegrityReport.entityLabelEl('department_phones'),
        'Συσχέτιση τμήματος–τηλεφώνου',
      );
      expect(
        DatabaseIntegrityReport.entityLabelEl('building_map_floors'),
        'Όροφοι χάρτη κτιρίου',
      );
    });
  });

  group('Εξαίρεση για τα διαγνωστικά ευρήματα σχέσεων', () {
    test('μόνο οι παραβιάσεις σχέσεων δείχνουν τεχνικό όνομα', () {
      // Ο κανόνας γράφεται ρητά ώστε μια μελλοντική προσθήκη να μην τον
      // παρακάμψει σιωπηλά.
      expect(_typesAllowedTechnicalNames, hasLength(1));
      expect(
        _typesAllowedTechnicalNames.single,
        IntegrityCheckType.foreignKeyViolations,
      );
    });
  });
}
