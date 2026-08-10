import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/history_entity_display_utils.dart';

/// Πεδία κλήσης που καταγράφονται στο audit — κοινά για δημιουργία,
/// τροποποίηση και διαγραφή, ώστε οι ροές να μη διαφωνούν στο τι ιχνηλατείται.
const List<String> kCallAuditFields = [
  'date',
  'time',
  'caller_id',
  'equipment_id',
  'caller_text',
  'phone_text',
  'department_text',
  'equipment_text',
  'issue',
  'solution',
  'category_text',
  'category_id',
  'status',
  'duration',
  'is_priority',
  'lansweeper_state',
  'lansweeper_main_ticket_id',
  'lansweeper_last_sync_at',
  'is_deleted',
];

/// Σύνθεση της γραμμής «τηλέφωνο - καλούντας - τμήμα - εξοπλισμός» για το
/// `entity_name` του audit — ίδια εμφάνιση με το ιστορικό κλήσεων.
class CallsAuditLine {
  const CallsAuditLine(this.db);

  final Database db;

  /// Γραμμή όπως στο ιστορικό κλήσεων: κενά παραλείπονται, χωρίς placeholder `-`.
  static String formatCallAuditLineFromHistoryQueryRow(Map<String, Object?> r) {
    String nz(dynamic v) {
      final t = v?.toString().trim() ?? '';
      if (t.isEmpty || t == '-') return '';
      return t;
    }

    final phone = nz(r['user_phone']);
    final first = (r['user_first_name'] as String?)?.trim() ?? '';
    final last = (r['user_last_name'] as String?)?.trim() ?? '';
    var caller = '$first $last'.trim();
    if (caller.isNotEmpty && historyEntityIsDeleted(r['caller_is_deleted'])) {
      caller = historyDeletedDisplayLabel(
        caller,
        isDeleted: true,
        deletedSuffix: kHistoryUserDeletedSuffix,
      );
    }
    final dept = nz(r['user_department']);
    var equip = nz(r['equipment_code']);
    if (equip.isNotEmpty && historyEntityIsDeleted(r['equipment_is_deleted'])) {
      equip = historyDeletedDisplayLabel(
        equip,
        isDeleted: true,
        deletedSuffix: kHistoryEquipmentDeletedSuffix,
      );
    }
    return [phone, caller, dept, equip].where((s) => s.isNotEmpty).join(' - ');
  }

  /// Ίδια JOIN/COALESCE με το ιστορικό κλήσεων, για ΜΙΑ εγγραφή.
  Future<String> buildCallAuditDisplayLine(
    int callId, {
    DatabaseExecutor? executor,
  }) async {
    const userPhoneExpr =
        "COALESCE(NULLIF(TRIM(calls.phone_text), ''), upl.phone_list, '-')";
    final ex = executor ?? db;
    final rows = await ex.rawQuery(
      '''
      SELECT COALESCE(users.first_name, calls.caller_text, '') AS user_first_name,
             COALESCE(users.last_name, '') AS user_last_name,
             COALESCE(users.is_deleted, 0) AS caller_is_deleted,
             COALESCE(cat.is_deleted, 0) AS category_is_deleted,
             COALESCE(equipment.is_deleted, 0) AS equipment_is_deleted,
             COALESCE(cat.name, calls.category_text, '') AS category,
             $userPhoneExpr AS user_phone,
             COALESCE(departments.name, calls.department_text, '-') AS user_department,
             COALESCE(equipment.code_equipment, calls.equipment_text, '-') AS equipment_code
      FROM calls
      LEFT JOIN categories cat ON cat.id = calls.category_id
      LEFT JOIN users ON calls.caller_id = users.id
      LEFT JOIN (
        SELECT up.user_id AS uid,
               GROUP_CONCAT(p.number, ', ') AS phone_list
        FROM user_phones up
        JOIN phones p ON p.id = up.phone_id
        GROUP BY up.user_id
      ) upl ON upl.uid = users.id
      LEFT JOIN equipment ON calls.equipment_id = equipment.id
      LEFT JOIN departments ON users.department_id = departments.id
      WHERE calls.id = ?
      LIMIT 1
      ''',
      [callId],
    );
    if (rows.isEmpty) return '';
    return formatCallAuditLineFromHistoryQueryRow(rows.first);
  }
}
