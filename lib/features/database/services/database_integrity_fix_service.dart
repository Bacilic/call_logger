import 'package:sqflite_common/sqflite.dart';

import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../../../core/services/audit_service.dart';
import '../../../features/tasks/services/task_service.dart';
import '../models/database_integrity_finding.dart';
import '../models/integrity_fix_models.dart';
import 'integrity_audit_details_builder.dart';

/// Μηχανισμός εκτέλεσης επιδιορθώσεων ακεραιότητας (transactions + audit).
class DatabaseIntegrityFixService {
  DatabaseIntegrityFixService({
    DirectoryRepository Function(Database db)? directoryFactory,
    CallsRepository Function(Database db)? callsFactory,
    TaskService Function()? taskServiceFactory,
    IntegrityAuditDetailsBuilder? auditBuilder,
  })  : _directoryFactory = directoryFactory ?? ((db) => DirectoryRepository(db)),
        _callsFactory = callsFactory ?? ((db) => CallsRepository(db)),
        _taskServiceFactory = taskServiceFactory ?? TaskService.new,
        _audit = auditBuilder ?? const IntegrityAuditDetailsBuilder();

  final DirectoryRepository Function(Database db) _directoryFactory;
  final CallsRepository Function(Database db) _callsFactory;
  final TaskService Function() _taskServiceFactory;
  final IntegrityAuditDetailsBuilder _audit;

  static const int _maxAutoRetries = 2;
  static const Duration _retryDelay = Duration(milliseconds: 250);

  Future<IntegrityFixResult> applyFix(
    DatabaseIntegrityFinding finding,
    IntegrityFixDecision decision, {
    int autoRetryAttempt = 0,
  }) async {
    if (finding.checkType == IntegrityCheckType.pragmaQuickCheck) {
      return const IntegrityFixFailure(
        'Δεν επιτρέπεται inline επιδιόρθωση PRAGMA corruption.',
      );
    }

    try {
      await _executeFix(finding, decision);
      return const IntegrityFixSuccess();
    } catch (e) {
      if (_isLockFailure(e) && autoRetryAttempt < _maxAutoRetries) {
        await Future<void>.delayed(_retryDelay);
        return applyFix(
          finding,
          decision,
          autoRetryAttempt: autoRetryAttempt + 1,
        );
      }
      if (_isLockFailure(e)) {
        final db = await DatabaseHelper.instance.database;
        return IntegrityFixLockFailure(
          dbPath: db.path,
          message:
              'Η βάση δεδομένων είναι κλειδωμένη. Κλείστε άλλες εφαρμογές που τη χρησιμοποιούν και δοκιμάστε ξανά.',
          findingKey: finding.findingKey,
        );
      }
      return IntegrityFixFailure('$e');
    }
  }

  Future<IntegrityBulkFixResult> applyBulkFix(
    List<DatabaseIntegrityFinding> findings,
  ) async {
    final results = <IntegrityFixResult>[];
    for (final finding in findings) {
      results.add(await applyFix(finding, const IntegrityFixConfirm()));
    }
    return IntegrityBulkFixResult(results: results, findings: findings);
  }

  Future<void> _executeFix(
    DatabaseIntegrityFinding finding,
    IntegrityFixDecision decision,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final dir = _directoryFactory(db);
    final calls = _callsFactory(db);
    final tasks = _taskServiceFactory();

    switch (finding.checkType) {
      case IntegrityCheckType.orphanPhone:
        await _fixOrphanPhone(dir, finding, decision);
      case IntegrityCheckType.callsMissingSearchIndex:
        await _fixCallSearchIndex(db, calls, dir, finding);
      case IntegrityCheckType.tasksMissingSearchIndex:
        await _fixTaskSearchIndex(db, tasks, dir, finding);
      case IntegrityCheckType.usersWithoutDepartment:
        await _fixUserWithoutDepartment(dir, db, finding, decision);
      case IntegrityCheckType.usersInvalidDepartment:
        await _fixUserInvalidDepartment(dir, db, finding, decision);
      case IntegrityCheckType.tasksInvalidCall:
        await _fixTaskInvalidCall(db, dir, tasks, finding, decision);
      case IntegrityCheckType.departmentsInvalidNameKey:
        await _fixDepartmentNameKey(dir, finding);
      case IntegrityCheckType.orphanCallExternalLinks:
        await _fixOrphanCallExternalLink(dir, finding);
      case IntegrityCheckType.orphanUserPhones:
        await _fixOrphanUserPhones(dir, finding);
      case IntegrityCheckType.orphanDepartmentPhones:
        await _fixOrphanDepartmentPhones(dir, finding);
      case IntegrityCheckType.orphanUserEquipment:
        await _fixOrphanUserEquipment(dir, finding);
      case IntegrityCheckType.callsDeletedLinkedEntities:
        await _fixCallDeletedFk(db, calls, dir, finding, decision);
      case IntegrityCheckType.tasksDeletedLinkedEntities:
        await _fixTaskDeletedFk(db, dir, finding, decision);
      case IntegrityCheckType.tasksTemporalInconsistency:
        await _fixTaskTemporal(db, dir, finding);
      case IntegrityCheckType.auditMissingSearchText:
        await _fixAuditSearchText(db, dir, finding);
      case IntegrityCheckType.pragmaQuickCheck:
        break;
    }
  }

  Future<void> _fixOrphanPhone(
    DirectoryRepository dir,
    DatabaseIntegrityFinding finding,
    IntegrityFixDecision decision,
  ) async {
    final phoneId = _ctxInt(finding, 'phone_id') ?? finding.affectedId;
    if (phoneId == null) return;

    final auditPack = _audit.simpleAction(
      details: _audit.orphanPhoneActionDescription(decision),
      oldValues: {'phone_id': phoneId},
      newValues: const {'integrity_fix': true},
    );

    switch (decision) {
      case IntegrityFixSoftDeletePhone():
        await dir.softDeletePhoneForIntegrity(
          phoneId: phoneId,
          details: auditPack.details,
          oldValues: auditPack.oldValues,
          newValues: auditPack.newValues,
        );
      case IntegrityFixLinkPhoneToDepartment(:final departmentId):
        await dir.linkOrphanPhoneToDepartmentForIntegrity(
          phoneId: phoneId,
          departmentId: departmentId,
          details: auditPack.details,
          oldValues: auditPack.oldValues,
          newValues: {
            ...auditPack.newValues,
            'department_id': departmentId,
          },
        );
      case IntegrityFixLinkPhoneToUser(:final userId):
        await dir.linkOrphanPhoneToUserForIntegrity(
          phoneId: phoneId,
          userId: userId,
          details: auditPack.details,
          oldValues: auditPack.oldValues,
          newValues: {
            ...auditPack.newValues,
            'user_id': userId,
          },
        );
      default:
        throw ArgumentError('Απαιτείται επιλογή για ορφανό τηλέφωνο.');
    }
  }

  Future<void> _fixCallSearchIndex(
    Database db,
    CallsRepository calls,
    DirectoryRepository dir,
    DatabaseIntegrityFinding finding,
  ) async {
    final callId = _ctxInt(finding, 'call_id') ?? finding.affectedId;
    if (callId == null) return;
    final rows = await db.query(
      'calls',
      where: 'id = ?',
      whereArgs: [callId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final oldIndex = rows.first['search_index'];
    await calls.rebuildSearchIndexForCallId(callId);
    await db.transaction((txn) async {
      final ap = await AuditService.performingUser(txn);
      final pack = _audit.simpleAction(
        details: 'Αναδημιουργία ευρετηρίου αναζήτησης για κλήση ID $callId',
        oldValues: {'search_index': oldIndex},
        newValues: const {'search_index': 'rebuilt'},
      );
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: pack.details,
        entityType: AuditEntityTypes.call,
        entityId: callId,
        oldValues: pack.oldValues,
        newValues: pack.newValues,
      );
    });
  }

  Future<void> _fixTaskSearchIndex(
    Database db,
    TaskService tasks,
    DirectoryRepository dir,
    DatabaseIntegrityFinding finding,
  ) async {
    final taskId = _ctxInt(finding, 'task_id') ?? finding.affectedId;
    if (taskId == null) return;
    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final oldIndex = rows.first['search_index'];
    final title = rows.first['title']?.toString();
    await tasks.rebuildSearchIndexForTaskId(taskId);
    await db.transaction((txn) async {
      final ap = await AuditService.performingUser(txn);
      final pack = _audit.simpleAction(
        details:
            'Αναδημιουργία ευρετηρίου αναζήτησης για εκκρεμότητα ID $taskId',
        oldValues: {'search_index': oldIndex},
        newValues: const {'search_index': 'rebuilt'},
      );
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: pack.details,
        entityType: AuditEntityTypes.task,
        entityId: taskId,
        entityName: title,
        oldValues: pack.oldValues,
        newValues: pack.newValues,
      );
    });
  }

  Future<void> _fixUserWithoutDepartment(
    DirectoryRepository dir,
    Database db,
    DatabaseIntegrityFinding finding,
    IntegrityFixDecision decision,
  ) async {
    final userId = _ctxInt(finding, 'user_id') ?? finding.affectedId;
    if (userId == null) return;

    final userLabel = await dir.integrityUserLabel(db, userId);

    switch (decision) {
      case IntegrityFixSoftDeleteUser():
        final pack = _audit.simpleAction(
          details: 'Διαγραφή $userLabel (χωρίς τμήμα)',
          oldValues: {'user_id': userId, 'department_id': null},
          newValues: const {'is_deleted': 1},
        );
        await dir.softDeleteUserForIntegrity(
          userId: userId,
          details: pack.details,
          oldValues: pack.oldValues,
          newValues: pack.newValues,
        );
      case IntegrityFixAssignDepartment(:final departmentId):
        final deptLabel =
            await dir.integrityDepartmentLabel(db, departmentId);
        final pack = _audit.userDepartmentChange(
          userLabel: userLabel,
          oldDepartmentLabel: '—',
          newDepartmentLabel: deptLabel,
          oldDepartmentId: null,
          newDepartmentId: departmentId,
        );
        await dir.updateUserDepartmentForIntegrity(
          userId: userId,
          departmentId: departmentId,
          details: pack.details,
          oldValues: pack.oldValues,
          newValues: pack.newValues,
        );
      default:
        throw ArgumentError('Απαιτείται μεταφορά σε τμήμα ή διαγραφή υπαλλήλου.');
    }
  }

  Future<void> _fixUserInvalidDepartment(
    DirectoryRepository dir,
    Database db,
    DatabaseIntegrityFinding finding,
    IntegrityFixDecision decision,
  ) async {
    final userId = _ctxInt(finding, 'user_id') ?? finding.affectedId;
    final oldDeptId = _ctxInt(finding, 'department_id');
    if (userId == null) return;

    if (decision is! IntegrityFixAssignDepartment) {
      throw ArgumentError('Απαιτείται μεταφορά σε ενεργό τμήμα.');
    }
    final newDeptId = decision.departmentId;

    final userLabel = await dir.integrityUserLabel(db, userId);
    final oldLabel = await dir.integrityDepartmentLabel(db, oldDeptId);
    final newLabel = await dir.integrityDepartmentLabel(db, newDeptId);
    final pack = _audit.userDepartmentChange(
      userLabel: userLabel,
      oldDepartmentLabel: oldLabel,
      newDepartmentLabel: newLabel,
      oldDepartmentId: oldDeptId,
      newDepartmentId: newDeptId,
    );
    await dir.updateUserDepartmentForIntegrity(
      userId: userId,
      departmentId: newDeptId,
      details: pack.details,
      oldValues: pack.oldValues,
      newValues: pack.newValues,
    );
  }

  Future<void> _fixTaskInvalidCall(
    Database db,
    DirectoryRepository dir,
    TaskService tasks,
    DatabaseIntegrityFinding finding,
    IntegrityFixDecision decision,
  ) async {
    final taskId = _ctxInt(finding, 'task_id') ?? finding.affectedId;
    if (taskId == null) return;

    if (decision is! IntegrityFixConfirm) {
      throw ArgumentError('Μόνο εκκαθάριση κλήσης (NULL) επιτρέπεται.');
    }
    const int? newCallId = null;

    await db.transaction((txn) async {
      final oldRow = await dir.integrityUpdateTaskFk(
        txn,
        taskId,
        'call_id',
        newCallId,
      );
      if (oldRow == null) return;
      final ap = await AuditService.performingUser(txn);
      final pack = _audit.fkChange(
        entityLabel: 'Εκκρεμότητα ID $taskId',
        fieldLabel: 'call_id',
        oldValue: oldRow['call_id'],
        newValue: newCallId,
        actionDescription: 'Επιδιόρθωση άκυρης αναφοράς κλήσης',
      );
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: pack.details,
        entityType: AuditEntityTypes.task,
        entityId: taskId,
        entityName: oldRow['title']?.toString(),
        oldValues: pack.oldValues,
        newValues: pack.newValues,
      );
    });
  }

  Future<void> _fixDepartmentNameKey(
    DirectoryRepository dir,
    DatabaseIntegrityFinding finding,
  ) async {
    final departmentId =
        _ctxInt(finding, 'department_id') ?? finding.affectedId;
    final expected = finding.context['expectedNameKey'] as String?;
    if (departmentId == null || expected == null) return;

    final current = finding.context['currentNameKey'] as String? ?? '';
    final pack = _audit.simpleAction(
      details:
          'Διόρθωση name_key τμήματος ID $departmentId σε «$expected»',
      oldValues: {'name_key': current.isEmpty ? null : current},
      newValues: {'name_key': expected},
    );
    await dir.fixDepartmentNameKeyForIntegrity(
      departmentId: departmentId,
      nameKey: expected,
      details: pack.details,
      oldValues: pack.oldValues,
      newValues: pack.newValues,
    );
  }

  Future<void> _fixOrphanCallExternalLink(
    DirectoryRepository dir,
    DatabaseIntegrityFinding finding,
  ) async {
    final linkId = _ctxInt(finding, 'link_id') ?? finding.affectedId;
    if (linkId == null) return;
    final callId = finding.context['call_id'];
    final pack = _audit.simpleAction(
      details: 'Διαγραφή ορφανού call_external_link ID $linkId (call_id=$callId)',
      oldValues: {'link_id': linkId, 'call_id': callId},
      newValues: const {'removed': true},
    );
    await dir.deleteCallExternalLinkForIntegrity(
      linkId: linkId,
      details: pack.details,
      oldValues: pack.oldValues,
      newValues: pack.newValues,
    );
  }

  Future<void> _fixOrphanUserPhones(
    DirectoryRepository dir,
    DatabaseIntegrityFinding finding,
  ) async {
    final userId = _ctxInt(finding, 'user_id');
    final phoneId = _ctxInt(finding, 'phone_id');
    if (userId == null || phoneId == null) return;
    final pack = _audit.junctionCleanup(finding: finding);
    await dir.deleteOrphanUserPhonesJunction(
      userId: userId,
      phoneId: phoneId,
      details: pack.details,
      oldValues: pack.oldValues,
      newValues: pack.newValues,
    );
  }

  Future<void> _fixOrphanDepartmentPhones(
    DirectoryRepository dir,
    DatabaseIntegrityFinding finding,
  ) async {
    final departmentId = _ctxInt(finding, 'department_id');
    final phoneId = _ctxInt(finding, 'phone_id');
    if (departmentId == null || phoneId == null) return;
    final pack = _audit.junctionCleanup(finding: finding);
    await dir.deleteOrphanDepartmentPhonesJunction(
      departmentId: departmentId,
      phoneId: phoneId,
      details: pack.details,
      oldValues: pack.oldValues,
      newValues: pack.newValues,
    );
  }

  Future<void> _fixOrphanUserEquipment(
    DirectoryRepository dir,
    DatabaseIntegrityFinding finding,
  ) async {
    final userId = _ctxInt(finding, 'user_id');
    final equipmentId = _ctxInt(finding, 'equipment_id');
    if (userId == null || equipmentId == null) return;
    final pack = _audit.junctionCleanup(finding: finding);
    await dir.deleteOrphanUserEquipmentJunction(
      userId: userId,
      equipmentId: equipmentId,
      details: pack.details,
      oldValues: pack.oldValues,
      newValues: pack.newValues,
    );
  }

  Future<void> _fixCallDeletedFk(
    Database db,
    CallsRepository calls,
    DirectoryRepository dir,
    DatabaseIntegrityFinding finding,
    IntegrityFixDecision decision,
  ) async {
    final callId = _ctxInt(finding, 'call_id') ?? finding.affectedId;
    final field = finding.context['invalidField'] as String?;
    if (callId == null || field == null) return;

    if (decision is! IntegrityFixConfirm) {
      throw ArgumentError(
        'Μόνο εκκαθάριση ανύπαρκτης αναφοράς (NULL) επιτρέπεται.',
      );
    }
    const int? newValue = null;

    await db.transaction((txn) async {
      final oldRow = await calls.integrityUpdateCallFk(
        txn,
        callId,
        field,
        newValue,
      );
      if (oldRow == null) return;
      final ap = await AuditService.performingUser(txn);
      final pack = _audit.fkChange(
        entityLabel: 'Κλήση ID $callId',
        fieldLabel: field,
        oldValue: oldRow[field],
        newValue: newValue,
        actionDescription:
            'Εκκαθάριση ανύπαρκτης αναφοράς κλήσης (snapshot διατηρείται)',
      );
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: pack.details,
        entityType: AuditEntityTypes.call,
        entityId: callId,
        oldValues: pack.oldValues,
        newValues: pack.newValues,
      );
    });
  }

  Future<void> _fixTaskDeletedFk(
    Database db,
    DirectoryRepository dir,
    DatabaseIntegrityFinding finding,
    IntegrityFixDecision decision,
  ) async {
    final taskId = _ctxInt(finding, 'task_id') ?? finding.affectedId;
    final field = finding.context['invalidField'] as String?;
    if (taskId == null || field == null) return;

    if (decision is! IntegrityFixConfirm) {
      throw ArgumentError(
        'Μόνο εκκαθάριση ανύπαρκτης αναφοράς (NULL) επιτρέπεται.',
      );
    }
    const int? newValue = null;

    await db.transaction((txn) async {
      final oldRow = await dir.integrityUpdateTaskFk(
        txn,
        taskId,
        field,
        newValue,
      );
      if (oldRow == null) return;
      final ap = await AuditService.performingUser(txn);
      final pack = _audit.fkChange(
        entityLabel: 'Εκκρεμότητα ID $taskId',
        fieldLabel: field,
        oldValue: oldRow[field],
        newValue: newValue,
        actionDescription:
            'Εκκαθάριση ανύπαρκτης αναφοράς εκκρεμότητας (snapshot διατηρείται)',
      );
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: pack.details,
        entityType: AuditEntityTypes.task,
        entityId: taskId,
        entityName: oldRow['title']?.toString(),
        oldValues: pack.oldValues,
        newValues: pack.newValues,
      );
    });
  }

  Future<void> _fixTaskTemporal(
    Database db,
    DirectoryRepository dir,
    DatabaseIntegrityFinding finding,
  ) async {
    final taskId = _ctxInt(finding, 'task_id') ?? finding.affectedId;
    if (taskId == null) return;

    await db.transaction((txn) async {
      final oldRow = await dir.integritySyncTaskTimestamps(txn, taskId);
      if (oldRow == null) return;
      final ap = await AuditService.performingUser(txn);
      final created = oldRow['created_at'];
      final pack = _audit.simpleAction(
        details:
            'Συγχρονισμός updated_at = created_at για εκκρεμότητα ID $taskId',
        oldValues: {
          'created_at': created,
          'updated_at': oldRow['updated_at'],
        },
        newValues: {
          'created_at': created,
          'updated_at': created,
        },
      );
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: pack.details,
        entityType: AuditEntityTypes.task,
        entityId: taskId,
        entityName: oldRow['title']?.toString(),
        oldValues: pack.oldValues,
        newValues: pack.newValues,
      );
    });
  }

  Future<void> _fixAuditSearchText(
    Database db,
    DirectoryRepository dir,
    DatabaseIntegrityFinding finding,
  ) async {
    final auditId = _ctxInt(finding, 'audit_id') ?? finding.affectedId;
    if (auditId == null) return;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'audit_log',
        where: 'id = ?',
        whereArgs: [auditId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      await AuditService.rebuildAndPersistSearchText(txn, auditId);
      final ap = await AuditService.performingUser(txn);
      final pack = _audit.simpleAction(
        details: 'Ανακατασκευή search_text για audit ID $auditId',
        oldValues: {'search_text': rows.first['search_text']},
        newValues: const {'search_text': 'rebuilt'},
      );
      await AuditService.log(
        txn,
        action: DatabaseHelper.auditActionIntegrityFix,
        userPerforming: ap,
        details: pack.details,
        entityType: AuditEntityTypes.maintenance,
        entityId: auditId,
        oldValues: pack.oldValues,
        newValues: pack.newValues,
      );
    });
  }

  int? _ctxInt(DatabaseIntegrityFinding finding, String key) {
    final v = finding.context[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  bool _isLockFailure(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('sqlite_busy') ||
        s.contains('database is locked') ||
        s.contains('locked');
  }
}
