import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utils/user_identity_normalizer.dart';
import 'lamp_issue_matching_engine.dart';
import 'lamp_issue_resolution_models.dart';

class LampFkLabelMaps {
  const LampFkLabelMaps({
    required this.modelLabelById,
    required this.officeLabelById,
    required this.ownerLabelById,
  });

  final Map<int, String> modelLabelById;
  final Map<int, String> officeLabelById;
  final Map<int, String> ownerLabelById;

  static const LampFkLabelMaps empty = LampFkLabelMaps(
    modelLabelById: <int, String>{},
    officeLabelById: <int, String>{},
    ownerLabelById: <int, String>{},
  );
}

/// Ετικέτα FK ως «Όνομα (id)» ή σκέτο id αν λείπει όνομα.
String lampLabelledId(Map<int, String> labels, Object? id) {
  if (id == null) return '-';
  int? asInt;
  if (id is int) {
    asInt = id;
  } else if (id is num) {
    asInt = id.toInt();
  } else {
    asInt = int.tryParse(id.toString().trim());
  }
  if (asInt == null) return '-';
  final label = labels[asInt];
  if (label != null && label.isNotEmpty) return '$label ($asInt)';
  return asInt.toString();
}

class LampIssueResolutionSupport {
  LampIssueResolutionSupport(this._matching);

  final LampIssueMatchingEngine _matching;

  static const List<String> equipmentPreviewColumns = <String>[
    'code',
    'description',
    'model',
    'serial_no',
    'asset_no',
    'office',
    'owner',
    'set_master',
  ];

  Future<List<Map<String, Object?>>> openIssues(
    Database db,
    LampIssueType issueType,
  ) {
    return db.query(
      'data_issues',
      where: "issue_type = ? AND COALESCE(status, 'open') = 'open'",
      whereArgs: <Object?>[issueType.issueType],
      orderBy: 'id ASC',
    );
  }

  String? text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  int? toInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  String? issueEntityType(Map<String, Object?> issue) {
    final explicit = text(issue['entity_type'])?.toLowerCase();
    if (explicit != null) return explicit;
    final legacySheet = text(issue['sheet'])?.toLowerCase();
    if (legacySheet == 'integrity_scan') {
      return 'equipment';
    }
    return legacySheet;
  }

  String? issueOrigin(Map<String, Object?> issue) {
    final explicit = text(issue['origin'])?.toLowerCase();
    if (explicit != null) return explicit;
    final legacySheet = text(issue['sheet'])?.toLowerCase();
    if (legacySheet == 'integrity_scan') {
      return 'integrity_scan';
    }
    return 'manual';
  }

  String originalText(
    Map<String, Object?> equipment,
    String originalColumn,
    Object? rawValue,
  ) {
    final fromOriginal = text(equipment[originalColumn]);
    if (fromOriginal != null && fromOriginal.trim().isNotEmpty) {
      return fromOriginal.trim();
    }
    return text(rawValue)?.trim() ?? '';
  }

  FkSpec? fkSpec(String column) {
    return switch (column) {
      'office' => const FkSpec('office', 'office_original_text'),
      'owner' => const FkSpec('owner', 'owner_original_text'),
      'contract' => const FkSpec('contract', 'contract_original_text'),
      'model' => const FkSpec('model', 'model_original_text'),
      _ => null,
    };
  }

  LampIssueResolutionProposal Function({
    required LampIssueResolutionAction action,
    int? proposedId,
    String? proposedMatch,
    required int confidence,
    List<LampIssueResolutionOption> options,
    required String notes,
    Map<String, Object?> metadata,
  })
  baseProposal(
    LampIssueType issueType,
    Map<String, Object?> issue, {
    String? originalOverride,
  }) {
    return ({
      required LampIssueResolutionAction action,
      int? proposedId,
      String? proposedMatch,
      required int confidence,
      List<LampIssueResolutionOption> options =
          const <LampIssueResolutionOption>[],
      required String notes,
      Map<String, Object?> metadata = const <String, Object?>{},
    }) {
      return LampIssueResolutionProposal(
        issueType: issueType,
        issueIds: [toInt(issue['id'])].whereType<int>().toList(),
        sheet: text(issue['sheet']),
        row: toInt(issue['row_number']),
        column: text(issue['column_name']),
        originalValue: originalOverride ?? text(issue['raw_value']),
        proposedAction: action,
        proposedId: proposedId,
        proposedMatch: proposedMatch,
        confidence: confidence,
        options: options,
        notes: notes,
        metadata: metadata,
      );
    };
  }

  String equipmentSummary(
    Map<String, Object?> row, {
    LampFkLabelMaps labels = LampFkLabelMaps.empty,
  }) {
    return 'κωδικός=${row['code']} · ${text(row['description']) ?? '-'} · '
        'μοντέλο=${lampLabelledId(labels.modelLabelById, row['model'])} · '
        'σειριακός=${row['serial_no'] ?? '-'} · '
        'γραφείο=${lampLabelledId(labels.officeLabelById, row['office'])} · '
        'υπάλληλος=${lampLabelledId(labels.ownerLabelById, row['owner'])}';
  }

  Future<LampFkLabelMaps> loadFkLabelMaps(Database db) async {
    final modelLabelById = <int, String>{};
    final modelRows = await db.query(
      'model',
      columns: <String>['model', 'model_name'],
    );
    for (final row in modelRows) {
      final id = toInt(row['model']);
      final label = text(row['model_name']);
      if (id != null && label != null) {
        modelLabelById[id] = label;
      }
    }

    final officeLabelById = <int, String>{};
    final officeRows = await db.query(
      'offices',
      columns: <String>['office', 'office_name', 'department_name'],
    );
    for (final row in officeRows) {
      final id = toInt(row['office']);
      if (id == null) continue;
      final officeName = text(row['office_name']) ?? '';
      final departmentName = text(row['department_name']) ?? '';
      final label = departmentName.isNotEmpty
          ? '$officeName $departmentName'
          : officeName;
      if (label.isNotEmpty) {
        officeLabelById[id] = label;
      }
    }

    final ownerLabelById = <int, String>{};
    final ownerRows = await db.query('owners');
    for (final row in ownerRows) {
      final id = toInt(row['owner']);
      final label = ownerLabel(row);
      if (id != null && label.isNotEmpty) {
        ownerLabelById[id] = label;
      }
    }

    return LampFkLabelMaps(
      modelLabelById: modelLabelById,
      officeLabelById: officeLabelById,
      ownerLabelById: ownerLabelById,
    );
  }

  Future<Map<String, Object?>?> equipmentByCode(Database db, int code) async {
    final rows = await db.query(
      'equipment',
      where: 'code = ?',
      whereArgs: <Object?>[code],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<ReferenceRow>> referenceRows(
    Database db, {
    required String table,
    required String idColumn,
    required String labelColumn,
  }) async {
    final rows = await db.query(
      table,
      columns: <String>[idColumn, labelColumn],
      orderBy: labelColumn,
    );
    return <ReferenceRow>[
      for (final row in rows)
        if (toInt(row[idColumn]) != null)
          ReferenceRow(
            id: toInt(row[idColumn])!,
            label: text(row[labelColumn]) ?? '',
            normalized: _matching.normalizeReferenceText(
              text(row[labelColumn]) ?? '',
            ),
          ),
    ];
  }

  String ownerLabel(Map<String, Object?> owner) {
    final lastName = text(owner['last_name']) ?? '';
    final firstName = text(owner['first_name']) ?? '';
    return '$lastName $firstName'.trim();
  }

  String ownerIdentityKeyFromRow(Map<String, Object?> owner) {
    return UserIdentityNormalizer.identityKeyForPerson(
      text(owner['first_name']),
      text(owner['last_name']),
    );
  }

  List<String> ownerOriginalParts(String original) {
    final cleaned = original.replaceAll(RegExp(r'[-/()\\]+'), ' ').trim();
    if (cleaned.isEmpty) return const <String>[];
    return cleaned
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
  }

  List<int> cycleForRoot(int root, Map<int, int> masterByCode) {
    final path = <int>[];
    final indexByCode = <int, int>{};
    var current = root;
    while (true) {
      final existing = indexByCode[current];
      if (existing != null) return path.sublist(existing);
      final next = masterByCode[current];
      if (next == null || next == current) return const <int>[];
      indexByCode[current] = path.length;
      path.add(current);
      current = next;
    }
  }
}

class FkSpec {
  const FkSpec(this.fkColumn, this.originalColumn);

  final String fkColumn;
  final String originalColumn;
}
