// Μόνο για τον τύπο [Database] στην υπογραφή — τα ερωτήματα πάνε σε repositories.
import 'package:sqflite_common/sqflite.dart';

import '../../../core/database/calls_repository.dart';
import '../../../core/database/user_repository.dart';

/// Περίληψη εξοπλισμού για τον διάλογο επιβεβαίωσης διαγραφής.
class EquipmentDeletionSummary {
  const EquipmentDeletionSummary({
    required this.code,
    this.ownerName,
    this.phone,
    required this.historyCount,
  });

  final String code;
  final String? ownerName;
  final String? phone;
  final int historyCount;
}

/// Γραμμές λεπτομερειών για έως 5 εξοπλισμούς.
///
/// Μορφή: `2113 → Αναστασία Φούφα · τηλ. 2898 · 12 εγγραφές ιστορικού`
/// (παραλείπει κάτοχο/τηλέφωνο όταν λείπουν).
List<String> formatEquipmentDeletionLines(
  List<EquipmentDeletionSummary> summaries,
) {
  return summaries.map(_formatOne).toList(growable: false);
}

String _formatOne(EquipmentDeletionSummary s) {
  final historyLabel = s.historyCount == 1
      ? '1 εγγραφή ιστορικού'
      : '${s.historyCount} εγγραφές ιστορικού';
  final owner = s.ownerName?.trim();
  final phone = s.phone?.trim();
  final buf = StringBuffer(s.code);
  if (owner != null && owner.isNotEmpty) {
    buf.write(' → $owner');
  }
  if (phone != null && phone.isNotEmpty) {
    buf.write(' · τηλ. $phone');
  }
  buf.write(' · $historyLabel');
  return buf.toString();
}

String? _ownerDisplayName(Map<String, dynamic> snapshot) {
  final first = (snapshot['first_name'] as String?)?.trim() ?? '';
  final last = (snapshot['last_name'] as String?)?.trim() ?? '';
  final name = '$first $last'.trim();
  return name.isEmpty ? null : name;
}

/// Φορτώνει περίληψη διαγραφής για τα δοσμένα ids εξοπλισμού (σειρά εισόδου).
Future<List<EquipmentDeletionSummary>> deletionSummaries(
  Database db,
  List<int> equipmentIds,
) async {
  if (equipmentIds.isEmpty) return const [];

  final userRepo = UserRepository(db);
  final callsRepo = CallsRepository(db);
  final out = <EquipmentDeletionSummary>[];

  for (final id in equipmentIds) {
    final codeRows = await db.query(
      'equipment',
      columns: ['code_equipment'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final rawCode = codeRows.isEmpty
        ? null
        : (codeRows.first['code_equipment'] as String?)?.trim();
    final code = (rawCode == null || rawCode.isEmpty) ? id.toString() : rawCode;

    String? ownerName;
    String? phone;
    final owners = await userRepo.getEquipmentOwnerSnapshots(id);
    if (owners.isNotEmpty) {
      final owner = owners.first;
      ownerName = _ownerDisplayName(owner);
      final ownerId = owner['id'] as int?;
      if (ownerId != null) {
        final phones = await userRepo.userPhoneNumbersOrdered(db, ownerId);
        if (phones.isNotEmpty) {
          final p = phones.first.trim();
          phone = p.isEmpty ? null : p;
        }
      }
    }

    final historyCount = await callsRepo.countCallsForEquipment(id);
    out.add(
      EquipmentDeletionSummary(
        code: code,
        ownerName: ownerName,
        phone: phone,
        historyCount: historyCount,
      ),
    );
  }

  return out;
}
