import 'package:call_logger/features/audit/models/audit_log_model.dart';
import 'package:call_logger/features/audit/models/audit_reference_labels.dart';
import 'package:call_logger/features/audit/services/audit_formatter_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = AuditFormatterService();

  test('summaryLine για bulk JSON με affected_ids', () {
    final row = AuditLogModel(
      id: 1,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
      entityType: 'bulk_users',
      newValuesJson:
          '{"fields":{"department_id":5},"affected_ids":[1,2,3]}',
    );
    final s = formatter.summaryLine(row, technical: false);
    expect(s, contains('Επηρέασε 3'));
    expect(s, contains('τμήματος'));
  });

  test('summaryLine fallback όταν λείπει entity_type', () {
    final row = AuditLogModel(
      id: 2,
      action: 'ΠΑΛΙΑ ΕΝΕΡΓΕΙΑ',
      details: 'legacy row',
    );
    final s = formatter.summaryLine(row);
    expect(s, isNotEmpty);
  });

  test('prettyJsonBlock για κενό', () {
    expect(formatter.prettyJsonBlock(null), '—');
  });

  test('formatAuditTimestamp τοπική μορφή ελληνικής ημέρας', () {
    final s = formatter.formatAuditTimestamp('2026-04-13T11:00:17.756183');
    expect(s, contains('13-04-2026'));
    expect(s, contains(':'));
    final first = s.split(' ').first;
    expect(first.length, 3);
    const days = {'Δευ', 'Τρι', 'Τετ', 'Πεμ', 'Παρ', 'Σαβ', 'Κυρ'};
    expect(days.contains(first), true);
  });

  test('summaryLine διαγραφή εκκρεμότητας με τίτλο', () {
    final row = AuditLogModel(
      id: 1,
      action: 'ΔΙΑΓΡΑΦΗ',
      entityType: 'task',
      entityId: 48,
      entityName: 'Δοκιμαστικός τίτλος',
    );
    final s = formatter.summaryLine(row);
    expect(s, 'Διαγραφή · Δοκιμαστικός τίτλος');
  });

  test('summaryLine από details tasks id= χωρίς entity_type', () {
    final row = AuditLogModel(
      id: 2,
      action: 'ΔΙΑΓΡΑΦΗ',
      details: 'tasks id=48',
    );
    final s = formatter.summaryLine(row);
    expect(s, 'Διαγραφή · Εκκρεμότητα #48');
  });

  test('summaryLine αλλαγής χρώματος τμήματος', () {
    final row = AuditLogModel(
      id: 3,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ',
      entityType: 'department',
      entityName: 'Πληροφορική',
      oldValuesJson: '{"color":"#1976D2"}',
      newValuesJson: '{"color":"#EF5350"}',
    );
    final s = formatter.summaryLine(row);
    expect(
      s,
      'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ · Πληροφορική - Αλλαγή χρώματος από Μπλε #1976D2 σε Κόκκινο #EF5350',
    );
  });

  test('describeChanges για map_floor null -> 2', () {
    final row = AuditLogModel(
      id: 4,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ',
      entityType: 'department',
      entityName: 'Άδειες',
      oldValuesJson: '{"map_floor":null}',
      newValuesJson: '{"map_floor":"2"}',
    );
    final lines = formatter.describeChanges(row);
    expect(lines.first, 'Προσθήκη στον όροφο 2');
  });

  test('describeChanges για σύνδεση τηλεφώνου σε χρήστη', () {
    final row = AuditLogModel(
      id: 5,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
      entityType: 'phone',
      entityName: '2101234567',
      oldValuesJson: '{"linked_user_id":null}',
      newValuesJson: '{"linked_user_id":12}',
    );
    final lines = formatter.describeChanges(row);
    expect(lines.first, 'Σύνδεση σε χρήστη #12');
  });

  test('describeChanges department_id με department_text στο JSON', () {
    final row = AuditLogModel(
      id: 6,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ',
      entityType: 'equipment',
      entityName: '2978',
      oldValuesJson: '{"department_id":null}',
      newValuesJson:
          '{"department_id":46,"department_text":"Πληροφορική"}',
    );
    final s = formatter.summaryLine(row);
    expect(s, contains('Πληροφορική'));
    expect(s, isNot(contains('46')));
  });

  test('describeChanges department_id με resolved labels', () {
    final row = AuditLogModel(
      id: 7,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ',
      entityType: 'equipment',
      entityName: '2978',
      oldValuesJson: '{"department_id":null}',
      newValuesJson: '{"department_id":46}',
    );
    const labels = AuditReferenceLabels(
      departmentNames: {46: 'Γραμματεία'},
    );
    final s = formatter.summaryLine(row, labels: labels);
    expect(s, contains('Γραμματεία'));
    expect(s, isNot(contains('#46')));
  });

  test('summaryLine μίας αλλαγής χρώματος τμήματος — τίτλος όπως σήμερα', () {
    final row = AuditLogModel(
      id: 9,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ',
      entityType: 'department',
      entityName: 'Πληροφορική',
      oldValuesJson: '{"color":"#1976D2"}',
      newValuesJson: '{"color":"#33691E"}',
    );
    final s = formatter.summaryLine(row);
    expect(
      s,
      'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ · Πληροφορική - Αλλαγή χρώματος από Μπλε #1976D2 σε #33691E',
    );
  });

  test('summaryLine πολλαπλών αλλαγών τμήματος — σύντομος τίτλος με ετικέτες', () {
    final row = AuditLogModel(
      id: 10,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ',
      entityType: 'department',
      entityName: 'Πληροφορική',
      oldValuesJson: '{"color":"#1976D2","map_x":10.0,"map_floor":"1"}',
      newValuesJson: '{"color":"#33691E","map_x":50.0,"map_floor":"2"}',
    );
    final s = formatter.summaryLine(row);
    expect(
      s,
      'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ · Πληροφορική - 3 αλλαγές: χρώμα, όροφος, θέση',
    );
  });

  test('describeChanges department_id technical mode κρατά id', () {
    final row = AuditLogModel(
      id: 8,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ',
      entityType: 'equipment',
      entityName: '2978',
      newValuesJson: '{"department_id":46}',
    );
    const labels = AuditReferenceLabels(
      departmentNames: {46: 'Γραμματεία'},
    );
    final lines = formatter.describeChanges(
      row,
      technical: true,
      labels: labels,
    );
    expect(lines.first, contains('#46'));
  });
}
