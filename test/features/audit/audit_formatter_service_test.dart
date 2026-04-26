import 'package:call_logger/features/audit/models/audit_log_model.dart';
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
      'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ · Πληροφορική - Αλλαγή χρώματος από Μπλε σε Κόκκινο',
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
}
