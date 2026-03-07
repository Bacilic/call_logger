import 'dart:io';

import 'package:excel/excel.dart';

import 'import_types.dart';

/// Αποτέλεσμα εισαγωγής Excel (parse + prepare).
class ImportResult {
  const ImportResult({
    required this.success,
    this.totalCount = 0,
    this.errorMessage,
    this.usersPrepared = 0,
    this.equipmentPrepared = 0,
    this.usersInserted = 0,
    this.equipmentInserted = 0,
    this.skipped = 0,
    this.errors = const [],
    this.preparedOwners,
    this.preparedEquipment,
  });

  final bool success;
  final int totalCount;
  final String? errorMessage;
  final int usersPrepared;
  final int equipmentPrepared;
  final int usersInserted;
  final int equipmentInserted;
  final int skipped;
  final List<String> errors;
  final List<Map<String, dynamic>>? preparedOwners;
  final List<Map<String, dynamic>>? preparedEquipment;
}

/// Exact-match φίλτρο: descriptions_tower_pc.txt σε lowercase.
/// Η description πρέπει να ταυτίζεται ΑΚΡΙΒΩΣ (case-insensitive) με κάποιο entry.
const Set<String> _pcDescriptionsExact = {
  '4quest x intel p4 2.8ghz fsb 533',
  'altec performer',
  'black case (inn vator)',
  'compaq deskpro en',
  'compaq proliant ml370',
  'compaq proliant ml370 g3 series',
  'dell desktop 1',
  'dell optiplex 3010',
  'hp 290g2m σταθερός υπολογιστής',
  'hp compaq',
  'inn vator',
  'lenovo thinkcentre e73 desktop',
  'lenovo thinkstation p360 tower',
  'oktabit vero',
  'plato advanced',
  'plato bp 500 piii',
  'plato piii 1ghz',
  'plato piii 1ghz - αλλαγή κουτιού',
  'poweredge t610 server',
  'quest x intel p4 2.8ghz fsb 533',
  'quest x intel p4 3.0ghz fsb 533',
  'quest x intel p4 3.0ghz fsb 800',
  'rise pc',
  'server hp zlbl ml350 g10',
  'σταθερός υπολογιστής',
  'σταθερός υπολογιστής από πληροφορική.',
  'σταθερός υπολογιστής i3',
  'σταθερός υπολογιστής- από πληροφορική',
  'σταθερός υπολογιστής-από πληροφορική',
  'σταθερός υπολογιστής dell optiplex 3050',
  'σταθερός υπολογιστής hp desktop pro300 g3',
  'σταθερός υπολογιστής hp elitedesk 800 g3 twr',
  'σταθερός υπολογιστής hp pro g2 mt',
  'σταθερός υπολογιστής lenovo v530s',
  'σταθερός υπολογιστής pc expert',
  'σταθερός υπολογιστής turbo-x',
  'σταθερος υπολογιστης',
  'σταθερος υπολογιστης oktabit vero',
  'σταθερος υπολογιστης optiplex 3050',
  'υπολογιστής dell optiplex 3050',
  'turbo-x teamwork 13i3324-7',
  'turbo-x pentium',
  'vero pc p4 2.0ghz',
  'vero pc p4 2.6ghz',
  'vero pc oktavit, intel e5700/3 ghz,ram 2gb/ddr3,hdd sata 500gb, μητρική asus p5g41t-m lx2-gb-lpt, windows 7 pr. 32 bit gr',
};

/// Parser για legacy Master Excel (Λάμπα): offices → owners → equipment.
class ExcelParser {
  ExcelParser();

  static String _cell(List<Data?> row, int idx) {
    if (idx >= row.length) return '';
    final v = row[idx]?.value;
    if (v == null) return '';
    switch (v) {
      case TextCellValue():
        return v.value.toString().trim();
      case IntCellValue():
        return v.value.toString().trim();
      case DoubleCellValue():
        final s = v.value.toString();
        return (s.endsWith('.0') ? s.substring(0, s.length - 2) : s).trim();
      default:
        return v.toString().trim();
    }
  }

  /// Διαβάζει το αρχείο .xlsx με φύλλα offices/owners/equipment.
  ///
  /// - **offices** (header row 0): `[0]office [1]office_name [9]building [10]level`
  ///   → officeMap: officeId → "officeName buildingLevel" (π.χ. "Κίνηση Αιμοδοσίας β1")
  ///
  /// - **owners** (header row 0): `[0]owner [1]last_name [2]first_name [3]office [5]phones`
  ///   → ownersMap: ownerId → {fullName, phones, department}
  ///   Ένας owner εισάγεται **μία φορά** στη βάση.
  ///
  /// - **equipment** (header row 4, δεδομένα από row 5):
  ///   `[0]code [1]description [6]state_name [13]owner`
  ///   Φίλτρο: state_name == "Σε λειτουργία" ΚΑΙ description **exact match** (case-insensitive) με _pcDescriptionsExact.
  ///   Εισάγεται μόνο `code` + `user_id`. **description δεν εισάγεται**.
  Future<ImportResult> parseLegacyExcel(
    String filePath,
    void Function(String message, [ImportLogLevel? level]) onLog,
  ) async {
    int skipped = 0;
    final errors = <String>[];

    try {
      final bytes = await File(filePath).readAsBytes();
      if (bytes.isEmpty) {
        return const ImportResult(
          success: false,
          errors: ['Δεν ήταν δυνατή η ανάγνωση του αρχείου.'],
        );
      }

      final excel = Excel.decodeBytes(bytes);

      // ── offices: officeId → location string ──
      final officeMap = <int, String>{};
      final officesSheet = excel.tables['offices'];
      if (officesSheet != null) {
        onLog('--- Φύλλο: offices (${officesSheet.rows.length - 1} εγγραφές) ---');
        for (var i = 1; i < officesSheet.rows.length; i++) {
          final row = officesSheet.rows[i];
          if (row.isEmpty) continue;
          final officeId = int.tryParse(_cell(row, 0)) ?? 0;
          final name = _cell(row, 1);
          final building = _cell(row, 9);
          final level = _cell(row, 10);
          final location = '$name $building$level'.trim();
          officeMap[officeId] = location.isEmpty ? 'Άγνωστο' : location;
        }
        onLog('Offices φορτωμένα: ${officeMap.length}', ImportLogLevel.success);
      }

      // ── owners: ownerId → { ownerId, fullName, phones, department } ──
      final ownersMap = <int, Map<String, dynamic>>{};
      final ownersSheet = excel.tables['owners'];
      if (ownersSheet != null) {
        onLog('--- Φύλλο: owners (${ownersSheet.rows.length - 1} εγγραφές) ---');
        for (var i = 1; i < ownersSheet.rows.length; i++) {
          final row = ownersSheet.rows[i];
          if (row.isEmpty) continue;
          final ownerId = int.tryParse(_cell(row, 0)) ?? 0;
          final lastName = _cell(row, 1);
          final firstName = _cell(row, 2);
          final officeId = int.tryParse(_cell(row, 3)) ?? 0;
          final phones = _cell(row, 5);
          final fullName = '$lastName $firstName'.trim();
          if (fullName.isEmpty) continue;
          final department = officeMap[officeId] ?? 'Άγνωστο';
          ownersMap[ownerId] = {
            'ownerId': ownerId,
            'fullName': fullName,
            'phones': phones,
            'department': department,
          };
        }
        onLog('Owners φορτωμένοι: ${ownersMap.length}', ImportLogLevel.success);
      }

      // ── equipment: δεδομένα από row 5 (header στη row 4) ──
      // Φίλτρο: state_name == "Σε λειτουργία" + exact match description + owner υπάρχει
      // Εισαγωγή: code + ownerCodeTemp (→ user_id μετά)
      final equipmentList = <Map<String, dynamic>>[];
      final referencedOwnerIds = <int>{};
      final equipmentSheet = excel.tables['equipment'];
      if (equipmentSheet != null) {
        onLog('--- Φύλλο: equipment (${equipmentSheet.rows.length} rows, header row 4, data row 5+) ---');
        for (var i = 5; i < equipmentSheet.rows.length; i++) {
          final row = equipmentSheet.rows[i];
          if (row.isEmpty) continue;

          final description = _cell(row, 1);
          final stateName = _cell(row, 6);

          if (stateName != 'Σε λειτουργία') {
            skipped++;
            continue;
          }

          final descLower = description.toLowerCase();
          if (!_pcDescriptionsExact.contains(descLower)) {
            skipped++;
            continue;
          }

          final code = _cell(row, 0);
          final ownerIdStr = _cell(row, 13);
          final ownerId = int.tryParse(ownerIdStr) ?? 0;

          if (!ownersMap.containsKey(ownerId)) {
            skipped++;
            continue;
          }

          referencedOwnerIds.add(ownerId);
          equipmentList.add({
            'code': code,
            'ownerCodeTemp': ownerId,
          });
          final ownerName = ownersMap[ownerId]!['fullName'];
          onLog('[${equipmentList.length}] Κωδ: $code | Owner: $ownerName ($ownerId)');
        }
      }

      // Κρατάμε μόνο owners που αναφέρονται σε τουλάχιστον ένα equipment
      final filteredOwners = referencedOwnerIds
          .where((id) => ownersMap.containsKey(id))
          .map((id) => ownersMap[id]!)
          .toList();

      onLog(
        'ΕΠΙΤΥΧΙΑ: ${filteredOwners.length} χρήστες, ${equipmentList.length} υπολογιστές (παράλειψη: $skipped).',
        ImportLogLevel.success,
      );

      return ImportResult(
        success: true,
        usersPrepared: filteredOwners.length,
        equipmentPrepared: equipmentList.length,
        skipped: skipped,
        errors: errors,
        preparedOwners: filteredOwners,
        preparedEquipment: equipmentList,
      );
    } catch (e) {
      final msg = 'ΣΦΑΛΜΑ: $e';
      onLog(msg, ImportLogLevel.error);
      errors.add(msg);
      return ImportResult(
        success: false,
        skipped: skipped,
        errors: errors,
      );
    }
  }
}
