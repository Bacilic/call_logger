import 'package:sqflite_common/sqflite.dart';

import '../../features/database/models/database_integrity_finding.dart';
import '../../features/database/models/database_integrity_report.dart';
import '../utils/search_text_normalizer.dart';
import 'database_helper.dart';
import 'database_v1_schema.dart';

/// Βήμα ελέγχου ακεραιότητας με count + διαγνωστικό query.
typedef _IntegrityCheckRunner = Future<List<DatabaseIntegrityFinding>> Function(
  Database db,
);

class _IntegrityCheckStep {
  const _IntegrityCheckStep({
    required this.checkType,
    required this.name,
    required this.tableScopeLabel,
    required this.countSql,
    required this.run,
  });

  final IntegrityCheckType checkType;
  final String name;
  final String tableScopeLabel;
  final String countSql;
  final _IntegrityCheckRunner run;
}

/// Read-only διαγνωστικά SQL για ακεραιότητα δεδομένων SQLite.
class DatabaseIntegrityDiagnostics {
  static const int totalSteps = 16;

  static const String _activePhones = 'COALESCE(is_deleted, 0) = 0';
  static const String _activeCalls = 'COALESCE(c.is_deleted, 0) = 0';
  static const String _activeTasks = 'COALESCE(t.is_deleted, 0) = 0';
  static const String _activeUsers = 'COALESCE(u.is_deleted, 0) = 0';

  Future<DatabaseIntegrityReport> runChecks({
    void Function(DatabaseIntegrityProgress)? onProgress,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final findings = <DatabaseIntegrityFinding>[];
    var step = 0;

    Future<void> emitProgress({
      required String checkName,
      required String tableScopeLabel,
      required int totalRowsChecked,
    }) async {
      step++;
      onProgress?.call(
        DatabaseIntegrityProgress(
          currentStep: step,
          totalSteps: totalSteps,
          currentCheckName: checkName,
          totalRowsChecked: totalRowsChecked,
          tableScopeLabel: tableScopeLabel,
        ),
      );
    }

    await emitProgress(
      checkName: IntegrityCheckType.pragmaQuickCheck.displayNameEl,
      tableScopeLabel: 'αρχείο βάσης',
      totalRowsChecked: 0,
    );
    findings.addAll(await _checkPragmaQuickCheck(db));

    final steps = _diagnosticSteps();
    for (final check in steps) {
      final countRow = await db.rawQuery(check.countSql);
      final count = (countRow.first.values.first as int?) ?? 0;
      await emitProgress(
        checkName: check.name,
        tableScopeLabel: check.tableScopeLabel,
        totalRowsChecked: count,
      );
      findings.addAll(await check.run(db));
    }

    return DatabaseIntegrityReport(
      findings: findings,
      checkedAt: DateTime.now(),
      schemaVersion: databaseSchemaVersionV1,
    );
  }

  /// Στοχευμένη επαν-επαλήθευση ενός τύπου ελέγχου (χωρίς πλήρες 16-βηματικό scan).
  Future<List<DatabaseIntegrityFinding>> runCheck(IntegrityCheckType type) async {
    final db = await DatabaseHelper.instance.database;
    if (type == IntegrityCheckType.pragmaQuickCheck) {
      return _checkPragmaQuickCheck(db);
    }
    final step = _diagnosticSteps().firstWhere((s) => s.checkType == type);
    return step.run(db);
  }

  static List<_IntegrityCheckStep> _diagnosticSteps() {
    return [
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.orphanPhone,
        name: IntegrityCheckType.orphanPhone.displayNameEl,
        tableScopeLabel: 'συνολικά τηλέφωνα',
        countSql: 'SELECT COUNT(*) FROM phones WHERE $_activePhones',
        run: _checkOrphanPhones,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.callsMissingSearchIndex,
        name: IntegrityCheckType.callsMissingSearchIndex.displayNameEl,
        tableScopeLabel: 'συνολικές κλήσεις',
        countSql: 'SELECT COUNT(*) FROM calls WHERE COALESCE(is_deleted, 0) = 0',
        run: _checkCallsMissingSearchIndex,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.tasksMissingSearchIndex,
        name: IntegrityCheckType.tasksMissingSearchIndex.displayNameEl,
        tableScopeLabel: 'συνολικές εκκρεμότητες',
        countSql: 'SELECT COUNT(*) FROM tasks WHERE COALESCE(is_deleted, 0) = 0',
        run: _checkTasksMissingSearchIndex,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.usersWithoutDepartment,
        name: IntegrityCheckType.usersWithoutDepartment.displayNameEl,
        tableScopeLabel: 'συνολικοί χρήστες',
        countSql: 'SELECT COUNT(*) FROM users WHERE COALESCE(is_deleted, 0) = 0',
        run: _checkUsersWithoutDepartment,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.usersInvalidDepartment,
        name: IntegrityCheckType.usersInvalidDepartment.displayNameEl,
        tableScopeLabel: 'χρήστες με τμήμα',
        countSql: '''
SELECT COUNT(*) FROM users
WHERE COALESCE(is_deleted, 0) = 0 AND department_id IS NOT NULL
''',
        run: _checkUsersInvalidDepartment,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.tasksInvalidCall,
        name: IntegrityCheckType.tasksInvalidCall.displayNameEl,
        tableScopeLabel: 'εκκρεμότητες με κλήση',
        countSql: '''
SELECT COUNT(*) FROM tasks
WHERE COALESCE(is_deleted, 0) = 0 AND call_id IS NOT NULL
''',
        run: _checkTasksInvalidCall,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.departmentsInvalidNameKey,
        name: IntegrityCheckType.departmentsInvalidNameKey.displayNameEl,
        tableScopeLabel: 'συνολικά τμήματα',
        countSql:
            'SELECT COUNT(*) FROM departments WHERE COALESCE(is_deleted, 0) = 0',
        run: _checkDepartmentsInvalidNameKey,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.orphanCallExternalLinks,
        name: IntegrityCheckType.orphanCallExternalLinks.displayNameEl,
        tableScopeLabel: 'call_external_links',
        countSql: 'SELECT COUNT(*) FROM call_external_links',
        run: _checkOrphanCallExternalLinks,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.orphanUserPhones,
        name: IntegrityCheckType.orphanUserPhones.displayNameEl,
        tableScopeLabel: 'συσχετίσεις χρήστη–τηλεφώνου',
        countSql: 'SELECT COUNT(*) FROM user_phones',
        run: _checkOrphanUserPhones,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.orphanDepartmentPhones,
        name: IntegrityCheckType.orphanDepartmentPhones.displayNameEl,
        tableScopeLabel: 'department_phones',
        countSql: 'SELECT COUNT(*) FROM department_phones',
        run: _checkOrphanDepartmentPhones,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.orphanUserEquipment,
        name: IntegrityCheckType.orphanUserEquipment.displayNameEl,
        tableScopeLabel: 'συσχετίσεις χρήστη–εξοπλισμού',
        countSql: 'SELECT COUNT(*) FROM user_equipment',
        run: _checkOrphanUserEquipment,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.callsDeletedLinkedEntities,
        name: IntegrityCheckType.callsDeletedLinkedEntities.displayNameEl,
        tableScopeLabel: 'κλήσεις με αναφορές',
        countSql: '''
SELECT COUNT(*) FROM calls c
WHERE $_activeCalls
  AND (c.caller_id IS NOT NULL OR c.equipment_id IS NOT NULL OR c.category_id IS NOT NULL)
''',
        run: _checkCallsDeletedLinkedEntities,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.tasksDeletedLinkedEntities,
        name: IntegrityCheckType.tasksDeletedLinkedEntities.displayNameEl,
        tableScopeLabel: 'συνολικές εκκρεμότητες',
        countSql: 'SELECT COUNT(*) FROM tasks WHERE COALESCE(is_deleted, 0) = 0',
        run: _checkTasksDeletedLinkedEntities,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.tasksTemporalInconsistency,
        name: IntegrityCheckType.tasksTemporalInconsistency.displayNameEl,
        tableScopeLabel: 'εκκρεμότητες με χρονικές στιγμές',
        countSql: '''
SELECT COUNT(*) FROM tasks t
WHERE $_activeTasks
  AND t.created_at IS NOT NULL
  AND t.updated_at IS NOT NULL
''',
        run: _checkTasksTemporalInconsistency,
      ),
      _IntegrityCheckStep(
        checkType: IntegrityCheckType.auditMissingSearchText,
        name: IntegrityCheckType.auditMissingSearchText.displayNameEl,
        tableScopeLabel: 'εγγραφές audit με entity_id',
        countSql: 'SELECT COUNT(*) FROM audit_log WHERE entity_id IS NOT NULL',
        run: _checkAuditMissingSearchText,
      ),
    ];
  }

  static Future<List<DatabaseIntegrityFinding>> _checkPragmaQuickCheck(
    Database db,
  ) async {
    final rows = await db.rawQuery('PRAGMA quick_check;');
    if (rows.isEmpty) return const [];

    final result = rows.first.values.first?.toString() ?? '';
    if (result.toLowerCase() == 'ok') return const [];

    return [
      DatabaseIntegrityFinding(
        severity: IntegritySeverity.critical,
        category: IntegrityCategory.technicalFlow,
        checkType: IntegrityCheckType.pragmaQuickCheck,
        title: 'Αποτυχία PRAGMA quick_check',
        description: result,
      ),
    ];
  }

  static Future<List<DatabaseIntegrityFinding>> _checkOrphanPhones(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
SELECT p.id, p.number
FROM phones p
WHERE $_activePhones
  AND p.department_id IS NULL
  AND NOT EXISTS (SELECT 1 FROM user_phones up WHERE up.phone_id = p.id)
  AND NOT EXISTS (SELECT 1 FROM department_phones dp WHERE dp.phone_id = p.id)
''');
    return rows
        .map(
          (r) => DatabaseIntegrityFinding(
            severity: IntegritySeverity.warning,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.orphanPhone,
            title: 'Ορφανό τηλέφωνο',
            description:
                'Το τηλέφωνο ${r['number']} δεν συνδέεται με χρήστη, τμήμα ή department_phones.',
            affectedId: r['id'] as int?,
            affectedEntity: 'phones',
            context: {'phone_id': r['id']},
          ),
        )
        .toList();
  }

  static Future<List<DatabaseIntegrityFinding>> _checkCallsMissingSearchIndex(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
SELECT c.id
FROM calls c
WHERE $_activeCalls
  AND (c.search_index IS NULL OR TRIM(c.search_index) = '')
''');
    return rows
        .map(
          (r) => DatabaseIntegrityFinding(
            severity: IntegritySeverity.warning,
            category: IntegrityCategory.searchIndex,
            checkType: IntegrityCheckType.callsMissingSearchIndex,
            title: 'Κλήση χωρίς ευρετήριο αναζήτησης',
            description: 'Η κλήση δεν έχει search_index.',
            affectedId: r['id'] as int?,
            affectedEntity: 'calls',
            context: {'call_id': r['id']},
          ),
        )
        .toList();
  }

  static Future<List<DatabaseIntegrityFinding>> _checkTasksMissingSearchIndex(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
SELECT t.id, t.title
FROM tasks t
WHERE $_activeTasks
  AND (t.search_index IS NULL OR TRIM(t.search_index) = '')
''');
    return rows
        .map(
          (r) => DatabaseIntegrityFinding(
            severity: IntegritySeverity.warning,
            category: IntegrityCategory.searchIndex,
            checkType: IntegrityCheckType.tasksMissingSearchIndex,
            title: 'Εκκρεμότητα χωρίς ευρετήριο αναζήτησης',
            description:
                'Η εκκρεμότητα «${r['title'] ?? ''}» δεν έχει search_index.',
            affectedId: r['id'] as int?,
            affectedEntity: 'tasks',
            context: {'task_id': r['id']},
          ),
        )
        .toList();
  }

  static Future<List<DatabaseIntegrityFinding>> _checkUsersWithoutDepartment(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
SELECT u.id, u.first_name, u.last_name
FROM users u
WHERE $_activeUsers
  AND u.department_id IS NULL
''');
    return rows
        .map(
          (r) => DatabaseIntegrityFinding(
            severity: IntegritySeverity.warning,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.usersWithoutDepartment,
            title: 'Χρήστης χωρίς τμήμα',
            description:
                'Ο χρήστης ${r['last_name']} ${r['first_name']} δεν έχει department_id.',
            affectedId: r['id'] as int?,
            affectedEntity: 'users',
            context: {'user_id': r['id']},
          ),
        )
        .toList();
  }

  static Future<List<DatabaseIntegrityFinding>> _checkUsersInvalidDepartment(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
SELECT u.id, u.first_name, u.last_name, u.department_id
FROM users u
LEFT JOIN departments d ON d.id = u.department_id
WHERE $_activeUsers
  AND u.department_id IS NOT NULL
  AND (d.id IS NULL OR COALESCE(d.is_deleted, 0) = 1)
''');
    return rows
        .map(
          (r) => DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.usersInvalidDepartment,
            title: 'Χρήστης με άκυρο τμήμα',
            description:
                'Ο χρήστης ${r['last_name']} ${r['first_name']} δείχνει σε ανύπαρκτο ή διαγραμμένο τμήμα (department_id=${r['department_id']}).',
            affectedId: r['id'] as int?,
            affectedEntity: 'users',
            context: {
              'user_id': r['id'],
              'department_id': r['department_id'],
            },
          ),
        )
        .toList();
  }

  static Future<List<DatabaseIntegrityFinding>> _checkTasksInvalidCall(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
SELECT t.id, t.title, t.call_id
FROM tasks t
LEFT JOIN calls c ON c.id = t.call_id
WHERE $_activeTasks
  AND t.call_id IS NOT NULL
  AND (c.id IS NULL OR COALESCE(c.is_deleted, 0) = 1)
''');
    return rows
        .map(
          (r) => DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.tasksInvalidCall,
            title: 'Εκκρεμότητα με άκυρη κλήση',
            description:
                'Η εκκρεμότητα «${r['title'] ?? ''}» δείχνει σε ανύπαρκτη ή διαγραμμένη κλήση (call_id=${r['call_id']}).',
            affectedId: r['id'] as int?,
            affectedEntity: 'tasks',
            context: {
              'task_id': r['id'],
              'call_id': r['call_id'],
              'invalidField': 'call_id',
            },
          ),
        )
        .toList();
  }

  static Future<List<DatabaseIntegrityFinding>> _checkDepartmentsInvalidNameKey(
    Database db,
  ) async {
    final findings = <DatabaseIntegrityFinding>[];

    final emptyKeyRows = await db.rawQuery('''
SELECT d.id, d.name, d.name_key
FROM departments d
WHERE COALESCE(d.is_deleted, 0) = 0
  AND (d.name_key IS NULL OR TRIM(d.name_key) = '')
''');
    for (final r in emptyKeyRows) {
      final name = r['name'] as String? ?? '';
      final expected = SearchTextNormalizer.normalizeForSearch(name);
      findings.add(
        DatabaseIntegrityFinding(
          severity: IntegritySeverity.warning,
          category: IntegrityCategory.technicalFlow,
          checkType: IntegrityCheckType.departmentsInvalidNameKey,
          title: 'Τμήμα με κενό name_key',
          description: 'Το τμήμα «$name» έχει κενό ή null name_key.',
          affectedId: r['id'] as int?,
          affectedEntity: 'departments',
          context: {
            'department_id': r['id'],
            'expectedNameKey': expected,
          },
        ),
      );
    }

    final allActive = await db.rawQuery('''
SELECT d.id, d.name, d.name_key
FROM departments d
WHERE COALESCE(d.is_deleted, 0) = 0
  AND d.name_key IS NOT NULL
  AND TRIM(d.name_key) != ''
''');
    for (final r in allActive) {
      final name = r['name'] as String? ?? '';
      final nameKey = r['name_key'] as String? ?? '';
      final expected = SearchTextNormalizer.normalizeForSearch(name);
      if (nameKey != expected) {
        findings.add(
          DatabaseIntegrityFinding(
            severity: IntegritySeverity.warning,
            category: IntegrityCategory.technicalFlow,
            checkType: IntegrityCheckType.departmentsInvalidNameKey,
            title: 'Τμήμα με μη συμβαδίζον name_key',
            description:
                'Το τμήμα «$name» έχει name_key «$nameKey» αντί για «$expected».',
            affectedId: r['id'] as int?,
            affectedEntity: 'departments',
            context: {
              'department_id': r['id'],
              'expectedNameKey': expected,
              'currentNameKey': nameKey,
            },
          ),
        );
      }
    }

    return findings;
  }

  static Future<List<DatabaseIntegrityFinding>> _checkOrphanCallExternalLinks(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
SELECT cel.id, cel.call_id
FROM call_external_links cel
LEFT JOIN calls c ON c.id = cel.call_id
WHERE c.id IS NULL OR COALESCE(c.is_deleted, 0) = 1
''');
    return rows
        .map(
          (r) => DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.orphanCallExternalLinks,
            title: 'Ορφανό call_external_link',
            description:
                'Η εγγραφή δείχνει σε ανύπαρκτη ή διαγραμμένη κλήση (call_id=${r['call_id']}).',
            affectedId: r['id'] as int?,
            affectedEntity: 'call_external_links',
            context: {
              'link_id': r['id'],
              'call_id': r['call_id'],
            },
          ),
        )
        .toList();
  }

  static Future<List<DatabaseIntegrityFinding>> _checkOrphanUserPhones(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
SELECT up.user_id, up.phone_id,
       u.first_name AS user_first_name,
       u.last_name AS user_last_name,
       p.number AS phone_number
FROM user_phones up
LEFT JOIN phones p ON p.id = up.phone_id
LEFT JOIN users u ON u.id = up.user_id
WHERE p.id IS NULL OR COALESCE(p.is_deleted, 0) = 1
   OR u.id IS NULL OR COALESCE(u.is_deleted, 0) = 1
''');
    return rows
        .map(
          (r) => DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.orphanUserPhones,
            title: 'Ορφανή συσχέτιση χρήστη–τηλεφώνου',
            description:
                'Σύνδεση υπαλλήλου ${_formatUserLabel(r['user_id'] as int?, r['user_last_name'] as String?, r['user_first_name'] as String?)} '
                'με τηλέφωνο ${_formatPhoneLabel(r['phone_id'] as int?, r['phone_number'] as String?)} '
                'δείχνει σε διαγραμμένη ή ανύπαρκτη εγγραφή.',
            affectedId: r['phone_id'] as int?,
            affectedEntity: 'user_phones',
            context: {
              'user_id': r['user_id'],
              'phone_id': r['phone_id'],
            },
          ),
        )
        .toList();
  }

  static Future<List<DatabaseIntegrityFinding>> _checkOrphanDepartmentPhones(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
SELECT dp.department_id, dp.phone_id,
       d.name AS department_name,
       p.number AS phone_number
FROM department_phones dp
LEFT JOIN departments d ON d.id = dp.department_id
LEFT JOIN phones p ON p.id = dp.phone_id
WHERE d.id IS NULL OR COALESCE(d.is_deleted, 0) = 1
   OR p.id IS NULL OR COALESCE(p.is_deleted, 0) = 1
''');
    return rows
        .map(
          (r) => DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.orphanDepartmentPhones,
            title: 'Ορφανό department_phones',
            description:
                'Σύνδεση τμήματος ${_formatDepartmentLabel(r['department_id'] as int?, r['department_name'] as String?)} '
                'με τηλέφωνο ${_formatPhoneLabel(r['phone_id'] as int?, r['phone_number'] as String?)} '
                'δείχνει σε διαγραμμένη ή ανύπαρκτη εγγραφή.',
            affectedId: r['phone_id'] as int?,
            affectedEntity: 'department_phones',
            context: {
              'department_id': r['department_id'],
              'phone_id': r['phone_id'],
            },
          ),
        )
        .toList();
  }

  static Future<List<DatabaseIntegrityFinding>> _checkOrphanUserEquipment(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
SELECT ue.user_id, ue.equipment_id,
       u.first_name AS user_first_name,
       u.last_name AS user_last_name,
       e.code_equipment
FROM user_equipment ue
LEFT JOIN users u ON u.id = ue.user_id
LEFT JOIN equipment e ON e.id = ue.equipment_id
WHERE u.id IS NULL OR COALESCE(u.is_deleted, 0) = 1
   OR e.id IS NULL OR COALESCE(e.is_deleted, 0) = 1
''');
    return rows
        .map(
          (r) => DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.orphanUserEquipment,
            title: 'Ορφανή συσχέτιση χρήστη–εξοπλισμού',
            description:
                'Σύνδεση υπαλλήλου ${_formatUserLabel(r['user_id'] as int?, r['user_last_name'] as String?, r['user_first_name'] as String?)} '
                'με εξοπλισμό ${_formatEquipmentLabel(r['equipment_id'] as int?, r['code_equipment'] as String?)} '
                'δείχνει σε διαγραμμένη ή ανύπαρκτη εγγραφή.',
            affectedId: r['equipment_id'] as int?,
            affectedEntity: 'user_equipment',
            context: {
              'user_id': r['user_id'],
              'equipment_id': r['equipment_id'],
            },
          ),
        )
        .toList();
  }

  static Future<List<DatabaseIntegrityFinding>> _checkCallsDeletedLinkedEntities(
    Database db,
  ) async {
    // Soft-deleted αναφορές (is_deleted=1) ΔΕΝ είναι εύρημα — αποτελούν
    // «ιστορική αλήθεια» και εμφανίζονται με σήμανση «(διαγραμμένο)» στο UI.
    // Εύρημα είναι μόνο όταν η εγγραφή ΛΕΙΠΕΙ εντελώς από τον πίνακα.
    final rows = await db.rawQuery('''
SELECT c.id,
       c.caller_id,
       c.equipment_id,
       c.category_id,
       CASE WHEN c.caller_id IS NOT NULL AND u.id IS NULL
            THEN 1 ELSE 0 END AS caller_invalid,
       CASE WHEN c.equipment_id IS NOT NULL AND e.id IS NULL
            THEN 1 ELSE 0 END AS equipment_invalid,
       CASE WHEN c.category_id IS NOT NULL AND cat.id IS NULL
            THEN 1 ELSE 0 END AS category_invalid
FROM calls c
LEFT JOIN users u ON u.id = c.caller_id
LEFT JOIN equipment e ON e.id = c.equipment_id
LEFT JOIN categories cat ON cat.id = c.category_id
WHERE $_activeCalls
  AND (
    (c.caller_id IS NOT NULL AND u.id IS NULL)
    OR (c.equipment_id IS NOT NULL AND e.id IS NULL)
    OR (c.category_id IS NOT NULL AND cat.id IS NULL)
  )
''');

    final findings = <DatabaseIntegrityFinding>[];
    for (final r in rows) {
      final callId = r['id'] as int;
      if ((r['caller_invalid'] as int?) == 1) {
        final callerId = r['caller_id'] as int?;
        findings.add(
          DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.callsDeletedLinkedEntities,
            title: 'Κλήση με ανύπαρκτη αναφορά (υπάλληλος)',
            description:
                'Η κλήση αναφέρεται σε υπάλληλο (id=$callerId) που λείπει εντελώς από τη βάση.',
            affectedId: callId,
            affectedEntity: 'calls',
            context: {
              'call_id': callId,
              'invalidField': 'caller_id',
              'invalidFkId': callerId,
            },
          ),
        );
      }
      if ((r['equipment_invalid'] as int?) == 1) {
        final equipmentId = r['equipment_id'] as int?;
        findings.add(
          DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.callsDeletedLinkedEntities,
            title: 'Κλήση με ανύπαρκτη αναφορά (εξοπλισμός)',
            description:
                'Η κλήση αναφέρεται σε εξοπλισμό (id=$equipmentId) που λείπει εντελώς από τη βάση.',
            affectedId: callId,
            affectedEntity: 'calls',
            context: {
              'call_id': callId,
              'invalidField': 'equipment_id',
              'invalidFkId': equipmentId,
            },
          ),
        );
      }
      if ((r['category_invalid'] as int?) == 1) {
        final categoryId = r['category_id'] as int?;
        findings.add(
          DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.callsDeletedLinkedEntities,
            title: 'Κλήση με ανύπαρκτη αναφορά (κατηγορία)',
            description:
                'Η κλήση αναφέρεται σε κατηγορία (id=$categoryId) που λείπει εντελώς από τη βάση.',
            affectedId: callId,
            affectedEntity: 'calls',
            context: {
              'call_id': callId,
              'invalidField': 'category_id',
              'invalidFkId': categoryId,
            },
          ),
        );
      }
    }
    return findings;
  }

  static Future<List<DatabaseIntegrityFinding>> _checkTasksDeletedLinkedEntities(
    Database db,
  ) async {
    // Soft-deleted αναφορές ΔΕΝ είναι εύρημα (ιστορική αλήθεια, σήμανση
    // «(διαγραμμένο)» στο UI). Εύρημα μόνο όταν η εγγραφή λείπει εντελώς.
    final rows = await db.rawQuery('''
SELECT t.id, t.title,
       t.caller_id, t.equipment_id, t.department_id, t.phone_id,
       CASE WHEN t.caller_id IS NOT NULL AND u.id IS NULL
            THEN 1 ELSE 0 END AS caller_invalid,
       CASE WHEN t.equipment_id IS NOT NULL AND e.id IS NULL
            THEN 1 ELSE 0 END AS equipment_invalid,
       CASE WHEN t.department_id IS NOT NULL AND d.id IS NULL
            THEN 1 ELSE 0 END AS department_invalid,
       CASE WHEN t.phone_id IS NOT NULL AND p.id IS NULL
            THEN 1 ELSE 0 END AS phone_invalid
FROM tasks t
LEFT JOIN users u ON u.id = t.caller_id
LEFT JOIN equipment e ON e.id = t.equipment_id
LEFT JOIN departments d ON d.id = t.department_id
LEFT JOIN phones p ON p.id = t.phone_id
WHERE $_activeTasks
  AND (
    (t.caller_id IS NOT NULL AND u.id IS NULL)
    OR (t.equipment_id IS NOT NULL AND e.id IS NULL)
    OR (t.department_id IS NOT NULL AND d.id IS NULL)
    OR (t.phone_id IS NOT NULL AND p.id IS NULL)
  )
''');

    final findings = <DatabaseIntegrityFinding>[];
    for (final r in rows) {
      final taskId = r['id'] as int;
      final title = r['title'] as String? ?? '';
      if ((r['caller_invalid'] as int?) == 1) {
        final callerId = r['caller_id'] as int?;
        findings.add(
          DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.tasksDeletedLinkedEntities,
            title: 'Εκκρεμότητα με ανύπαρκτη αναφορά (υπάλληλος)',
            description:
                'Η εκκρεμότητα «$title» αναφέρεται σε υπάλληλο (id=$callerId) που λείπει εντελώς από τη βάση.',
            affectedId: taskId,
            affectedEntity: 'tasks',
            context: {
              'task_id': taskId,
              'invalidField': 'caller_id',
              'invalidFkId': callerId,
            },
          ),
        );
      }
      if ((r['equipment_invalid'] as int?) == 1) {
        final equipmentId = r['equipment_id'] as int?;
        findings.add(
          DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.tasksDeletedLinkedEntities,
            title: 'Εκκρεμότητα με ανύπαρκτη αναφορά (εξοπλισμός)',
            description:
                'Η εκκρεμότητα «$title» αναφέρεται σε εξοπλισμό (id=$equipmentId) που λείπει εντελώς από τη βάση.',
            affectedId: taskId,
            affectedEntity: 'tasks',
            context: {
              'task_id': taskId,
              'invalidField': 'equipment_id',
              'invalidFkId': equipmentId,
            },
          ),
        );
      }
      if ((r['department_invalid'] as int?) == 1) {
        final departmentId = r['department_id'] as int?;
        findings.add(
          DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.tasksDeletedLinkedEntities,
            title: 'Εκκρεμότητα με ανύπαρκτη αναφορά (τμήμα)',
            description:
                'Η εκκρεμότητα «$title» αναφέρεται σε τμήμα (id=$departmentId) που λείπει εντελώς από τη βάση.',
            affectedId: taskId,
            affectedEntity: 'tasks',
            context: {
              'task_id': taskId,
              'invalidField': 'department_id',
              'invalidFkId': departmentId,
            },
          ),
        );
      }
      if ((r['phone_invalid'] as int?) == 1) {
        final phoneId = r['phone_id'] as int?;
        findings.add(
          DatabaseIntegrityFinding(
            severity: IntegritySeverity.critical,
            category: IntegrityCategory.referential,
            checkType: IntegrityCheckType.tasksDeletedLinkedEntities,
            title: 'Εκκρεμότητα με ανύπαρκτη αναφορά (τηλέφωνο)',
            description:
                'Η εκκρεμότητα «$title» αναφέρεται σε τηλέφωνο (id=$phoneId) που λείπει εντελώς από τη βάση.',
            affectedId: taskId,
            affectedEntity: 'tasks',
            context: {
              'task_id': taskId,
              'invalidField': 'phone_id',
              'invalidFkId': phoneId,
            },
          ),
        );
      }
    }
    return findings;
  }

  static Future<List<DatabaseIntegrityFinding>> _checkTasksTemporalInconsistency(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
SELECT t.id, t.title, t.created_at, t.updated_at
FROM tasks t
WHERE $_activeTasks
  AND t.created_at IS NOT NULL
  AND t.updated_at IS NOT NULL
  AND t.created_at > t.updated_at
''');
    return rows
        .map(
          (r) => DatabaseIntegrityFinding(
            severity: IntegritySeverity.warning,
            category: IntegrityCategory.temporal,
            checkType: IntegrityCheckType.tasksTemporalInconsistency,
            title: 'Εκκρεμότητα: created_at > updated_at',
            description:
                'Η εκκρεμότητα «${r['title'] ?? ''}» έχει created_at (${r['created_at']}) μεταγενέστερο από updated_at (${r['updated_at']}).',
            affectedId: r['id'] as int?,
            affectedEntity: 'tasks',
            context: {'task_id': r['id']},
          ),
        )
        .toList();
  }

  static Future<List<DatabaseIntegrityFinding>> _checkAuditMissingSearchText(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
SELECT a.id, a.entity_type, a.entity_id
FROM audit_log a
WHERE a.entity_id IS NOT NULL
  AND (a.search_text IS NULL OR TRIM(a.search_text) = '')
''');
    return rows
        .map(
          (r) => DatabaseIntegrityFinding(
            severity: IntegritySeverity.warning,
            category: IntegrityCategory.searchIndex,
            checkType: IntegrityCheckType.auditMissingSearchText,
            title: 'Audit χωρίς search_text',
            description:
                'Η εγγραφή audit για ${r['entity_type']} #${r['entity_id']} δεν έχει search_text.',
            affectedId: r['id'] as int?,
            affectedEntity: 'audit_log',
            context: {
              'audit_id': r['id'],
              'entity_type': r['entity_type'],
              'entity_id': r['entity_id'],
            },
          ),
        )
        .toList();
  }

  static String _formatPersonName(String? lastName, String? firstName) {
    final parts = <String>[
      if (lastName != null && lastName.trim().isNotEmpty) lastName.trim(),
      if (firstName != null && firstName.trim().isNotEmpty) firstName.trim(),
    ];
    return parts.join(' ');
  }

  static String _formatUserLabel(int? userId, String? lastName, String? firstName) {
    if (userId == null) return 'άγνωστος υπάλληλος';
    final name = _formatPersonName(lastName, firstName);
    if (name.isNotEmpty) return '$name (id=$userId)';
    return 'υπάλληλος id=$userId';
  }

  static String _formatEquipmentLabel(int? equipmentId, String? code) {
    if (equipmentId == null) return 'άγνωστος εξοπλισμός';
    final trimmed = code?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return '$trimmed (id=$equipmentId)';
    }
    return 'εξοπλισμός id=$equipmentId';
  }

  static String _formatPhoneLabel(int? phoneId, String? number) {
    if (phoneId == null) return 'άγνωστο τηλέφωνο';
    final trimmed = number?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return '$trimmed (id=$phoneId)';
    }
    return 'τηλέφωνο id=$phoneId';
  }

  static String _formatDepartmentLabel(int? departmentId, String? name) {
    if (departmentId == null) return 'άγνωστο τμήμα';
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return '«$trimmed» (id=$departmentId)';
    }
    return 'τμήμα id=$departmentId';
  }

}
