import 'lamp_database_provider.dart';

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
}
