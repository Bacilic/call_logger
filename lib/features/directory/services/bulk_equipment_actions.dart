import '../../../core/database/department_repository.dart';
import '../../../core/database/directory_support.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/models/remote_tool.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/models/user_model.dart';
import '../models/equipment_column.dart';
import '../screens/widgets/shared_asset_disconnect_dialog.dart';
import 'bulk_action_undo_record.dart';

/// Πεδίο-στόχος του μαζικού Καθαρισμού εξοπλισμού.
enum BulkEquipmentClearField { owner, notes, location, remoteParams }

/// Τύχη του εξοπλισμού μετά την αποδέσμευση κατόχου στον Καθαρισμό.
enum BulkEquipmentOwnerClearFate {
  /// Κοινόχρηστος στο τμήμα του πρώην κατόχου (προεπιλογή).
  shareInFormerOwnerDepartment,

  /// Μεταφορά σε τμήμα που επιλέγει ο χρήστης.
  transfer,
}

/// Τρόπος εφαρμογής μαζικών σημειώσεων εξοπλισμού.
enum BulkEquipmentNotesMode { append, replace }

/// Στοιχείο που εξαιρέθηκε από μαζική ενέργεια εξοπλισμού, με αιτιολογία.
class BulkEquipmentExclusion {
  const BulkEquipmentExclusion({required this.code, required this.reason});

  final String code;
  final String reason;
}

/// Εμφανίσιμος κωδικός εξοπλισμού για μηνύματα.
String bulkEquipmentDisplayCode(EquipmentModel e) {
  final code = (e.code ?? '').trim();
  if (code.isNotEmpty) return code;
  final id = e.id;
  return id == null ? '—' : 'id=$id';
}

/// Λίστα κωδικών για μηνύματα: έως 5 ονομαστικά, μετά «+Ν ακόμη».
String bulkEquipmentCodesPreview(Iterable<EquipmentRow> rows) {
  final codes = [for (final r in rows) bulkEquipmentDisplayCode(r.$1)];
  if (codes.isEmpty) return '';
  if (codes.length <= 5) return codes.join(', ');
  return '${codes.take(5).join(', ')} +${codes.length - 5} ακόμη';
}

String _ownerName(UserModel u) {
  final name = (u.name ?? '${u.firstName ?? ''} ${u.lastName ?? ''}').trim();
  return name.isEmpty ? '—' : name;
}

// ─────────────────────────── Μεταφορά σε τμήμα ───────────────────────────

/// Σχέδιο μαζικής μεταφοράς εξοπλισμού σε τμήμα.
class BulkEquipmentTransferPlan {
  const BulkEquipmentTransferPlan({
    required this.target,
    required this.targetDisplayName,
    required this.rowsToMove,
    required this.rowsAlreadyInTarget,
    required this.ownersToDetach,
    required this.exclusions,
  });

  final SharedAssetTransferTarget target;
  final String targetDisplayName;
  final List<EquipmentRow> rowsToMove;
  final List<EquipmentRow> rowsAlreadyInTarget;

  /// equipment.id → κάτοχοι που αποδεσμεύονται λόγω της μεταφοράς.
  final Map<int, List<int>> ownersToDetach;

  final List<BulkEquipmentExclusion> exclusions;

  bool get hasWork => rowsToMove.isNotEmpty;

  int get detachedOwnerCount => ownersToDetach.length;
}

/// Υπολογίζει το σχέδιο μεταφοράς ΧΩΡΙΣ πρόσβαση στη βάση (τεσταρίσιμο).
BulkEquipmentTransferPlan buildBulkEquipmentTransferPlan({
  required List<EquipmentRow> selectedRows,
  required SharedAssetTransferTarget target,
  required String targetDisplayName,
  Map<int, List<UserModel>> ownersByEquipmentId = const {},
}) {
  final targetId = target.departmentId;
  final rowsToMove = <EquipmentRow>[];
  final rowsAlreadyInTarget = <EquipmentRow>[];
  final ownersToDetach = <int, List<int>>{};
  final exclusions = <BulkEquipmentExclusion>[];

  for (final row in selectedRows) {
    final eq = row.$1;
    final eqId = eq.id;
    if (eqId == null) continue;
    final owners = ownersByEquipmentId[eqId] ?? const <UserModel>[];

    // Το εμφανιζόμενο τμήμα: του κατόχου όταν υπάρχει, αλλιώς του εξοπλισμού.
    final effectiveDeptId = owners.isNotEmpty
        ? owners.first.departmentId
        : eq.departmentId;
    if (targetId != null && effectiveDeptId == targetId && owners.isEmpty) {
      rowsAlreadyInTarget.add(row);
      continue;
    }

    rowsToMove.add(row);
    if (owners.isNotEmpty) {
      ownersToDetach[eqId] = [
        for (final o in owners)
          if (o.id != null) o.id!,
      ];
      exclusions.add(
        BulkEquipmentExclusion(
          code: bulkEquipmentDisplayCode(eq),
          reason:
              'Ο ${bulkEquipmentDisplayCode(eq)} αποδεσμεύεται από '
              '${owners.map(_ownerName).join(', ')} και γίνεται κοινόχρηστος '
              'του «$targetDisplayName».',
        ),
      );
    }
  }

  return BulkEquipmentTransferPlan(
    target: target,
    targetDisplayName: targetDisplayName,
    rowsToMove: rowsToMove,
    rowsAlreadyInTarget: rowsAlreadyInTarget,
    ownersToDetach: ownersToDetach,
    exclusions: exclusions,
  );
}

String bulkEquipmentTransferConfirmationText(BulkEquipmentTransferPlan plan) {
  final buf = StringBuffer();
  final n = plan.rowsToMove.length;
  buf.write(
    n == 1
        ? 'Θα μεταφερθεί 1 εξοπλισμός στο «${plan.targetDisplayName}»'
        : 'Θα μεταφερθούν $n εξοπλισμοί στο «${plan.targetDisplayName}»',
  );
  final codes = bulkEquipmentCodesPreview(plan.rowsToMove);
  if (codes.isNotEmpty) buf.write(': $codes');
  buf.write('.');
  if (plan.target.departmentId == null) {
    buf.write('\nΤο τμήμα «${plan.targetDisplayName}» θα δημιουργηθεί τώρα.');
  }
  if (plan.rowsAlreadyInTarget.isNotEmpty) {
    buf.write(
      '\n${plan.rowsAlreadyInTarget.length} από τους επιλεγμένους είναι '
      'ήδη εκεί και δεν αλλάζουν: '
      '${bulkEquipmentCodesPreview(plan.rowsAlreadyInTarget)}.',
    );
  }
  for (final ex in plan.exclusions) {
    buf.write('\n• ${ex.reason}');
  }
  return buf.toString();
}

String bulkEquipmentTransferResultMessage(BulkEquipmentTransferPlan plan) {
  final n = plan.rowsToMove.length;
  final buf = StringBuffer(
    n == 1
        ? 'Μεταφέρθηκε 1 εξοπλισμός στο «${plan.targetDisplayName}»'
        : 'Μεταφέρθηκαν $n εξοπλισμοί στο «${plan.targetDisplayName}»',
  );
  if (plan.detachedOwnerCount > 0) {
    buf.write(' · ${plan.detachedOwnerCount} αποδεσμεύτηκαν από κάτοχο');
  }
  buf.write('.');
  return buf.toString();
}

// ─────────────────────────── Αλλαγή κατόχου ───────────────────────────

/// Σχέδιο μαζικής αλλαγής κατόχου.
///
/// Απόφαση Διευθυντή 29/07: το τμήμα του εξοπλισμού **ακολουθεί** τον νέο
/// κάτοχο. Εξοπλισμός με περισσότερους από έναν κατόχους εξαιρείται, ώστε να
/// μη σβηστούν σιωπηλά οι υπόλοιποι.
class BulkEquipmentOwnerPlan {
  const BulkEquipmentOwnerPlan({
    required this.newOwner,
    required this.rowsToAssign,
    required this.exclusions,
  });

  final UserModel newOwner;
  final List<EquipmentRow> rowsToAssign;
  final List<BulkEquipmentExclusion> exclusions;

  bool get hasWork => rowsToAssign.isNotEmpty;
}

BulkEquipmentOwnerPlan buildBulkEquipmentOwnerPlan({
  required List<EquipmentRow> selectedRows,
  required UserModel newOwner,
  Map<int, List<UserModel>> ownersByEquipmentId = const {},
}) {
  final rowsToAssign = <EquipmentRow>[];
  final exclusions = <BulkEquipmentExclusion>[];

  for (final row in selectedRows) {
    final eq = row.$1;
    final eqId = eq.id;
    if (eqId == null) continue;
    final code = bulkEquipmentDisplayCode(eq);
    final owners = ownersByEquipmentId[eqId] ?? const <UserModel>[];

    if (owners.length > 1) {
      exclusions.add(
        BulkEquipmentExclusion(
          code: code,
          reason:
              'Ο $code έχει ${owners.length} κατόχους '
              '(${owners.map(_ownerName).join(', ')}) — άλλαξέ τον ατομικά '
              'ώστε να μη χαθεί κανένας.',
        ),
      );
      continue;
    }
    if (owners.length == 1 && owners.first.id == newOwner.id) {
      exclusions.add(
        BulkEquipmentExclusion(
          code: code,
          reason: 'Ο $code ανήκει ήδη στον ${_ownerName(newOwner)}.',
        ),
      );
      continue;
    }
    rowsToAssign.add(row);
  }

  return BulkEquipmentOwnerPlan(
    newOwner: newOwner,
    rowsToAssign: rowsToAssign,
    exclusions: exclusions,
  );
}

String bulkEquipmentOwnerConfirmationText(
  BulkEquipmentOwnerPlan plan, {
  String? newOwnerDepartmentName,
}) {
  final buf = StringBuffer(
    'Ο ${_ownerName(plan.newOwner)} θα γίνει κάτοχος '
    '${plan.rowsToAssign.length} εξοπλισμών: '
    '${bulkEquipmentCodesPreview(plan.rowsToAssign)}.',
  );
  final dept = newOwnerDepartmentName?.trim() ?? '';
  buf.write(
    dept.isEmpty
        ? '\nΟ νέος κάτοχος δεν έχει τμήμα — το τμήμα των εξοπλισμών μένει '
              'ως έχει.'
        : '\nΟι εξοπλισμοί περνούν και στο τμήμα του: «$dept».',
  );
  for (final ex in plan.exclusions) {
    buf.write('\n• ${ex.reason}');
  }
  return buf.toString();
}

String bulkEquipmentOwnerResultMessage(BulkEquipmentOwnerPlan plan) {
  final buf = StringBuffer(
    '${plan.rowsToAssign.length} εξοπλισμοί ανατέθηκαν στον '
    '${_ownerName(plan.newOwner)}',
  );
  if (plan.exclusions.isNotEmpty) {
    buf.write(' · ${plan.exclusions.length} εξαιρέσεις');
  }
  buf.write('.');
  return buf.toString();
}

// ───────────────────── Κύριο εργαλείο απομακρυσμένης ─────────────────────

/// Σχέδιο ορισμού κύριου εργαλείου.
///
/// Εξοπλισμός **χωρίς παράμετρο** για το εργαλείο εξαιρείται: αλλιώς
/// αναπαράγεται η γνωστή ασυνέπεια «αποθηκευμένο κύριο εργαλείο που δεν
/// αντιστοιχεί σε καμία ρυθμισμένη σύνδεση».
class BulkEquipmentPrimaryToolPlan {
  const BulkEquipmentPrimaryToolPlan({
    required this.tool,
    required this.rowsToApply,
    required this.exclusions,
  });

  final RemoteTool tool;
  final List<EquipmentRow> rowsToApply;
  final List<BulkEquipmentExclusion> exclusions;

  bool get hasWork => rowsToApply.isNotEmpty;
}

BulkEquipmentPrimaryToolPlan buildBulkEquipmentPrimaryToolPlan({
  required List<EquipmentRow> selectedRows,
  required RemoteTool tool,
}) {
  final rowsToApply = <EquipmentRow>[];
  final exclusions = <BulkEquipmentExclusion>[];

  for (final row in selectedRows) {
    final eq = row.$1;
    if (eq.id == null) continue;
    final code = bulkEquipmentDisplayCode(eq);
    if (eq.paramForTool(tool) == null) {
      exclusions.add(
        BulkEquipmentExclusion(
          code: code,
          reason:
              'Ο $code δεν έχει παράμετρο για ${tool.name} — θα έμενε με '
              'κύριο εργαλείο που δεν μπορεί να συνδεθεί.',
        ),
      );
      continue;
    }
    if (eq.defaultRemoteTool?.trim() == tool.id.toString()) continue;
    rowsToApply.add(row);
  }

  return BulkEquipmentPrimaryToolPlan(
    tool: tool,
    rowsToApply: rowsToApply,
    exclusions: exclusions,
  );
}

String bulkEquipmentPrimaryToolConfirmationText(
  BulkEquipmentPrimaryToolPlan plan,
) {
  final buf = StringBuffer(
    'Το ${plan.tool.name} θα γίνει κύριο εργαλείο σε '
    '${plan.rowsToApply.length} εξοπλισμούς: '
    '${bulkEquipmentCodesPreview(plan.rowsToApply)}.'
    '\nΟι παράμετροι σύνδεσης του καθενός δεν αλλάζουν.',
  );
  for (final ex in plan.exclusions) {
    buf.write('\n• ${ex.reason}');
  }
  return buf.toString();
}

// ─────────────────────────── Καθαρισμός πεδίου ───────────────────────────

/// Σχέδιο μαζικού καθαρισμού πεδίου εξοπλισμού.
class BulkEquipmentClearPlan {
  const BulkEquipmentClearPlan({
    required this.field,
    required this.rows,
    this.ownerFate = BulkEquipmentOwnerClearFate.shareInFormerOwnerDepartment,
    this.transferTarget,
    this.transferTargetDisplayName,
    this.ownersToDetach = const {},
    this.departmentFallbackByEquipmentId = const {},
    required this.exclusions,
  });

  final BulkEquipmentClearField field;
  final List<EquipmentRow> rows;
  final BulkEquipmentOwnerClearFate ownerFate;
  final SharedAssetTransferTarget? transferTarget;
  final String? transferTargetDisplayName;

  /// equipment.id → κάτοχοι που αποδεσμεύονται.
  final Map<int, List<int>> ownersToDetach;

  /// equipment.id → τμήμα που πρέπει να γραφτεί ώστε να μη μείνει ορφανός.
  final Map<int, int> departmentFallbackByEquipmentId;

  final List<BulkEquipmentExclusion> exclusions;

  bool get hasWork {
    switch (field) {
      case BulkEquipmentClearField.owner:
        return ownersToDetach.isNotEmpty;
      case BulkEquipmentClearField.notes:
        return rows.any((r) => (r.$1.notes ?? '').trim().isNotEmpty);
      case BulkEquipmentClearField.location:
        return rows.any((r) => (r.$1.location ?? '').trim().isNotEmpty);
      case BulkEquipmentClearField.remoteParams:
        return rows.any(
          (r) =>
              r.$1.remoteParams.isNotEmpty ||
              (r.$1.defaultRemoteTool ?? '').trim().isNotEmpty,
        );
    }
  }
}

/// Υπολογίζει το σχέδιο καθαρισμού ΧΩΡΙΣ πρόσβαση στη βάση (τεσταρίσιμο).
///
/// Κανόνας πεδίου «ο εξοπλισμός δεν μένει ποτέ ορφανός»: όταν αποδεσμεύεται ο
/// κάτοχος, γράφεται ρητά τμήμα στον εξοπλισμό (του πρώην κατόχου ή αυτό που
/// επιλέχθηκε). Αν δεν υπάρχει κανένα, ο εξοπλισμός εξαιρείται.
BulkEquipmentClearPlan buildBulkEquipmentClearPlan({
  required List<EquipmentRow> selectedRows,
  required BulkEquipmentClearField field,
  BulkEquipmentOwnerClearFate ownerFate =
      BulkEquipmentOwnerClearFate.shareInFormerOwnerDepartment,
  SharedAssetTransferTarget? transferTarget,
  String? transferTargetDisplayName,
  Map<int, List<UserModel>> ownersByEquipmentId = const {},
}) {
  final rows = [
    for (final r in selectedRows)
      if (r.$1.id != null) r,
  ];
  final ownersToDetach = <int, List<int>>{};
  final departmentFallback = <int, int>{};
  final exclusions = <BulkEquipmentExclusion>[];

  if (field == BulkEquipmentClearField.owner) {
    for (final row in rows) {
      final eq = row.$1;
      final eqId = eq.id!;
      final code = bulkEquipmentDisplayCode(eq);
      final owners = ownersByEquipmentId[eqId] ?? const <UserModel>[];
      if (owners.isEmpty) continue;

      final int? destination;
      if (ownerFate == BulkEquipmentOwnerClearFate.transfer) {
        // Νέο τμήμα: επιλύεται μέσα στη συναλλαγή, όχι εδώ.
        destination = transferTarget?.departmentId;
        if (destination == null && transferTarget?.newDepartmentName == null) {
          continue;
        }
      } else {
        destination = owners.first.departmentId ?? eq.departmentId;
        if (destination == null) {
          exclusions.add(
            BulkEquipmentExclusion(
              code: code,
              reason:
                  'Ο $code δεν αποδεσμεύεται — ούτε ο κάτοχος '
                  '${_ownerName(owners.first)} ούτε ο ίδιος έχουν τμήμα, '
                  'οπότε θα έμενε ορφανός.',
            ),
          );
          continue;
        }
      }

      ownersToDetach[eqId] = [
        for (final o in owners)
          if (o.id != null) o.id!,
      ];
      if (destination != null) departmentFallback[eqId] = destination;
    }
  }

  return BulkEquipmentClearPlan(
    field: field,
    rows: rows,
    ownerFate: ownerFate,
    transferTarget: transferTarget,
    transferTargetDisplayName: transferTargetDisplayName,
    ownersToDetach: ownersToDetach,
    departmentFallbackByEquipmentId: departmentFallback,
    exclusions: exclusions,
  );
}

String bulkEquipmentClearConfirmationText(BulkEquipmentClearPlan plan) {
  final buf = StringBuffer();
  switch (plan.field) {
    case BulkEquipmentClearField.owner:
      final affected = [
        for (final r in plan.rows)
          if (plan.ownersToDetach.containsKey(r.$1.id)) r,
      ];
      buf.write(
        'Θα αποδεσμευτούν ${affected.length} εξοπλισμοί από τον κάτοχό τους: '
        '${bulkEquipmentCodesPreview(affected)}.',
      );
      buf.write(
        plan.ownerFate == BulkEquipmentOwnerClearFate.transfer
            ? '\nΘα γίνουν κοινόχρηστοι του «'
                  '${plan.transferTargetDisplayName ?? ''}».'
            : '\nΘα γίνουν κοινόχρηστοι του τμήματος του πρώην κατόχου τους.',
      );
    case BulkEquipmentClearField.notes:
      final affected = [
        for (final r in plan.rows)
          if ((r.$1.notes ?? '').trim().isNotEmpty) r,
      ];
      buf.write(
        'Θα διαγραφούν οι σημειώσεις ${affected.length} εξοπλισμών: '
        '${bulkEquipmentCodesPreview(affected)}.',
      );
    case BulkEquipmentClearField.location:
      final affected = [
        for (final r in plan.rows)
          if ((r.$1.location ?? '').trim().isNotEmpty) r,
      ];
      buf.write(
        'Θα καθαριστεί η τοποθεσία ${affected.length} εξοπλισμών: '
        '${bulkEquipmentCodesPreview(affected)}.',
      );
    case BulkEquipmentClearField.remoteParams:
      final affected = [
        for (final r in plan.rows)
          if (r.$1.remoteParams.isNotEmpty ||
              (r.$1.defaultRemoteTool ?? '').trim().isNotEmpty)
            r,
      ];
      buf.write(
        'ΠΡΟΣΟΧΗ: θα σβηστούν ΟΛΕΣ οι παράμετροι απομακρυσμένης σύνδεσης '
        '(AnyDesk id, VNC host κ.λπ.) και το κύριο εργαλείο '
        '${affected.length} εξοπλισμών: '
        '${bulkEquipmentCodesPreview(affected)}.'
        '\nΟι τιμές αυτές είναι μοναδικές ανά μηχάνημα και δεν ξαναβρίσκονται '
        'εύκολα — μόνο η «Αναίρεση» τις επαναφέρει.',
      );
  }
  for (final ex in plan.exclusions) {
    buf.write('\n• ${ex.reason}');
  }
  return buf.toString();
}

String bulkEquipmentClearResultMessage(BulkEquipmentClearPlan plan) {
  final String head;
  switch (plan.field) {
    case BulkEquipmentClearField.owner:
      head = 'Αποδεσμεύτηκαν ${plan.ownersToDetach.length} εξοπλισμοί';
    case BulkEquipmentClearField.notes:
      head = 'Διαγράφηκαν οι σημειώσεις ${plan.rows.length} εξοπλισμών';
    case BulkEquipmentClearField.location:
      head = 'Καθαρίστηκε η τοποθεσία ${plan.rows.length} εξοπλισμών';
    case BulkEquipmentClearField.remoteParams:
      head =
          'Σβήστηκαν οι παράμετροι απομακρυσμένης ${plan.rows.length} '
          'εξοπλισμών';
  }
  final buf = StringBuffer(head);
  if (plan.exclusions.isNotEmpty) {
    buf.write(' · ${plan.exclusions.length} εξαιρέσεις');
  }
  buf.write('.');
  return buf.toString();
}

// ─────────────────────── Βοηθητικά ανάγνωσης σε txn ───────────────────────

const _kEquipmentUndoColumns = [
  'type',
  'notes',
  'location',
  'remote_params',
  'default_remote_tool',
  'department_id',
];

Future<Map<String, Object?>?> _equipmentSnapshotInTxn(
  DatabaseExecutor txn,
  int equipmentId,
) async {
  final rows = await txn.query(
    'equipment',
    columns: _kEquipmentUndoColumns,
    where: 'id = ?',
    whereArgs: [equipmentId],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return {for (final c in _kEquipmentUndoColumns) c: rows.first[c]};
}

Future<List<int>> _equipmentOwnerIdsInTxn(
  DatabaseExecutor txn,
  int equipmentId,
) async {
  final rows = await txn.query(
    'user_equipment',
    columns: ['user_id'],
    where: 'equipment_id = ?',
    whereArgs: [equipmentId],
  );
  return [
    for (final r in rows)
      if (r['user_id'] is int) r['user_id'] as int,
  ];
}

Future<int?> _activeDepartmentIdByNameInTxn(
  DatabaseExecutor txn,
  String name,
) async {
  final key = SearchTextNormalizer.normalizeForSearch(name.trim());
  if (key.isEmpty) return null;
  final rows = await txn.query(
    'departments',
    columns: ['id'],
    where: '${DirectorySupport.notDeletedClause} AND name_key = ?',
    whereArgs: [key],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first['id'] as int?;
}

/// Επιλύει τον προορισμό μεταφοράς μέσα στη συναλλαγή.
/// Επιστρέφει (id τμήματος, id ΜΟΝΟ αν δημιουργήθηκε τώρα).
Future<(int?, int?)> _resolveTargetInTxn(
  DatabaseExecutor txn,
  DepartmentRepository departments,
  SharedAssetTransferTarget target,
) async {
  if (target.departmentId != null) return (target.departmentId, null);
  final name = target.newDepartmentName?.trim();
  if (name == null || name.isEmpty) return (null, null);
  final existing = await _activeDepartmentIdByNameInTxn(txn, name);
  final id = await departments.getOrCreateDepartmentIdByName(
    name,
    executor: txn,
  );
  return (id, existing == null ? id : null);
}

// ─────────────────────── Εφαρμογές σε μία συναλλαγή ───────────────────────

/// Μαζική μεταφορά εξοπλισμού σε τμήμα ΜΕΣΑ στο [txn].
Future<BulkActionUndoRecord> applyBulkEquipmentTransferInTxn(
  DatabaseExecutor txn,
  Database db,
  BulkEquipmentTransferPlan plan,
) async {
  if (!plan.hasWork) return const BulkActionUndoRecord();

  final equipment = EquipmentRepository(db);
  final departments = DepartmentRepository(db);

  final (targetId, createdDepartmentId) = await _resolveTargetInTxn(
    txn,
    departments,
    plan.target,
  );
  if (targetId == null) return const BulkActionUndoRecord();

  final fieldsBefore = <int, Map<String, Object?>>{};
  final ownersBefore = <int, List<int>>{};

  for (final row in plan.rowsToMove) {
    final eqId = row.$1.id!;
    final snapshot = await _equipmentSnapshotInTxn(txn, eqId);
    if (snapshot == null) continue;
    fieldsBefore[eqId] = snapshot;

    if (plan.ownersToDetach.containsKey(eqId)) {
      ownersBefore[eqId] = await _equipmentOwnerIdsInTxn(txn, eqId);
      await equipment.replaceEquipmentUsers(eqId, const [], executor: txn);
    }
    await txn.update(
      'equipment',
      {'department_id': targetId},
      where: 'id = ?',
      whereArgs: [eqId],
    );
  }

  return BulkActionUndoRecord(
    equipmentFieldsBefore: fieldsBefore,
    equipmentOwnersBefore: ownersBefore,
    createdDepartmentId: createdDepartmentId,
  );
}

/// Μαζική ανάθεση κατόχου ΜΕΣΑ στο [txn] (το τμήμα ακολουθεί τον κάτοχο).
Future<BulkActionUndoRecord> applyBulkEquipmentOwnerInTxn(
  DatabaseExecutor txn,
  Database db,
  BulkEquipmentOwnerPlan plan,
) async {
  if (!plan.hasWork) return const BulkActionUndoRecord();
  final ownerId = plan.newOwner.id;
  if (ownerId == null) return const BulkActionUndoRecord();

  final equipment = EquipmentRepository(db);
  final fieldsBefore = <int, Map<String, Object?>>{};
  final ownersBefore = <int, List<int>>{};

  final ownerRows = await txn.query(
    'users',
    columns: ['department_id'],
    where: 'id = ?',
    whereArgs: [ownerId],
    limit: 1,
  );
  final ownerDeptId = ownerRows.isEmpty
      ? null
      : ownerRows.first['department_id'] as int?;

  for (final row in plan.rowsToAssign) {
    final eqId = row.$1.id!;
    final snapshot = await _equipmentSnapshotInTxn(txn, eqId);
    if (snapshot == null) continue;
    fieldsBefore[eqId] = snapshot;
    ownersBefore[eqId] = await _equipmentOwnerIdsInTxn(txn, eqId);

    await equipment.replaceEquipmentUsers(eqId, [ownerId], executor: txn);
    if (ownerDeptId != null) {
      await txn.update(
        'equipment',
        {'department_id': ownerDeptId},
        where: 'id = ?',
        whereArgs: [eqId],
      );
    }
  }

  return BulkActionUndoRecord(
    equipmentFieldsBefore: fieldsBefore,
    equipmentOwnersBefore: ownersBefore,
  );
}

/// Μαζική εγγραφή απλών στηλών (τύπος, τοποθεσία, σημειώσεις, κύριο εργαλείο).
Future<BulkActionUndoRecord> applyBulkEquipmentFieldInTxn(
  DatabaseExecutor txn,
  Database db, {
  required List<EquipmentRow> rows,
  required String column,
  required Object? value,
  BulkEquipmentNotesMode? notesMode,
}) async {
  if (rows.isEmpty) return const BulkActionUndoRecord();
  final fieldsBefore = <int, Map<String, Object?>>{};

  for (final row in rows) {
    final eqId = row.$1.id;
    if (eqId == null) continue;
    final snapshot = await _equipmentSnapshotInTxn(txn, eqId);
    if (snapshot == null) continue;
    fieldsBefore[eqId] = snapshot;

    Object? next = value;
    if (notesMode == BulkEquipmentNotesMode.append) {
      final before = (snapshot[column] as String?)?.trim() ?? '';
      final addition = (value as String?)?.trim() ?? '';
      next = before.isEmpty ? addition : '$before\n$addition';
    }
    await txn.update(
      'equipment',
      {column: next},
      where: 'id = ?',
      whereArgs: [eqId],
    );
  }

  return BulkActionUndoRecord(equipmentFieldsBefore: fieldsBefore);
}

/// Μαζικός καθαρισμός πεδίου εξοπλισμού ΜΕΣΑ στο [txn].
Future<BulkActionUndoRecord> applyBulkEquipmentClearInTxn(
  DatabaseExecutor txn,
  Database db,
  BulkEquipmentClearPlan plan,
) async {
  if (!plan.hasWork) return const BulkActionUndoRecord();

  final equipment = EquipmentRepository(db);
  final departments = DepartmentRepository(db);
  final fieldsBefore = <int, Map<String, Object?>>{};
  final ownersBefore = <int, List<int>>{};
  int? createdDepartmentId;

  int? transferTargetId;
  if (plan.field == BulkEquipmentClearField.owner &&
      plan.ownerFate == BulkEquipmentOwnerClearFate.transfer &&
      plan.transferTarget != null) {
    final (resolved, created) = await _resolveTargetInTxn(
      txn,
      departments,
      plan.transferTarget!,
    );
    transferTargetId = resolved;
    createdDepartmentId = created;
    if (transferTargetId == null) return const BulkActionUndoRecord();
  }

  for (final row in plan.rows) {
    final eq = row.$1;
    final eqId = eq.id!;

    switch (plan.field) {
      case BulkEquipmentClearField.owner:
        if (!plan.ownersToDetach.containsKey(eqId)) continue;
        final snapshot = await _equipmentSnapshotInTxn(txn, eqId);
        if (snapshot == null) continue;
        fieldsBefore[eqId] = snapshot;
        ownersBefore[eqId] = await _equipmentOwnerIdsInTxn(txn, eqId);
        await equipment.replaceEquipmentUsers(eqId, const [], executor: txn);
        final destination =
            transferTargetId ?? plan.departmentFallbackByEquipmentId[eqId];
        if (destination != null) {
          await txn.update(
            'equipment',
            {'department_id': destination},
            where: 'id = ?',
            whereArgs: [eqId],
          );
        }

      case BulkEquipmentClearField.notes:
        if ((eq.notes ?? '').trim().isEmpty) continue;
        final snapshot = await _equipmentSnapshotInTxn(txn, eqId);
        if (snapshot == null) continue;
        fieldsBefore[eqId] = snapshot;
        await txn.update(
          'equipment',
          {'notes': null},
          where: 'id = ?',
          whereArgs: [eqId],
        );

      case BulkEquipmentClearField.location:
        if ((eq.location ?? '').trim().isEmpty) continue;
        final snapshot = await _equipmentSnapshotInTxn(txn, eqId);
        if (snapshot == null) continue;
        fieldsBefore[eqId] = snapshot;
        await txn.update(
          'equipment',
          {'location': null},
          where: 'id = ?',
          whereArgs: [eqId],
        );

      case BulkEquipmentClearField.remoteParams:
        final hasParams =
            eq.remoteParams.isNotEmpty ||
            (eq.defaultRemoteTool ?? '').trim().isNotEmpty;
        if (!hasParams) continue;
        final snapshot = await _equipmentSnapshotInTxn(txn, eqId);
        if (snapshot == null) continue;
        fieldsBefore[eqId] = snapshot;
        await txn.update(
          'equipment',
          {'remote_params': null, 'default_remote_tool': null},
          where: 'id = ?',
          whereArgs: [eqId],
        );
    }
  }

  return BulkActionUndoRecord(
    equipmentFieldsBefore: fieldsBefore,
    equipmentOwnersBefore: ownersBefore,
    createdDepartmentId: createdDepartmentId,
  );
}
