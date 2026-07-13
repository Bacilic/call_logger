import 'dart:convert';

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/audit/models/audit_log_model.dart';
import 'package:call_logger/features/audit/models/audit_reference_labels.dart';
import 'package:call_logger/features/audit/services/audit_formatter_service.dart';
import 'package:call_logger/features/database/services/database_backup_audit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Εξελληνισμός και εξανθρωπισμός Ιστορικού Εφαρμογής (Φάση 5).
void main() {
  group('audit humanization — write + display path', () {
    late Database db;
    const formatter = AuditFormatterService();

    setUpAll(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await db.execute('''
        CREATE TABLE audit_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT,
          timestamp TEXT,
          user_performing TEXT,
          details TEXT,
          entity_type TEXT,
          entity_id INTEGER,
          entity_name TEXT,
          search_text TEXT,
          old_values_json TEXT,
          new_values_json TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE app_settings (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
      await db.insert('app_settings', {
        'key': 'audit_user_performing',
        'value': 'tester',
      });
    });

    tearDown(() async {
      await db.delete('audit_log');
    });

    tearDownAll(() async {
      await db.close();
    });

    Future<AuditLogModel> insertBackupAuditRow() async {
      await AuditService.log(
        db,
        action: 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΕΠΙΤΥΧΙΑ',
        userPerforming: 'tester',
        entityType: AuditEntityTypes.backup,
        newValues: {
          'trigger': BackupAuditTrigger.manual.name,
          'trigger_el': DatabaseBackupAudit.triggerLabelEl(
            BackupAuditTrigger.manual,
          ),
          'outcome': BackupAuditOutcome.success.name,
          'destination': r'D:\Backups',
          'output_path': r'D:\Backups\call_logger_2026.zip',
          'scheduled_time': '08:00',
        },
      );
      final rows = await db.query(
        'audit_log',
        orderBy: 'id DESC',
        limit: 1,
      );
      expect(rows, isNotEmpty);
      return AuditLogModel.fromMap(rows.first);
    }

    test('(α) αντίγραφο ασφαλείας: τίτλος «N αλλαγές» με ελληνικές ετικέτες', () async {
      final row = await insertBackupAuditRow();
      final summary = formatter.summaryLine(row);
      expect(summary, isNot(contains('destination')));
      expect(summary, isNot(contains('outcome')));
      expect(summary, isNot(contains('trigger el')));
      expect(summary, contains('Προορισμός'));
      expect(summary, contains('Αποτέλεσμα'));
      expect(summary, contains('Διαδρομή αρχείου'));
      expect(summary, contains('Έναυσμα'));
      expect(summary, matches(RegExp(r'\d+ αλλαγές:')));
    });

    test('(β) remote_params: diff ανά εργαλείο, χωρίς __stash_/__exclusive_tool__', () async {
      const labels = AuditReferenceLabels(
        remoteToolNames: {1: 'VNC', 2: 'AnyDesk', 3: 'RDP'},
      );
      final row = AuditLogModel(
        id: 1,
        action: AuditActions.modifyEquipment,
        entityType: 'equipment',
        entityName: '2978',
        oldValuesJson: jsonEncode({
          'remote_params': {
            '1': '83',
            '3': '',
            '2': '',
            '__exclusive_tool__': '2',
            '__stash_1': 'hidden',
          },
        }),
        newValuesJson: jsonEncode({
          'remote_params': {
            '1': '45.rdp',
            '3': '10.0.0.5',
            '__exclusive_tool__': '2',
          },
        }),
      );
      final lines = formatter.describeChanges(row, labels: labels);
      final joined = lines.join(' ');
      expect(joined, contains('VNC: 83 → 45.rdp'));
      expect(joined, isNot(contains('__exclusive_tool__')));
      expect(joined, isNot(contains('__stash_')));
      expect(joined, isNot(contains('1=')));
      expect(joined, isNot(contains('3=')));
    });

    test('(β2) remote_params: κενό→κενό παραλείπεται', () async {
      const labels = AuditReferenceLabels(remoteToolNames: {3: 'RDP'});
      final row = AuditLogModel(
        id: 2,
        action: AuditActions.modifyEquipment,
        entityType: 'equipment',
        oldValuesJson: jsonEncode({
          'remote_params': {'3': ''},
        }),
        newValuesJson: jsonEncode({
          'remote_params': {'3': ''},
        }),
      );
      final lines = formatter.describeChanges(row, labels: labels);
      expect(lines.where((l) => l.contains('RDP')), isEmpty);
    });

    test('(δ) διαγραμμένο εργαλείο: «Εργαλείο #N» χωρίς σφάλμα', () async {
      const labels = AuditReferenceLabels(remoteToolNames: {1: 'VNC'});
      final row = AuditLogModel(
        id: 3,
        action: AuditActions.modifyEquipment,
        entityType: 'equipment',
        oldValuesJson: jsonEncode({
          'remote_params': {'4': 'old.rdp'},
        }),
        newValuesJson: jsonEncode({
          'remote_params': {'4': 'new.rdp'},
        }),
      );
      final lines = formatter.describeChanges(row, labels: labels);
      expect(lines.single,
          'Αλλαγή παραμέτρων απομακρυσμένης · Εργαλείο #4: old.rdp → new.rdp');
    });

    test('(γ) migration v36: αναζήτηση «προορισμος» βρίσκει αντίγραφο ασφαλείας', () async {
      await insertBackupAuditRow();
      await migrateDatabaseToV36(db);
      final service = AuditService(db);
      final keyword = SearchTextNormalizer.normalizeForSearch('προορισμος');
      final page = await service.queryPage(
        offset: 0,
        limit: 10,
        keywordNormalized: keyword,
      );
      expect(page.total, 1);
    });

    test('(στ) __stash_ δεν εμφανίζεται σε τίτλο ούτε σε diff', () async {
      final row = AuditLogModel(
        id: 4,
        action: AuditActions.modifyEquipment,
        entityType: 'equipment',
        oldValuesJson: jsonEncode({
          'remote_params': {
            '__stash_5': 'secret',
          },
        }),
        newValuesJson: jsonEncode({
          'remote_params': {
            '__stash_5': 'secret2',
            '1': 'x',
          },
        }),
      );
      const labels = AuditReferenceLabels(remoteToolNames: {1: 'VNC'});
      final summary = formatter.summaryLine(row, labels: labels);
      final lines = formatter.describeChanges(row, labels: labels);
      expect(summary, isNot(contains('__stash_')));
      expect(lines.join(' '), isNot(contains('__stash_')));
    });
  });
}
