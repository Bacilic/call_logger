import '../../utils/search_text_normalizer.dart';
import 'lamp_database_provider.dart';
import 'lamp_issue_resolution_models.dart';
import 'old_equipment_repository.dart';

/// Αναλυμένη γραμμή δικτύου από το raw_value εγγραφής ουράς.
class ParsedNetworkIssueRow {
  const ParsedNetworkIssueRow({
    required this.node,
    required this.ip,
    this.equipmentCode,
    required this.description,
    required this.mac,
    required this.vlan,
    required this.hostname,
    required this.workgroup,
    required this.internet,
    required this.comments,
  });

  final String node;
  final String ip;
  final String? equipmentCode;
  final String description;
  final String mac;
  final String vlan;
  final String hostname;
  final String workgroup;
  final String internet;
  final String comments;
}

/// Αποτέλεσμα αντιστοίχισης εγγραφής ουράς σε εξοπλισμό.
class NetworkIssueMatchResult {
  const NetworkIssueMatchResult.success()
      : success = true,
        conflict = false,
        message = null,
        existingIp = null,
        existingNetworkName = null,
        proposedIp = null,
        proposedNetworkName = null;

  const NetworkIssueMatchResult.error(this.message)
      : success = false,
        conflict = false,
        existingIp = null,
        existingNetworkName = null,
        proposedIp = null,
        proposedNetworkName = null;

  const NetworkIssueMatchResult.conflict({
    required this.message,
    required this.existingIp,
    required this.existingNetworkName,
    required this.proposedIp,
    required this.proposedNetworkName,
  })  : success = false,
        conflict = true;

  final bool success;
  final bool conflict;
  final String? message;
  final String? existingIp;
  final String? existingNetworkName;
  final String? proposedIp;
  final String? proposedNetworkName;
}

/// Parser και εφαρμογή αντιστοίχισης εγγραφών ουράς δικτύου — μόνο βάση.
class LampNetworkIssueResolutionService {
  LampNetworkIssueResolutionService({LampDatabaseProvider? databaseProvider})
      : _databaseProvider = databaseProvider ?? LampDatabaseProvider.instance;

  final LampDatabaseProvider _databaseProvider;

  /// Αναλύει raw_value: 10 πεδία (με κωδικό εξοπλισμού) ή 9 (παλαιά μορφή).
  ParsedNetworkIssueRow? parseNetworkIssueRawValue(String rawValue) {
    final parts = rawValue.split(';');
    if (parts.length == 10) {
      return ParsedNetworkIssueRow(
        node: parts[0].trim(),
        ip: parts[1].trim(),
        equipmentCode: parts[2].trim().isEmpty ? null : parts[2].trim(),
        description: parts[3].trim(),
        mac: parts[4].trim(),
        vlan: parts[5].trim(),
        hostname: parts[6].trim(),
        workgroup: parts[7].trim(),
        internet: parts[8].trim(),
        comments: parts[9].trim(),
      );
    }
    if (parts.length == 9) {
      return ParsedNetworkIssueRow(
        node: parts[0].trim(),
        ip: parts[1].trim(),
        description: parts[2].trim(),
        mac: parts[3].trim(),
        vlan: parts[4].trim(),
        hostname: parts[5].trim(),
        workgroup: parts[6].trim(),
        internet: parts[7].trim(),
        comments: parts[8].trim(),
      );
    }
    return null;
  }

  String networkSourceStamp(String node) {
    final nodeLabel = node.trim().isEmpty ? '—' : node.trim();
    return 'Χειροκίνητη αντιστοίχιση από την ουρά προβλημάτων ETL '
        '(θέση δικτύου $nodeLabel)';
  }

  /// Αναζήτηση κωδικού ή ονόματος εξοπλισμού για autocomplete επίλυσης δικτύου.
  Future<List<LampEntityCodeSuggestion>> searchEquipmentSuggestions({
    required String databasePath,
    required String query,
    int limit = 10,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <LampEntityCodeSuggestion>[];

    final normalizedQuery = SearchTextNormalizer.normalizeForSearch(trimmed);
    final compactQuery = trimmed.replaceAll(RegExp(r'\s+'), '');
    final db = await _databaseProvider.open(databasePath.trim());
    final rows = await db.query(
      'equipment',
      columns: <String>['code', 'description', 'serial_no'],
      orderBy: 'description ASC, code ASC',
    );

    final matches = <LampEntityCodeSuggestion>[];

    bool matchesEntry(int code, String label) {
      if (compactQuery.isNotEmpty && code.toString().contains(compactQuery)) {
        return true;
      }
      return SearchTextNormalizer.matchesNormalizedQuery(label, normalizedQuery);
    }

    for (final row in rows) {
      final code = _toInt(row['code']);
      if (code == null) continue;
      final label = _equipmentSearchLabel(row);
      if (label.isEmpty) continue;
      if (!matchesEntry(code, label)) continue;
      matches.add(LampEntityCodeSuggestion(code: code, label: label));
      if (matches.length >= limit) break;
    }
    return matches;
  }

  /// Σύντομη ετικέτα εξοπλισμού για προεπισκόπηση πριν την αντιστοίχιση.
  Future<String?> equipmentPreview({
    required String databasePath,
    required int code,
  }) async {
    final db = await _databaseProvider.open(databasePath.trim());
    final rows = await db.query(
      'equipment',
      columns: <String>['description', 'serial_no', 'office_original_text'],
      where: 'code = ?',
      whereArgs: <Object?>[code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _equipmentPreviewLabel(rows.single);
  }

  /// Αντιστοιχίζει εγγραφή ουράς σε εξοπλισμό και διαγράφει την εγγραφή.
  Future<NetworkIssueMatchResult> matchIssueToEquipment({
    required String databasePath,
    required int issueId,
    required int equipmentCode,
    bool overwrite = false,
  }) async {
    final db = await _databaseProvider.open(
      databasePath.trim(),
      mode: LampDatabaseMode.write,
    );

    final issueRows = await db.query(
      'data_issues',
      where: 'id = ?',
      whereArgs: <Object?>[issueId],
      limit: 1,
    );
    if (issueRows.isEmpty) {
      return const NetworkIssueMatchResult.error('Η εγγραφή ουράς δεν βρέθηκε.');
    }

    final rawValue = issueRows.first['raw_value']?.toString() ?? '';
    final parsed = parseNetworkIssueRawValue(rawValue);
    if (parsed == null) {
      return const NetworkIssueMatchResult.error(
        'Μη αναγνωρίσιμη μορφή raw_value για γραμμή δικτύου.',
      );
    }

    final equipmentRows = await db.query(
      'equipment',
      where: 'code = ?',
      whereArgs: <Object?>[equipmentCode],
      limit: 1,
    );
    if (equipmentRows.isEmpty) {
      return NetworkIssueMatchResult.error(
        'Δεν βρέθηκε εξοπλισμός με κωδικό $equipmentCode.',
      );
    }

    final equipment = equipmentRows.single;
    final proposedIp = parsed.ip.trim();
    final proposedNetworkName = parsed.hostname.trim();
    final existingIp = _nonEmptyText(equipment['ip_address']);
    final existingNetworkName = _nonEmptyText(equipment['network_name']);

    final ipConflict = existingIp != null &&
        proposedIp.isNotEmpty &&
        existingIp != proposedIp;
    final nameConflict = existingNetworkName != null &&
        proposedNetworkName.isNotEmpty &&
        existingNetworkName != proposedNetworkName;

    if ((ipConflict || nameConflict) && !overwrite) {
      return NetworkIssueMatchResult.conflict(
        message: 'Ο εξοπλισμός $equipmentCode έχει ήδη στοιχεία δικτύου '
            'που διαφέρουν από την εγγραφή ουράς.',
        existingIp: existingIp,
        existingNetworkName: existingNetworkName,
        proposedIp: proposedIp.isEmpty ? null : proposedIp,
        proposedNetworkName:
            proposedNetworkName.isEmpty ? null : proposedNetworkName,
      );
    }

    final source = networkSourceStamp(parsed.node);
    final updates = <String, Object?>{
      if (proposedIp.isNotEmpty) 'ip_address': proposedIp,
      if (proposedNetworkName.isNotEmpty) 'network_name': proposedNetworkName,
      'network_source': source,
      'network_node': _nullableTrim(parsed.node),
      'network_vlan': _nullableTrim(parsed.vlan),
      'network_mac': _nullableTrim(parsed.mac),
      'network_description': _nullableTrim(parsed.description),
      'network_comments': _nullableTrim(parsed.comments),
    };

    try {
      await db.transaction<void>((txn) async {
        await txn.update(
          'equipment',
          updates,
          where: 'code = ?',
          whereArgs: <Object?>[equipmentCode],
        );
        await txn.delete(
          'data_issues',
          where: 'id = ?',
          whereArgs: <Object?>[issueId],
        );
      });
    } catch (e) {
      return NetworkIssueMatchResult.error('Αποτυχία αντιστοίχισης: $e');
    }

    return const NetworkIssueMatchResult.success();
  }

  /// Επικύρωση μορφής IPv4 (4 οκτάδες 0–255).
  bool isValidIpv4(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      if (part.isEmpty || !RegExp(r'^\d{1,3}$').hasMatch(part)) {
        return false;
      }
      final value = int.parse(part);
      if (value < 0 || value > 255) return false;
    }
    return true;
  }

  /// Διορθώνει πεδίο δικτύου στον εξοπλισμό και αφαιρεί την εγγραφή ουράς.
  Future<NetworkIssueMatchResult> fixEquipmentNetworkField({
    required String databasePath,
    required int issueId,
    required int equipmentCode,
    required String column,
    required String newValue,
  }) async {
    if (column != 'ip_address' && column != 'network_name') {
      return NetworkIssueMatchResult.error(
        'Μη υποστηριζόμενη στήλη: $column. '
        'Επιτρέπονται μόνο ip_address και network_name.',
      );
    }

    final trimmed = newValue.trim();
    if (trimmed.isEmpty) {
      return const NetworkIssueMatchResult.error(
        'Η τιμή δεν μπορεί να είναι κενή.',
      );
    }

    if (column == 'ip_address' && !isValidIpv4(trimmed)) {
      return const NetworkIssueMatchResult.error('Μη έγκυρη μορφή IPv4.');
    }

    final db = await _databaseProvider.open(
      databasePath.trim(),
      mode: LampDatabaseMode.write,
    );

    try {
      await db.transaction<void>((txn) async {
        await txn.update(
          'equipment',
          <String, Object?>{column: trimmed},
          where: 'code = ?',
          whereArgs: <Object?>[equipmentCode],
        );
        await txn.delete(
          'data_issues',
          where: 'id = ?',
          whereArgs: <Object?>[issueId],
        );
      });
    } catch (e) {
      return NetworkIssueMatchResult.error('Αποτυχία διόρθωσης: $e');
    }

    return const NetworkIssueMatchResult.success();
  }

  /// Αποδέχεται εγγραφή ουράς ως έχει, με αιτιολογία (χωρίς αλλαγή εξοπλισμού).
  Future<bool> acceptIssue({
    required String databasePath,
    required int issueId,
    required String reason,
  }) async {
    final db = await _databaseProvider.open(
      databasePath.trim(),
      mode: LampDatabaseMode.write,
    );

    final infoRows = await db.rawQuery('PRAGMA table_info(data_issues)');
    final columns = <String>{
      for (final row in infoRows)
        if ((row['name']?.toString().trim().isNotEmpty ?? false))
          row['name'].toString(),
    };
    if (!columns.contains('resolution_note')) {
      await db.execute(
        'ALTER TABLE data_issues ADD COLUMN resolution_note TEXT',
      );
    }

    final updated = await db.update(
      'data_issues',
      <String, Object?>{
        'status': kDataIssueStatusAccepted,
        'resolution_note': reason.trim(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[issueId],
    );
    return updated >= 1;
  }

  /// Διαγράφει εγγραφή ουράς χωρίς αντιστοίχιση.
  Future<bool> deleteIssue({
    required String databasePath,
    required int issueId,
  }) async {
    final db = await _databaseProvider.open(
      databasePath.trim(),
      mode: LampDatabaseMode.write,
    );
    final deleted = await db.delete(
      'data_issues',
      where: 'id = ?',
      whereArgs: <Object?>[issueId],
    );
    return deleted > 0;
  }

  String? _nonEmptyText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  String? _nullableTrim(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _toInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  String _equipmentSearchLabel(Map<String, Object?> row) {
    final description = row['description']?.toString().trim() ?? '';
    final serial = row['serial_no']?.toString().trim() ?? '';
    if (description.isNotEmpty && serial.isNotEmpty) {
      return '$description · $serial';
    }
    if (description.isNotEmpty) return description;
    if (serial.isNotEmpty) return serial;
    final code = _toInt(row['code']);
    return code?.toString() ?? '';
  }

  String? _equipmentPreviewLabel(Map<String, Object?> row) {
    final parts = <String>[];
    final description = row['description']?.toString().trim();
    final serial = row['serial_no']?.toString().trim();
    final department = row['office_original_text']?.toString().trim();
    if (description != null && description.isNotEmpty) {
      parts.add(description);
    }
    if (serial != null && serial.isNotEmpty) {
      parts.add(serial);
    }
    if (department != null && department.isNotEmpty) {
      parts.add(department);
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }
}
