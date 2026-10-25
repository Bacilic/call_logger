import 'dart:convert';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/tasks/models/task.dart';
import '../../features/tasks/models/task_analytics_summary.dart';
import '../../features/tasks/models/task_filter.dart'
    show TaskFilter, TaskSortOption;
import '../../features/tasks/models/task_notification.dart';
import '../../features/tasks/models/task_settings_config.dart';
import '../../features/tasks/services/call_task_solution_bridge.dart';
import '../../features/tasks/utils/task_due_date_calculator.dart';
import 'calls_repository.dart';
import '../errors/task_deleted_elsewhere_exception.dart';
import '../errors/task_save_exception.dart';
import '../errors/task_stale_exception.dart';
import '../services/current_operator.dart';
import '../utils/search_text_normalizer.dart';
import 'audit_service.dart';
import 'database_helper.dart';
import 'directory_support.dart';
import 'integrity_service.dart';
import 'settings_repository.dart';
import 'task_notifications_repository.dart';
import 'tasks_analytics_repository.dart';
import 'sql_like.dart';

/// Κλήση με status pending που δεν έχει αντίστοιχο task.
class OrphanCall {
  const OrphanCall({
    required this.id,
    this.date,
    this.time,
    this.callerId,
    this.callerText,
    this.issue,
  });

  final int id;
  final String? date;
  final String? time;
  final int? callerId;
  final String? callerText;
  final String? issue;
}

/// Repository εκκρεμοτήτων (πίνακας `tasks`).
///
/// **Αξιολογήθηκε για διάσπαση (13/10/2026) — ο πυρήνας μένει ενιαίος.**
/// Κρατά νόμιμα δύο συνεκτικούς ρόλους: τις **εγγραφές** (δημιουργία,
/// επεξεργασία, κλείσιμο, ανάθεση, γρήγορη προσθήκη) και τη **λίστα με τα
/// φίλτρα της**. Οι εγγραφές δεν χωρίζονται γιατί αποθήκευση, φρουρός
/// διένεξης, ειδοποιήσεις και Ιστορικό είναι μία πράξη στην ίδια συναλλαγή,
/// πάνω στους ίδιους κοινούς κανόνες (ποιος κατέχει, πότε σφραγίζεται η
/// ολοκλήρωση). Η λίστα, οι μετρητές και οι επιλογές «ποιανού» μοιράζονται
/// ένα φίλτρο, ώστε να μην μπορούν να αποκλίνουν.
///
/// Η Ανάλυση ζει στο [TasksAnalyticsRepository] και η προθεσμία στο
/// [TaskDueDateCalculator]· εδώ μένουν μόνο οι πόρτες τους. **Η ετυμηγορία
/// παύει να ισχύει** αν μπει εδώ αναφορά μόνο ανάγνωσης, καθαρός υπολογισμός
/// χωρίς βάση, ή δουλειά άλλου πίνακα.
class TasksRepository {
  Future<Database> get _db => DatabaseHelper.instance.database;
  bool? _hasSnoozeHistoryColumnCache;

  static const List<String> _kTaskAuditKeys = [
    'call_id',
    'caller_id',
    'equipment_id',
    'department_id',
    'phone_id',
    'phone_text',
    'user_text',
    'equipment_text',
    'department_text',
    'title',
    'description',
    'due_date',
    'snooze_until',
    'status',
    'origin',
    'priority',
    'solution_notes',
    'is_deleted',
  ];

  Future<void> _auditTaskCreate(
    DatabaseExecutor executor,
    int id,
    Map<String, dynamic> row,
  ) async {
    final user = AuditService.performingUser();
    final nv = <String, dynamic>{};
    for (final k in _kTaskAuditKeys) {
      if (row.containsKey(k) && row[k] != null) nv[k] = row[k];
    }
    await AuditService.log(
      executor,
      action: 'ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ',
      userPerforming: user,
      details: 'tasks id=$id',
      entityType: AuditEntityTypes.task,
      entityId: id,
      entityName: row['title']?.toString(),
      newValues: nv.isEmpty ? null : nv,
    );
  }

  Future<void> _auditTaskUpdate(
    DatabaseExecutor executor,
    int id,
    Map<String, dynamic> oldRow,
    Map<String, dynamic> newMap,
  ) async {
    final oldDiff = <String, dynamic>{};
    final newDiff = <String, dynamic>{};
    for (final k in _kTaskAuditKeys) {
      // Πεδίο που δεν γράφτηκε δεν άλλαξε (π.χ. το «διαγραμμένη», που η
      // επεξεργασία δεν αγγίζει ποτέ).
      if (!newMap.containsKey(k)) continue;
      final a = oldRow[k];
      final b = newMap[k];
      if ('${a ?? ''}' != '${b ?? ''}') {
        oldDiff[k] = a;
        newDiff[k] = b;
      }
    }
    // Η ανάθεση γράφεται στο Ιστορικό ως ΟΝΟΜΑ, όχι ως αριθμός: η εγγραφή
    // διαβάζεται και ψάχνεται χωρίς να χρειάζεται μετάφραση, και επιβιώνει
    // ακόμη κι αν το προφίλ διαγραφεί κάποτε.
    final oldAssigned = oldRow['assigned_operator_id'];
    final newAssigned = newMap['assigned_operator_id'];
    if ('${oldAssigned ?? ''}' != '${newAssigned ?? ''}') {
      oldDiff['assigned_operator'] = await _operatorNameForAudit(
        executor,
        oldAssigned,
      );
      newDiff['assigned_operator'] = await _operatorNameForAudit(
        executor,
        newAssigned,
      );
    }
    if (newDiff.isEmpty) return;
    final user = AuditService.performingUser();
    await AuditService.log(
      executor,
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΚΚΡΕΜΟΤΗΤΑΣ',
      userPerforming: user,
      details: 'tasks id=$id',
      entityType: AuditEntityTypes.task,
      entityId: id,
      entityName: newMap['title']?.toString() ?? oldRow['title']?.toString(),
      oldValues: oldDiff,
      newValues: newDiff,
    );
  }

  /// Ποιος κατέχει την εκκρεμότητα: ο υπεύθυνος, ή ο δημιουργός όταν δεν
  /// υπάρχει ανάθεση.
  ///
  /// Ίδια φόρμουλα με το φίλτρο χρήστη και με τα σήματα της κάρτας: η
  /// ανανάθετη εκκρεμότητα **ανήκει** σε αυτόν που την άνοιξε, και πρέπει να
  /// μάθει ότι κάποιος την έκλεισε γι' αυτόν.
  static int? _ownerOf(Map<String, dynamic>? row) {
    if (row == null) return null;
    return (row['assigned_operator_id'] as int?) ??
        (row['created_by_operator_id'] as int?);
  }

  /// Η μετακίνηση της ευθύνης αναγγέλλεται **και στις δύο κατευθύνσεις**.
  ///
  /// Η ανάθεση και η αφαίρεσή της είναι η ίδια πράξη με αντίθετη φορά: ο ένας
  /// μαθαίνει ότι απέκτησε δουλειά, ο άλλος ότι δεν τη χρωστά πια. Σε
  /// μεταβίβαση συμβαίνουν ταυτόχρονα, και ειδοποιούνται και οι δύο.
  ///
  /// Ένα σημείο για κάθε πύλη που αλλάζει υπεύθυνο — τη γρήγορη ανάθεση του
  /// μενού, τη φόρμα επεξεργασίας και τη δημιουργία με ανάθεση εξαρχής.
  static Future<void> _notifyAssignmentChange(
    DatabaseExecutor executor, {
    required int taskId,
    required int? previousOwner,
    required int? nextOwner,
  }) async {
    if (previousOwner == nextOwner) return;
    final actorId = CurrentOperator.active?.id;
    await TaskNotificationsRepository.record(
      executor,
      recipientOperatorId: nextOwner,
      taskId: taskId,
      kind: TaskNotificationKind.assigned,
      actorOperatorId: actorId,
    );
    await TaskNotificationsRepository.record(
      executor,
      recipientOperatorId: previousOwner,
      taskId: taskId,
      kind: TaskNotificationKind.unassigned,
      actorOperatorId: actorId,
    );
  }

  /// Το κλείσιμο αναγγέλλεται σε όποιον κατείχε την εκκρεμότητα.
  ///
  /// Διαβάζει την **παλιά** γραμμή: ο κάτοχος είναι αυτός που τη χρωστούσε
  /// πριν κλείσει, όχι ό,τι γράφεται μαζί με το κλείσιμο.
  static Future<void> _notifyClosure(
    DatabaseExecutor executor, {
    required int taskId,
    required Map<String, dynamic>? oldRow,
  }) async {
    await TaskNotificationsRepository.record(
      executor,
      recipientOperatorId: _ownerOf(oldRow),
      taskId: taskId,
      kind: TaskNotificationKind.closed,
      actorOperatorId: CurrentOperator.active?.id,
    );
  }

  /// Το όνομα του χειριστή όπως γράφεται στο Ιστορικό — «Χωρίς ανάθεση» για
  /// το κενό, το ωμό id όταν το προφίλ δεν βρίσκεται πια.
  static Future<String> _operatorNameForAudit(
    DatabaseExecutor executor,
    Object? operatorId,
  ) async {
    if (operatorId == null) return 'Χωρίς ανάθεση';
    final rows = await executor.query(
      'operators',
      columns: ['display_name'],
      where: 'id = ?',
      whereArgs: [operatorId],
      limit: 1,
    );
    final name = rows.isEmpty ? '' : '${rows.first['display_name'] ?? ''}';
    return name.trim().isEmpty ? 'Χρήστης #$operatorId' : name.trim();
  }

  /// Γρήγορη ανάθεση από το μενού της κάρτας — αλλάζει ΜΟΝΟ τον υπεύθυνο.
  ///
  /// `null` σημαίνει «Χωρίς ανάθεση»: η εκκρεμότητα επιστρέφει στη λίστα
  /// όποιου την άνοιξε. Ίδια τιμή με τη σημερινή δεν γράφει τίποτα — ούτε στη
  /// βάση ούτε στο Ιστορικό.
  Future<void> assignTask(int taskId, int? operatorId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'tasks',
        columns: ['assigned_operator_id', 'created_by_operator_id', 'title'],
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final current = rows.first['assigned_operator_id'] as int?;
      if (current == operatorId) return;
      // Ο κάτοχος ΠΡΙΝ την αλλαγή: χωρίς ανάθεση, η εκκρεμότητα ανήκει σε
      // αυτόν που την άνοιξε — κι εκείνος πρέπει να μάθει ότι του την πήραν.
      final previousOwner = _ownerOf(Map<String, dynamic>.from(rows.first));

      await txn.update(
        'tasks',
        {
          'assigned_operator_id': operatorId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [taskId],
      );

      await _notifyAssignmentChange(
        txn,
        taskId: taskId,
        previousOwner: previousOwner,
        nextOwner: operatorId ?? (rows.first['created_by_operator_id'] as int?),
      );

      final user = AuditService.performingUser();
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΚΚΡΕΜΟΤΗΤΑΣ',
        userPerforming: user,
        details: 'tasks id=$taskId',
        entityType: AuditEntityTypes.task,
        entityId: taskId,
        entityName: rows.first['title']?.toString(),
        oldValues: {
          'assigned_operator': await _operatorNameForAudit(txn, current),
        },
        newValues: {
          'assigned_operator': await _operatorNameForAudit(txn, operatorId),
        },
      );
    });
  }

  Future<bool> _hasSnoozeHistoryColumn(Database db) async {
    final cached = _hasSnoozeHistoryColumnCache;
    if (cached != null) return cached;
    final info = await db.rawQuery('PRAGMA table_info(tasks)');
    final has = info.any((row) => row['name'] == 'snooze_history_json');
    _hasSnoozeHistoryColumnCache = has;
    return has;
  }

  /// Καθαρισμός cache στηλής `snooze_history_json` μετά από migration ή αλλαγή βάσης.
  void resetSnoozeHistoryColumnCache() {
    _hasSnoozeHistoryColumnCache = null;
  }

  /// Γενικές ρυθμίσεις εκκρεμοτήτων από `app_settings` (JSON).
  ///
  /// - Διαβάζει πρώτα από [TaskSettingsConfig.appSettingsKey].
  /// - Αν λείπει, κάνει fallback στο [TaskSettingsConfig.legacyAppSettingsKey].
  Future<TaskSettingsConfig> getTaskSettingsConfig() async {
    final dbConn = await DatabaseHelper.instance.database;
    final settings = SettingsRepository(dbConn);
    final raw =
        await settings.getSetting(TaskSettingsConfig.appSettingsKey) ??
        await settings.getSetting(TaskSettingsConfig.legacyAppSettingsKey);
    return _decodeTaskSettingsConfig(raw);
  }

  /// Χαλασμένο ή άγνωστο περιεχόμενο δίνει προεπιλογές αντί για κρασάρισμα:
  /// οι ρυθμίσεις είναι προτιμήσεις, όχι δεδομένα που δεν αντικαθίστανται.
  static TaskSettingsConfig _decodeTaskSettingsConfig(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return TaskSettingsConfig.defaultConfig();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return TaskSettingsConfig.fromMap(decoded);
      }
      if (decoded is Map) {
        return TaskSettingsConfig.fromMap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return TaskSettingsConfig.defaultConfig();
  }

  /// Επόμενη προτεινόμενη ημερομηνία/ώρα λήξης βάσει ρυθμίσεων — δες
  /// [TaskDueDateCalculator.nextDueDate].
  DateTime calculateNextDueDate(
    TaskSettingsConfig config, {
    String option = TaskSettingsConfig.kOptionDefault,
    DateTime? fromDate,
  }) => TaskDueDateCalculator.nextDueDate(
    config,
    option: option,
    fromDate: fromDate,
  );

  /// **Στοχευμένη αλλαγή** των ρυθμίσεων εκκρεμοτήτων.
  ///
  /// Οι έξι ρυθμίσεις ζουν σε ΕΝΑ κλειδί, οπότε η [change] εφαρμόζεται στη
  /// **φρέσκια** αποθηκευμένη τιμή μέσα σε ατομική δέσμευση — όχι στην εικόνα
  /// που κρατά ο διάλογος. Γι' αυτό οφείλει να είναι καθαρή: μπορεί να
  /// ξανατρέξει αν κάποιος προλάβει.
  ///
  /// Επιστρέφει ό,τι **όντως** αποθηκεύτηκε: ο καλών ενημερώνει την οθόνη του
  /// με αυτό, οπότε βλέπει και τις αλλαγές του συναδέλφου.
  Future<TaskSettingsConfig> updateTaskSettingsConfig(
    TaskSettingsConfig Function(TaskSettingsConfig current) change,
  ) async {
    final dbSave = await DatabaseHelper.instance.database;
    final settings = SettingsRepository(dbSave);
    // Εγκατάσταση που δεν έχει ακόμη το νέο κλειδί κρατά τις ρυθμίσεις της στο
    // παλιό. Χωρίς αυτό, η πρώτη στοχευμένη εγγραφή θα ξεκινούσε από τις
    // προεπιλογές και θα έσβηνε ό,τι είχε ρυθμίσει ο χρήστης.
    final legacyRaw = await settings.getSetting(
      TaskSettingsConfig.legacyAppSettingsKey,
    );
    final storedRaw = await settings.updateSetting(
      TaskSettingsConfig.appSettingsKey,
      (raw) => jsonEncode(
        change(_decodeTaskSettingsConfig(raw ?? legacyRaw)).toMap(),
      ),
    );
    return _decodeTaskSettingsConfig(storedRaw);
  }

  /// Τίτλος εκκρεμότητας από σημειώσεις/κατηγορία (μορφή φόρμας κλήσης).
  /// Ο εξοπλισμός περνά μόνο ως metadata (`equipment_text` / FK), όχι στον τίτλο.
  ///
  /// `description` = πλήρες κείμενο σημειώσεων (το ίδιο αποθηκεύεται στο task.description).
  static String smartTaskTitleFromCallContext({
    required String description,
    String? categoryName,
    required DateTime titleAt,
    String? callerFallback,
  }) {
    final notesRaw = description.contains(Task.quickAddTag)
        ? description.replaceAll(Task.quickAddTag, '').trim()
        : description;
    String snippet = '';
    if (notesRaw.isNotEmpty) {
      var line = notesRaw.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      line = line.replaceAll(RegExp(r' +'), ' ');
      if (line.length > 40) {
        snippet = '${line.substring(0, 40)}...';
      } else {
        snippet = line;
      }
    }

    final categoryPart = (categoryName ?? '').trim();

    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(titleAt);
    final right = categoryPart.isNotEmpty
        ? '$categoryPart ($dateStr)'
        : '($dateStr)';

    if (snippet.isEmpty) {
      if (categoryPart.isEmpty &&
          callerFallback != null &&
          callerFallback.trim().isNotEmpty) {
        return '${callerFallback.trim()} | $right';
      }
      return right;
    }
    return '$snippet | $right';
  }

  Future<Map<String, dynamic>> buildCreateFromCallRow({
    int? callId,
    required String? callerName,
    required String description,
    required DateTime callDate,
    String callSolution = '',
    int? callerId,
    int? equipmentId,
    int? departmentId,
    int? phoneId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
    String? categoryName,
    DateTime? titleTimestamp,
    int? priority,
    String? origin,
    TaskSettingsConfig? config,
  }) async {
    final titleAt = titleTimestamp ?? callDate;
    // Ο τίτλος χτίζεται από τη ΣΚΕΤΗ περιγραφή, πριν προστεθεί η λύση: αλλιώς
    // το απόσπασμα που τον γεννά θα κουβαλούσε και τα πρώτα βήματα.
    final title = smartTaskTitleFromCallContext(
      description: description,
      categoryName: categoryName,
      titleAt: titleAt,
      callerFallback: callerName,
    );
    final notes = taskNotesFromCall(notes: description, solution: callSolution);
    final settings = config ?? await getTaskSettingsConfig();
    final dueDate = calculateNextDueDate(
      settings,
      option: TaskSettingsConfig.kOptionDefault,
      fromDate: DateTime.now(),
    );
    final nowIso = DateTime.now().toIso8601String();
    final resolvedOrigin = Task.normalizeOrigin(
      origin ?? (callId != null ? Task.originCallLinked : Task.originQuickAdd),
    );
    return <String, dynamic>{
      'call_id': callId,
      'created_at': nowIso,
      'updated_at': nowIso,
      'title': title,
      'description': notes,
      'due_date': dueDate.toIso8601String(),
      'status': 'open',
      'priority': priority,
      'caller_id': callerId,
      'equipment_id': equipmentId,
      'department_id': departmentId,
      'phone_id': phoneId,
      'phone_text': phoneText,
      'user_text': userText,
      'equipment_text': equipmentText,
      'department_text': departmentText,
      'origin': resolvedOrigin,
      'is_deleted': 0,
      'search_index': SearchTextNormalizer.normalizeForSearch(
        [
          title,
          description,
          userText ?? '',
          phoneText ?? '',
          equipmentText ?? '',
          departmentText ?? '',
        ].join(' '),
      ),
    };
  }

  /// Εισαγωγή εκκρεμότητας σε υπάρχον [DatabaseExecutor] (π.χ. κοινό transaction με κλήση).
  ///
  /// Αν δοθεί [afterTaskInserted], εκτελείται μετά την κύρια εγγραφή ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ
  /// και περνά suffix προέλευσης για παράγωγες εγγραφές (Φάση 3).
  /// Σφραγίζει τη νέα εκκρεμότητα με τον χειριστή που την ανοίγει.
  ///
  /// **Ένα σημείο για κάθε πόρτα δημιουργίας.** Η πληροφορία «ποιος την
  /// άνοιξε» δεν ανακτάται ποτέ αργότερα: αν μια πόρτα ξεφύγει, οι
  /// εκκρεμότητές της μένουν για πάντα αδέσποτες χωρίς να το πάρει κανείς
  /// είδηση — φαίνονται απλώς σε λάθος φίλτρο.
  ///
  /// Χωρίς αναγνωρισμένο χειριστή δεν γράφεται τίποτα: το κενό είναι τίμιο,
  /// ενώ ένα τυχαίο id θα ήταν εφεύρεση.
  static void _stampCreatingOperator(Map<String, dynamic> row) {
    if (row['created_by_operator_id'] != null) return;
    final operatorId = CurrentOperator.active?.id;
    if (operatorId == null) return;
    row['created_by_operator_id'] = operatorId;
  }

  Future<int> createFromCallOnExecutor(
    DatabaseExecutor executor, {
    required Map<String, dynamic> row,
    Future<void> Function(DatabaseExecutor txn, String auditOriginSuffix)?
    afterTaskInserted,
  }) async {
    _stampCreatingOperator(row);
    final id = await executor.insert('tasks', row);
    await _auditTaskCreate(executor, id, row);
    if (afterTaskInserted != null) {
      await afterTaskInserted(
        executor,
        DirectorySupport.auditOriginSuffixFromTask(id),
      );
    }
    return id;
  }

  /// Δημιουργεί εκκρεμότητα από κλήση ή αυτόνομα ([callId] null = χωρίς εγγραφή κλήσης).
  Future<int> createFromCall({
    int? callId,
    required String? callerName,
    required String description,
    required DateTime callDate,
    int? callerId,
    int? equipmentId,
    int? departmentId,
    int? phoneId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
    String? categoryName,
    DateTime? titleTimestamp,
    int? priority,
    String? origin,
  }) async {
    try {
      final row = await buildCreateFromCallRow(
        callId: callId,
        callerName: callerName,
        description: description,
        callDate: callDate,
        callerId: callerId,
        equipmentId: equipmentId,
        departmentId: departmentId,
        phoneId: phoneId,
        phoneText: phoneText,
        userText: userText,
        equipmentText: equipmentText,
        departmentText: departmentText,
        categoryName: categoryName,
        titleTimestamp: titleTimestamp,
        priority: priority,
        origin: origin,
      );
      final db = await _db;
      return await db.transaction(
        (txn) => createFromCallOnExecutor(txn, row: row),
      );
    } catch (e) {
      if (e is TaskSaveException) rethrow;
      throw TaskSaveException(
        'Η εκκρεμότητα δεν δημιουργήθηκε. Δοκιμάστε ξανά.',
      );
    }
  }

  /// Προσθέτει γραμμή στην περιγραφή ανοιχτής γρήγορης εκκρεμότητας (ίδιο [taskId]).
  /// Επιστρέφει false αν λείπει η εγγραφή, είναι διαγραμμένη/κλειστή ή δεν είναι quick-add.
  Future<bool> appendToQuickAddDescription(int taskId, String addition) async {
    final a = addition.trim();
    if (a.isEmpty) return false;
    final db = await _db;
    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final task = Task.fromMap(rows.first);
    if (task.isDeleted || !task.isQuickAdd) return false;
    if (task.status == TaskStatus.closed.toDbValue) return false;
    final desc = (task.description ?? '').trim();
    final newDesc = desc.isEmpty ? '${Task.quickAddTag} $a' : '$desc\n$a';
    await updateTask(task.copyWith(description: newDesc));
    return true;
  }

  /// Συμπληρώνει κενά FK/snapshot πεδία σε γρήγορη εκκρεμότητα (χωρίς αντικατάσταση μη κενών).
  Future<bool> mergeQuickAddEntitySnapshot({
    required int taskId,
    int? callerId,
    int? departmentId,
    int? equipmentId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    var task = Task.fromMap(rows.first);
    if (task.isDeleted || !task.isQuickAdd) return false;

    var next = task;
    var changed = false;

    if (task.callerId == null && callerId != null) {
      next = next.copyWith(callerId: callerId);
      changed = true;
    }
    if (task.departmentId == null && departmentId != null) {
      next = next.copyWith(departmentId: departmentId);
      changed = true;
    }
    if (task.equipmentId == null && equipmentId != null) {
      next = next.copyWith(equipmentId: equipmentId);
      changed = true;
    }

    String? pickText(String? current, String? incoming) {
      final inc = incoming?.trim();
      if (inc == null || inc.isEmpty) return null;
      final cur = current?.trim() ?? '';
      if (cur.isEmpty) return inc;
      return null;
    }

    final u = pickText(next.userText, userText);
    if (u != null) {
      next = next.copyWith(userText: u);
      changed = true;
    }
    final p = pickText(next.phoneText, phoneText);
    if (p != null) {
      next = next.copyWith(phoneText: p);
      changed = true;
    }
    final e = pickText(next.equipmentText, equipmentText);
    if (e != null) {
      next = next.copyWith(equipmentText: e);
      changed = true;
    }
    final d = pickText(next.departmentText, departmentText);
    if (d != null) {
      next = next.copyWith(departmentText: d);
      changed = true;
    }

    if (!changed) return false;
    await updateTask(next);
    return true;
  }

  /// Μία εκκρεμότητα, ξαναδιαβασμένη φρέσκια από τη βάση.
  ///
  /// Χρειάζεται όπου η οθόνη κρατά αντίγραφο και κάτι το άλλαξε από άλλη πόρτα
  /// (π.χ. η αποστολή στο Lansweeper γράφει στήλες που η φόρμα δεν αγγίζει).
  /// Η διαγραμμένη επιστρέφεται κανονικά: ο καλών ξαναδιαβάζει κάτι που ήδη
  /// κρατά στα χέρια του και δικαιούται να δει τι απέγινε.
  Future<Task?> getTaskById(int taskId) async {
    final db = await _db;
    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  /// Ζωντανές εκκρεμότητες μιας κλήσης — και οι κλειστές, γιατί η ερώτηση
  /// «τι άφησε πίσω της η κλήση» δεν παύει να ισχύει όταν η εκκρεμότητα κλείσει.
  Future<List<Task>> getTasksForCall(int callId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT * FROM tasks '
      'WHERE call_id = ? AND COALESCE(is_deleted, 0) = 0 '
      'ORDER BY id ASC',
      [callId],
    );
    return rows.map((row) => Task.fromMap(row)).toList();
  }

  Future<List<Task>> getOpenTasks() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT * FROM tasks WHERE status = 'open' AND COALESCE(is_deleted, 0) = 0 ORDER BY due_date ASC",
    );
    return rows.map((row) => Task.fromMap(row)).toList();
  }

  /// Συνολικό πλήθος εκκρεμοτήτων `open` + `snoozed` (για badge μενού).
  Future<int> getGlobalPendingTasksCount() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COUNT(id) AS count FROM tasks WHERE status IN ('open', 'snoozed') AND COALESCE(is_deleted, 0) = 0",
    );
    if (rows.isEmpty) return 0;
    final n = rows.first['count'];
    return n is int ? n : (n is num ? n.toInt() : int.tryParse('$n') ?? 0);
  }

  /// Συνολικό πλήθος μη διαγραμμένων εγγραφών στον πίνακα `tasks`.
  Future<int> getTotalTaskCount() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(id) AS count FROM tasks WHERE COALESCE(is_deleted, 0) = 0',
    );
    if (rows.isEmpty) return 0;
    final n = rows.first['count'];
    return n is int ? n : (n is num ? n.toInt() : int.tryParse('$n') ?? 0);
  }

  /// Ελάχιστη/μέγιστη ημερομηνία δημιουργίας εκκρεμοτήτων (ημέρα μόνο).
  Future<({DateTime start, DateTime end})> getTaskCreationDateSpan() async =>
      TasksAnalyticsRepository(await _db).getTaskCreationDateSpan();

  /// Η αναφορά της Ανάλυσης εκκρεμοτήτων για το διάστημα [range].
  Future<TaskAnalyticsSummary> getTaskAnalytics(DateTimeRange range) async =>
      TasksAnalyticsRepository(await _db).getTaskAnalytics(range);

  void _appendTaskFilterWhereParts(
    TaskFilter filter,
    List<String> conditions,
    List<Object?> args, {
    bool includeStatuses = true,
  }) {
    conditions.add('COALESCE(tasks.is_deleted, 0) = 0');
    if (filter.searchQuery.trim().isNotEmpty) {
      final normalizedQuery = SearchTextNormalizer.normalizeForSearch(
        filter.searchQuery,
      );
      final tokens = normalizedQuery
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();
      for (final token in tokens) {
        conditions.add('tasks.search_index ${SqlLike.op}');
        args.add(SqlLike.contains(token));
      }
    }

    if (includeStatuses && filter.statuses.isNotEmpty) {
      final placeholders = List.filled(filter.statuses.length, '?').join(',');
      conditions.add('tasks.status IN ($placeholders)');
      for (final s in filter.statuses) {
        args.add(s.toDbValue);
      }
    }
    // Η φόρμουλα της ευθύνης: «του Χ» σημαίνει ανατεθειμένες στον Χ, συν
    // όσες άνοιξε ο Χ και δεν ανατέθηκαν πουθενά. Η ανάθεση ΜΕΤΑΚΙΝΕΙ την
    // ευθύνη — μια εκκρεμότητα δεν εμφανίζεται ποτέ σε δύο λίστες ταυτόχρονα.
    // «Χωρίς χρήστη» σημαίνει ούτε δημιουργό ούτε υπεύθυνο.
    final owner = filter.owner;
    if (owner.unassignedOnly) {
      conditions.add(
        'tasks.assigned_operator_id IS NULL '
        'AND tasks.created_by_operator_id IS NULL',
      );
    } else if (owner.operatorId != null) {
      conditions.add(
        '(tasks.assigned_operator_id = ? '
        'OR (tasks.assigned_operator_id IS NULL '
        'AND tasks.created_by_operator_id = ?))',
      );
      args.add(owner.operatorId);
      args.add(owner.operatorId);
    }

    if (filter.startDate != null) {
      conditions.add('tasks.due_date >= ?');
      args.add(filter.startDate!.toIso8601String());
    }
    if (filter.endDate != null) {
      conditions.add('tasks.due_date <= ?');
      args.add(filter.endDate!.toIso8601String());
    }
  }

  /// Πόσες εκκρεμότητες ταιριάζουν στο [filter] — τα ίδια ακριβώς κριτήρια με
  /// τη λίστα, χωρίς να φορτωθούν οι εγγραφές.
  ///
  /// Χρησιμεύει στην κενή οθόνη, που πρέπει να ξεχωρίσει το «δεν έμεινε
  /// δουλειά» από το «δεν τη βλέπω λόγω φίλτρου» — δύο καταστάσεις που
  /// μοιάζουν ίδιες και δεν είναι.
  Future<int> countFilteredTasks(TaskFilter filter) async {
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];
    _appendTaskFilterWhereParts(filter, conditions, args);
    final rows = await db.rawQuery(
      'SELECT COUNT(id) AS count FROM tasks WHERE ${conditions.join(' AND ')}',
      args,
    );
    if (rows.isEmpty) return 0;
    final n = rows.first['count'];
    return n is int ? n : (n is num ? n.toInt() : int.tryParse('$n') ?? 0);
  }

  /// Τα ids των χρηστών που έχουν ανοίξει έστω μία εκκρεμότητα.
  ///
  /// Τροφοδοτεί τις επιλογές του φίλτρου. Δεν επιστρέφονται όλοι οι χρήστες
  /// της εφαρμογής: όνομα που θα έδινε πάντα άδεια λίστα δεν είναι επιλογή,
  /// είναι θόρυβος. Τον τρέχοντα χρήστη τον προσθέτει ο καλών, ώστε να μπορεί
  /// πάντα να διαλέξει τον εαυτό του.
  ///
  /// Οι διαγραμμένες εκκρεμότητες δεν μετρούν — δεν φαίνονται ούτε στη λίστα.
  Future<List<int>> getDistinctOwnerIds() async {
    final db = await _db;
    // Ίδια φόρμουλα με το φίλτρο: υπεύθυνοι, συν δημιουργοί των ανανάθετων.
    // Όνομα που θα έδινε πάντα άδεια λίστα δεν είναι επιλογή, είναι θόρυβος.
    final rows = await db.rawQuery(
      'SELECT DISTINCT assigned_operator_id AS oid FROM tasks '
      'WHERE assigned_operator_id IS NOT NULL '
      'AND COALESCE(is_deleted, 0) = 0 '
      'UNION '
      'SELECT DISTINCT created_by_operator_id AS oid FROM tasks '
      'WHERE assigned_operator_id IS NULL '
      'AND created_by_operator_id IS NOT NULL '
      'AND COALESCE(is_deleted, 0) = 0',
    );
    return rows
        .map((row) => row['oid'])
        .whereType<num>()
        .map((id) => id.toInt())
        .toList();
  }

  /// True όταν υπάρχει έστω μία εκκρεμότητα χωρίς καταγεγραμμένο χρήστη.
  ///
  /// Χωρίς αυτό, η επιλογή «Χωρίς χρήστη» θα εμφανιζόταν και σε βάσεις όπου
  /// δεν αντιστοιχεί σε τίποτα.
  Future<bool> hasUnassignedTasks() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT 1 FROM tasks WHERE assigned_operator_id IS NULL '
      'AND created_by_operator_id IS NULL '
      'AND COALESCE(is_deleted, 0) = 0 LIMIT 1',
    );
    return rows.isNotEmpty;
  }

  /// Πλήθος ανά `status` με ίδια φίλτρα αναζήτησης/ημερομηνίας με [getFilteredTasks],
  /// χωρίς φίλτρο επιλεγμένων statuses (για μετρητές στα chips).
  Future<Map<TaskStatus, int>> getTaskCounts(TaskFilter filter) async {
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];
    _appendTaskFilterWhereParts(
      filter,
      conditions,
      args,
      includeStatuses: false,
    );
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    final rows = await db.rawQuery(
      'SELECT tasks.status AS status, COUNT(DISTINCT tasks.id) AS count '
      'FROM tasks $where GROUP BY tasks.status',
      args,
    );

    final result = <TaskStatus, int>{for (final s in TaskStatus.values) s: 0};
    for (final row in rows) {
      final raw = row['status'] as String?;
      if (raw == null) continue;
      final status = TaskStatusX.fromString(raw);
      final n = row['count'];
      final c = n is int ? n : (n is num ? n.toInt() : int.tryParse('$n') ?? 0);
      result[status] = c;
    }
    return result;
  }

  /// Λίστα tasks με δυναμικό φίλτρο (search, statuses, ημερομηνίες) και ταξινόμηση.
  Future<List<Task>> getFilteredTasks(TaskFilter filter) async {
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];
    _appendTaskFilterWhereParts(
      filter,
      conditions,
      args,
      includeStatuses: true,
    );

    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    // Στήλη λήξης στο σχήμα: `due_date` (όχι due_at).
    // ΚΑΘΕ στήλη γράφεται με πρόθεμα `tasks.`: το ερώτημα ενώνεται με τις
    // κλήσεις, που έχουν δικές τους `status`, `search_index` και `created_at`.
    // Χωρίς το πρόθεμα η βάση απαντά «ambiguous column name» και η λίστα μένει
    // για πάντα στο «Φόρτωση εκκρεμοτήτων…».
    final sortColumn = switch (filter.sortBy) {
      TaskSortOption.createdAt => 'tasks.created_at',
      TaskSortOption.dueAt => 'tasks.due_date',
      TaskSortOption.priority => 'tasks.priority',
      TaskSortOption.department => 'tasks.department_text',
      TaskSortOption.user => 'tasks.user_text',
      TaskSortOption.equipment => 'tasks.equipment_text',
    };
    final sortDirection = filter.sortAscending ? 'ASC' : 'DESC';
    final orderByClause = 'ORDER BY $sortColumn $sortDirection';

    final rows = await db.rawQuery('''
      SELECT tasks.*,
        COALESCE(u.is_deleted, 0) AS caller_is_deleted,
        COALESCE(e.is_deleted, 0) AS equipment_is_deleted,
        COALESCE(d.is_deleted, 0) AS department_is_deleted,
        c.lansweeper_main_ticket_id AS linked_call_ticket_id
      FROM tasks
      LEFT JOIN users u ON u.id = tasks.caller_id
      LEFT JOIN equipment e ON e.id = tasks.equipment_id
      LEFT JOIN departments d ON d.id = tasks.department_id
      LEFT JOIN calls c ON c.id = tasks.call_id
      $where $orderByClause
      ''', args);
    return rows.map((row) => Task.fromMap(row)).toList();
  }

  /// Δημιουργεί νέα εγγραφή στον πίνακα tasks. Επιστρέφει το νέο id.
  ///
  /// Εγγραφή + audit στο ίδιο transaction ([TaskSaveException] σε αποτυχία).
  Future<int> createTask(Task task) async {
    final db = await _db;
    final map = task.toMap();
    map.remove('id');
    if (!await _hasSnoozeHistoryColumn(db)) {
      map.remove('snooze_history_json');
    }
    final now = DateTime.now().toIso8601String();
    map['created_at'] = now;
    map['updated_at'] = now;
    _stampCompletionMoment(map, null, now);
    map['origin'] = Task.normalizeOrigin(map['origin'] as String?);
    map['search_index'] = SearchTextNormalizer.normalizeForSearch(
      task.combinedSearchText,
    );
    _stampCreatingOperator(map);
    try {
      return await db.transaction((txn) async {
        final id = await txn.insert('tasks', map);
        // Νέα εκκρεμότητα ανατεθειμένη εξαρχής σε άλλον: δεν υπάρχει
        // προηγούμενος κάτοχος, οπότε αναγγέλλεται μόνο η μία κατεύθυνση.
        await _notifyAssignmentChange(
          txn,
          taskId: id,
          previousOwner: null,
          nextOwner: map['assigned_operator_id'] as int?,
        );
        await _auditTaskCreate(txn, id, map);
        return id;
      });
    } catch (e) {
      if (e is TaskSaveException) rethrow;
      throw TaskSaveException(
        'Η εκκρεμότητα δεν αποθηκεύτηκε. Δοκιμάστε ξανά.',
      );
    }
  }

  /// Πεδία που ο χρήστης μπορεί να αδειάσει από φόρμα.
  ///
  /// Το [Task.toMap] παραλείπει ό,τι είναι null, ώστε μια μερική ενημέρωση να
  /// μην πατάει πάνω σε τιμές που δεν αφορούν. Για αυτά τα πεδία όμως το κενό
  /// είναι απόφαση του χρήστη: αν λείψουν από το map, το UPDATE δεν τα αγγίζει
  /// και η παλιά τιμή επιστρέφει στην οθόνη σαν να μη σβήστηκε ποτέ.
  static const _kUserClearableFields = <String>[
    'description',
    'caller_id',
    'user_text',
    'phone_text',
    'department_text',
    'equipment_text',
  ];

  /// Πεδία που δεν μαρτυρούν ξένη δουλειά.
  ///
  /// Η σφραγίδα και το παράγωγο ευρετήριο αναζήτησης αλλάζουν σε **κάθε**
  /// εγγραφή· η στιγμή δημιουργίας δεν αλλάζει ποτέ. Καμία τους δεν λέει
  /// «κάποιος άλλαξε κάτι».
  static const Set<String> _kGuardIgnoredFields = {
    'updated_at',
    'created_at',
    'search_index',
  };

  static String _guardText(Object? value) => value?.toString().trim() ?? '';

  /// Θα σβήσει η εγγραφή μου δουλειά που έκανε **άλλος**;
  ///
  /// Η σφραγίδα απαντά μόνο «κάτι άγγιξε τη γραμμή» — και την αγγίζει και η
  /// δική μου προηγούμενη αποθήκευση, και μια εγγραφή που δεν άλλαξε καμία
  /// τιμή. Η αληθινή ερώτηση είναι στενότερη: **διαφέρει η αφετηρία μου από
  /// τη βάση σε πεδίο που περνά η εγγραφή μου;** Εκεί και μόνο εκεί υπάρχει
  /// ξένη δουλειά να χαθεί.
  ///
  /// Κρίνεται μόνο ό,τι γράφω: πεδίο που δεν το πειράζω δεν κινδυνεύει, όσο
  /// κι αν άλλαξε. Και η σύγκριση είναι **αφετηρία προς βάση**, όχι πρόθεσή
  /// μου προς βάση — αλλιώς κάθε δική μου αλλαγή θα φαινόταν ως ξένη.
  ///
  /// Χωρίς αφετηρία μένει η παλιά, αυστηρή απάντηση: μια ερώτηση παραπάνω
  /// είναι φθηνότερη από σιωπηλή απώλεια.
  static bool _overwritesForeignWork({
    required Task? expected,
    required Map<String, dynamic> freshRow,
    required Map<String, dynamic> attempted,
  }) {
    if (expected == null) return true;
    final baseline = expected.toMap();
    for (final key in attempted.keys) {
      if (key == 'id' || _kGuardIgnoredFields.contains(key)) continue;
      if (_guardText(baseline[key]) != _guardText(freshRow[key])) {
        return true;
      }
    }
    return false;
  }

  /// Άλλαξε η γραμμή από τότε που τη διάβασε η οθόνη;
  ///
  /// **Fail-open σε άγνοια:** χωρίς αποθηκευμένη σφραγίδα (`updated_at`) ή
  /// χωρίς αναμενόμενη τιμή δεν μπλοκάρουμε — μια εγγραφή από παλαιότερη έκδοση
  /// δεν πρέπει να γίνει άσωστη. Ο φρουρός προστατεύει ό,τι μπορεί να
  /// αποδείξει, και δεν εφευρίσκει διενέξεις.
  static bool _isStaleWrite({
    required Map<String, dynamic>? oldRow,
    required String? expectedUpdatedAt,
  }) {
    if (oldRow == null) return false;
    if (expectedUpdatedAt == null || expectedUpdatedAt.isEmpty) return false;
    final stored = oldRow['updated_at'] as String?;
    if (stored == null || stored.isEmpty) return false;
    return stored != expectedUpdatedAt;
  }

  /// Ποιος άγγιξε τελευταίος αυτή την εκκρεμότητα, από το Ιστορικό.
  ///
  /// Η γραμμή `tasks` δεν κρατά «ποιος με άλλαξε» — το κρατά μόνο το Ιστορικό.
  /// Το ερώτημα τρέχει **μόνο** όταν έχει ήδη διαπιστωθεί διένεξη, οπότε δεν
  /// επιβαρύνει την κανονική αποθήκευση, και πατά στο υπάρχον ευρετήριο
  /// `(entity_type, entity_id)`.
  static Future<({String? who, DateTime? at})> _lastAuditActor(
    DatabaseExecutor executor,
    int taskId,
  ) async {
    try {
      final rows = await executor.query(
        'audit_log',
        columns: ['user_performing', 'timestamp'],
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [AuditEntityTypes.task, taskId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isEmpty) return (who: null, at: null);
      final who = (rows.first['user_performing'] as String?)?.trim();
      final at = DateTime.tryParse((rows.first['timestamp'] as String?) ?? '');
      return (who: (who == null || who.isEmpty) ? null : who, at: at);
    } catch (_) {
      // Η ταυτότητα είναι συμπληρωματική: η διένεξη αναφέρεται και χωρίς αυτήν.
      return (who: null, at: null);
    }
  }

  /// Σφραγίζει τη στιγμή ολοκλήρωσης **και τον άνθρωπο** που την έκλεισε.
  ///
  /// Ένα σημείο για όλες τις ροές: η σφραγίδα μπαίνει μόνο στη μετάβαση προς
  /// «ολοκληρωμένη», ώστε μια απλή διόρθωση κειμένου να μη μετακινεί τη στιγμή
  /// της λύσης, και δεν αφαιρείται ποτέ — η αναίρεση χρειάζεται να τη δείξει.
  ///
  /// Τα δύο ταξιδεύουν μαζί επειδή απαντούν στο ίδιο ερώτημα — «πότε και από
  /// ποιον λύθηκε» — και μια μελλοντική ροή κλεισίματος δεν πρέπει να μπορεί να
  /// θυμηθεί το ένα ξεχνώντας το άλλο.
  ///
  /// Χωρίς αναγνωρισμένο χειριστή γράφεται μόνο η ώρα: το κενό είναι τίμιο,
  /// ενώ ένα τυχαίο id θα ήταν εφεύρεση.
  static void _stampCompletionMoment(
    Map<String, dynamic> map,
    Map<String, dynamic>? oldRow,
    String nowIso,
  ) {
    final closedValue = TaskStatus.closed.toDbValue;
    if (map['status'] != closedValue) return;
    if (oldRow != null && oldRow['status'] == closedValue) return;
    map['completed_at'] = nowIso;
    final operatorId = CurrentOperator.active?.id;
    if (operatorId != null) {
      map['closed_by_operator_id'] = operatorId;
    }
  }

  /// Ενημερώνει μια υπάρχουσα εγγραφή στον πίνακα tasks.
  ///
  /// Εγγραφή + audit στο ίδιο transaction ([TaskSaveException] σε αποτυχία).
  /// Με [force] `true` η εγγραφή περνά **παρά** τη διένεξη: ο χρήστης είδε τι
  /// άλλαξε και επέλεξε ρητά να κρατήσει τη δική του εικόνα.
  /// Το [expected] είναι η εγγραφή **όπως τη διάβασε η οθόνη** — η αφετηρία
  /// της σύγκρισης. Χωρίς αυτήν ο φρουρός δεν μπορεί να ξεχωρίσει τη δική
  /// μου αλλαγή από την ξένη και μπλοκάρει σε κάθε αγγιγμένη γραμμή.
  Future<void> updateTask(
    Task task, {
    Task? expected,
    bool force = false,
  }) async {
    if (task.id == null) return;
    final db = await _db;
    final tid = task.id!;

    final map = task.toMap();
    map.remove('id');
    if (!await _hasSnoozeHistoryColumn(db)) {
      map.remove('snooze_history_json');
    }
    // Η επεξεργασία δεν αποφασίζει ποτέ αν η εκκρεμότητα είναι διαγραμμένη:
    // η καρτέλα γράφεται ολόκληρη, και το «όχι διαγραμμένη» της φόρμας θα
    // ανέσταινε μια εκκρεμότητα που διέγραψε άλλος σταθμός στο μεταξύ.
    map.remove('is_deleted');
    final nowIso = DateTime.now().toIso8601String();
    map['updated_at'] = nowIso;
    for (final field in _kUserClearableFields) {
      map.putIfAbsent(field, () => null);
    }
    map['origin'] = Task.normalizeOrigin(map['origin'] as String?);
    map['search_index'] = SearchTextNormalizer.normalizeForSearch(
      task.combinedSearchText,
    );
    try {
      await db.transaction((txn) async {
        // Το «πριν» του audit διαβάζεται ΜΕΣΑ στη συναλλαγή, ώστε σε
        // κοινόχρηστη βάση να μην παρεμβληθεί ξένη εγγραφή ανάμεσα.
        final oldRows = await txn.query(
          'tasks',
          where: 'id = ?',
          whereArgs: [tid],
          limit: 1,
        );
        final oldRow = oldRows.isEmpty
            ? null
            : Map<String, dynamic>.from(oldRows.first);
        if (oldRow != null && oldRow['is_deleted'] == 1) {
          throw TaskDeletedElsewhereException();
        }
        // Ο φρουρός μπαίνει ΕΔΩ και όχι στον καλούντα: η γραμμή έχει μόλις
        // διαβαστεί μέσα στη συναλλαγή, οπότε η σύγκριση είναι ατομική — δεν
        // υπάρχει παράθυρο ανάμεσα στον έλεγχο και στην εγγραφή.
        // Η σφραγίδα είναι το φθηνό πρώτο φίλτρο· το περιεχόμενο κρίνει.
        if (!force &&
            _isStaleWrite(oldRow: oldRow, expectedUpdatedAt: task.updatedAt) &&
            _overwritesForeignWork(
              expected: expected,
              freshRow: oldRow!,
              attempted: map,
            )) {
          final actor = await _lastAuditActor(txn, tid);
          throw TaskStaleException(
            fresh: Task.fromMap(oldRow),
            attempted: task,
            changedBy: actor.who,
            changedAt: actor.at,
          );
        }
        final wasClosed = oldRow?['status'] == TaskStatus.closed.toDbValue;
        _stampCompletionMoment(map, oldRow, nowIso);
        final n = await txn.update(
          'tasks',
          map,
          where: 'id = ?',
          whereArgs: [tid],
        );
        if (n > 0 && oldRow != null) {
          await _notifyAssignmentChange(
            txn,
            taskId: tid,
            previousOwner: _ownerOf(oldRow),
            nextOwner: _ownerOf(map),
          );
          // Η φόρμα μπορεί να κλείσει την εκκρεμότητα όπως και ο διάλογος
          // ολοκλήρωσης. Η αναγγελία κρίνεται από τη ΜΕΤΑΒΑΣΗ και όχι από την
          // τελική κατάσταση: μια διόρθωση κειμένου σε ήδη κλειστή δεν
          // ξαναειδοποιεί κανέναν.
          if (!wasClosed && map['status'] == TaskStatus.closed.toDbValue) {
            await _notifyClosure(txn, taskId: tid, oldRow: oldRow);
          }
          await _auditTaskUpdate(txn, tid, oldRow, map);
        }
      });
    } catch (e) {
      if (e is TaskSaveException) rethrow;
      throw TaskSaveException('Η εκκρεμότητα δεν ενημερώθηκε. Δοκιμάστε ξανά.');
    }
  }

  /// Soft delete εγγραφής βάσει ID (audit στο [IntegrityService]).
  Future<void> deleteTask(int id) async {
    final dbDel = await DatabaseHelper.instance.database;
    await IntegrityService(dbDel).softDeleteTask(id);
  }

  /// Επαναδόμηση `search_index` για μία εκκρεμότητα (integrity fix).
  Future<void> rebuildSearchIndexForTaskId(int taskId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final task = Task.fromMap(rows.first);
      final si = SearchTextNormalizer.normalizeForSearch(
        task.combinedSearchText,
      );
      await txn.update(
        'tasks',
        {'search_index': si},
        where: 'id = ?',
        whereArgs: [taskId],
      );
    });
  }

  /// Η ωμή γραμμή της εκκρεμότητας [taskId], ή `null` αν δεν υπάρχει.
  Future<Map<String, dynamic>?> getTaskRowById(int taskId) async {
    final db = await _db;
    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Συγχρονισμός updated_at = created_at (integrity fix — χωρίς audit).
  Future<Map<String, dynamic>?> integritySyncTaskTimestamps(int taskId) async {
    final db = await _db;
    return db.transaction((txn) async {
      return IntegrityService(db).integritySyncTaskTimestamps(txn, taskId);
    });
  }

  /// Ενημέρωση FK πεδίου εκκρεμότητας (integrity fix — χωρίς audit).
  Future<Map<String, dynamic>?> integrityUpdateTaskFk(
    int taskId,
    String field,
    int? newValue,
  ) async {
    final db = await _db;
    return db.transaction((txn) async {
      return IntegrityService(
        db,
      ).integrityUpdateTaskFk(txn, taskId, field, newValue);
    });
  }

  /// Ορίζει status = closed, solution_notes και updated_at.
  ///
  /// Ενημέρωση και audit σε ΜΙΑ συναλλαγή: αποτυχία audit = καμία αλλαγή,
  /// με ειλικρινές σφάλμα αντί για σιωπηλό κλείσιμο χωρίς ίχνος.
  /// Το [expectedUpdatedAt] είναι η σφραγίδα της εγγραφής **όπως τη διάβασε η
  /// οθόνη**. Χωρίς αυτήν ο φρουρός δεν έχει αφετηρία και η εγγραφή περνά — γι'
  /// αυτό οι καλούντες οφείλουν να τη δίνουν πάντα.
  Future<void> closeTask(
    int id,
    String solutionNotes, {
    String? expectedUpdatedAt,
    bool force = false,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    try {
      await db.transaction((txn) async {
        final oldRows = await txn.query(
          'tasks',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final oldRow = oldRows.isEmpty
            ? null
            : Map<String, dynamic>.from(oldRows.first);
        final oldStatus = oldRow?['status'] as String?;
        if (!force &&
            _isStaleWrite(
              oldRow: oldRow,
              expectedUpdatedAt: expectedUpdatedAt,
            )) {
          final actor = await _lastAuditActor(txn, id);
          final fresh = Task.fromMap(oldRow!);
          throw TaskStaleException(
            fresh: fresh,
            // Η πρόθεση του χρήστη: κλείσιμο με ΑΥΤΟ το κείμενο λύσης. Ο
            // διάλογος τη χρειάζεται για να πει τι θα αντικατασταθεί.
            attempted: fresh.copyWith(
              status: TaskStatus.closed.toDbValue,
              solutionNotes: solutionNotes,
              updatedAt: expectedUpdatedAt,
            ),
            changedBy: actor.who,
            changedAt: actor.at,
          );
        }
        final values = <String, dynamic>{
          'status': 'closed',
          'solution_notes': solutionNotes,
          'updated_at': now,
        };
        _stampCompletionMoment(
          values,
          oldStatus != null ? {'status': oldStatus} : null,
          now,
        );
        final n = await txn.update(
          'tasks',
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
        if (n == 0) return;

        // Η λύση ταξιδεύει πίσω στην κλήση που γέννησε την εκκρεμότητα, στην
        // ΙΔΙΑ συναλλαγή: αλλιώς μια διακοπή θα άφηνε την εκκρεμότητα κλειστή
        // και την κλήση να αγνοεί πώς λύθηκε το πρόβλημά της.
        final linkedCallId = oldRow?['call_id'] as int?;
        if (linkedCallId != null) {
          await CallsRepository(db).appendSolutionFromTask(
            txn,
            callId: linkedCallId,
            taskSolution: solutionNotes,
          );
        }

        // Η αναγγελία κρίνεται από τη ΜΕΤΑΒΑΣΗ: ξανακλείσιμο ήδη κλειστής
        // (διόρθωση κειμένου λύσης) δεν ξαναειδοποιεί κανέναν.
        if (oldStatus != TaskStatus.closed.toDbValue) {
          await _notifyClosure(txn, taskId: id, oldRow: oldRow);
        }

        final user = AuditService.performingUser();
        await AuditService.log(
          txn,
          action: 'ΚΛΕΙΣΙΜΟ ΕΚΚΡΕΜΟΤΗΤΑΣ',
          userPerforming: user,
          details: 'tasks id=$id',
          entityType: AuditEntityTypes.task,
          entityId: id,
          entityName: oldRow?['title']?.toString(),
          oldValues: oldStatus != null ? {'status': oldStatus} : null,
          newValues: {'status': 'closed', 'solution_notes': solutionNotes},
        );
      });
    } catch (e) {
      if (e is TaskSaveException) rethrow;
      throw TaskSaveException('Η εκκρεμότητα δεν έκλεισε. Δοκιμάστε ξανά.');
    }
  }

  /// Κλήσεις με status pending που δεν έχουν αντίστοιχο task.
  Future<List<OrphanCall>> getCallsWithoutTask() async {
    final db = await _db;
    // Ορφανή = pending κλήση χωρίς καμία εγγραφή στο `tasks` για αυτό το `call_id`.
    // Αν υπήρχε task (ακόμη και soft-deleted), δεν ξαναπροτείνουμε μαζική δημιουργία.
    final rows = await db.rawQuery('''
      SELECT c.id, c.date, c.time, c.caller_id, c.caller_text, c.issue
      FROM calls c
      WHERE c.status = 'pending'
        AND COALESCE(c.is_deleted, 0) = 0
        AND NOT EXISTS (SELECT 1 FROM tasks t WHERE t.call_id = c.id)
      ORDER BY c.id
    ''');
    return rows
        .map(
          (r) => OrphanCall(
            id: r['id'] as int,
            date: r['date'] as String?,
            time: r['time'] as String?,
            callerId: r['caller_id'] as int?,
            callerText: r['caller_text'] as String?,
            issue: r['issue'] as String?,
          ),
        )
        .toList();
  }

  /// Δημιουργεί task για κάθε κλήση χωρίς εκκρεμότητα. Επιστρέφει πλήθος δημιουργημένων.
  Future<int> createTasksForOrphanCalls() async {
    final orphans = await getCallsWithoutTask();
    if (orphans.isEmpty) return 0;
    final db = await _db;
    int created = 0;
    for (final o in orphans) {
      String? callerName;
      if (o.callerId != null) {
        final userRows = await db.query(
          'users',
          columns: ['first_name', 'last_name'],
          where: 'id = ?',
          whereArgs: [o.callerId],
        );
        if (userRows.isNotEmpty) {
          final f = userRows.first['first_name'] as String? ?? '';
          final l = userRows.first['last_name'] as String? ?? '';
          callerName = '$f $l'.trim();
        }
      }
      if (callerName == null || callerName.isEmpty) {
        callerName = o.callerText?.trim().isEmpty == true
            ? null
            : o.callerText?.trim();
      }
      DateTime callDate = DateTime.now();
      if (o.date != null && o.date!.isNotEmpty) {
        final datePart = o.date!;
        final timePart = o.time ?? '00:00';
        final parsed = DateTime.tryParse('$datePart $timePart');
        if (parsed != null) callDate = parsed;
      }
      await createFromCall(
        callId: o.id,
        callerName: callerName,
        description: o.issue ?? '',
        callDate: callDate,
        titleTimestamp: callDate,
      );
      created++;
    }
    return created;
  }
}
