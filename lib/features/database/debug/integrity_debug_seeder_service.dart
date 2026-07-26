import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../../core/database/sqlite_types.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_path_resolution.dart';
import '../../../core/database/audit_service.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/search_text_normalizer.dart';

/// Αποτέλεσμα δημιουργίας/ενεργοποίησης της βάσης δοκιμών ακεραιότητας.
class IntegrityDebugSeedResult {
  const IntegrityDebugSeedResult._({
    required this.success,
    this.errorMessage,
    this.databasePath,
  });

  const IntegrityDebugSeedResult.success(String path)
    : this._(success: true, databasePath: path);

  const IntegrityDebugSeedResult.failure(String message)
    : this._(success: false, errorMessage: message);

  final bool success;
  final String? errorMessage;
  final String? databasePath;
}

/// Προγραμματιστικός μηχανισμός «Debug Error Seeder» — μόνο debug/desktop.
///
/// Δημιουργεί (ή αντικαθιστά) την `integrity_debug.db` με τεχνητά σφάλματα
/// για όλους τους ελέγχους ακεραιότητας (εκτός PRAGMA quick_check) και
/// φορτώνει την εφαρμογή σε αυτήν.
class IntegrityDebugSeederService {
  IntegrityDebugSeederService();

  static const String databaseFileName = 'integrity_debug.db';

  /// Τμήμα δοκιμής UX: μη εμφάνιση τηλεφώνων τμήματος (κοινόχρηστα στοιχεία).
  static const String dokimastikoDepartmentName = 'Δοκιμαστικό';
  static const List<String> dokimastikoSharedPhones = ['2001', '2002', '2003'];
  static const List<String> dokimastikoSharedEquipmentCodes = [
    '1001',
    '1002',
    '1003',
  ];

  /// Τμήμα δοκιμής UX: έλεγχος ροών διαγραφής υπαλλήλου/εξοπλισμού/τηλεφώνου.
  static const String informatikiDepartmentName = 'Πληροφορική';
  static const List<(String, String)> informatikiEmployees = [
    ('Άννα', 'Πατσαρίκα'),
    ('Βλάσης', 'Οικονόμου'),
    ('Ελένη', 'Ψαρά'),
    ('Βασίλης', 'Δρόσος'),
    ('Νίκος', 'Οικονομόπουλος'),
    ('Γιάννα', 'Κυριαζη'),
  ];
  static const List<String> informatikiPersonalPhones = [
    '2851',
    '2852',
    '2853',
    '2854',
    '2855',
    '2856',
  ];
  static const List<String> informatikiEquipmentCodes = [
    '3601',
    '3602',
    '3603',
    '3604',
    '3605',
    '3606',
  ];

  /// Διαθέσιμο μόνο σε debug builds σε desktop (Windows/macOS/Linux).
  static bool get isEnabled {
    if (!kDebugMode) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  /// Διαδρομή `integrity_debug.db` στον ίδιο φάκελο με την τρέχουσα/ρυθμισμένη βάση.
  Future<String> resolveDebugDatabasePath() async {
    final directory = await _resolveHostDirectory();
    return p.join(directory, databaseFileName);
  }

  Future<String> _resolveHostDirectory() async {
    try {
      final db = await DatabaseHelper.instance.database;
      return p.dirname(db.path);
    } catch (_) {
      final configured = await SettingsService().getDatabasePath();
      final resolved = await resolveEffectiveDatabasePath(configured);
      final dir = p.dirname(resolved.path);
      if (!await Directory(dir).exists()) {
        await Directory(dir).create(recursive: true);
      }
      return dir;
    }
  }

  /// Δημιουργεί/αντικαθιστά την debug βάση, την ενεργοποιεί και ανανεώνει lookup.
  Future<IntegrityDebugSeedResult> seedAndActivate() async {
    if (!isEnabled) {
      return const IntegrityDebugSeedResult.failure(
        'Ο seeder ακεραιότητας είναι διαθέσιμος μόνο σε debug desktop builds.',
      );
    }

    final debugPath = p.normalize(p.absolute(await resolveDebugDatabasePath()));

    try {
      await DatabaseHelper.instance.closeConnection();
      await _deleteSqliteBundle(debugPath);
      await DatabaseHelper.instance.createNewDatabaseFile(debugPath);
      await _seedIntegrityErrors(debugPath);
      await DatabaseHelper.bindTestDatabaseFile(debugPath);
      await DatabaseHelper.instance.initializeDatabase();
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
      return IntegrityDebugSeedResult.success(debugPath);
    } catch (e) {
      return IntegrityDebugSeedResult.failure('$e');
    }
  }

  Future<void> _deleteSqliteBundle(String dbPath) async {
    for (final path in [dbPath, '$dbPath-wal', '$dbPath-shm']) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _seedIntegrityErrors(String dbPath) async {
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await db.transaction((txn) async {
        await _insertBaseCatalog(txn);
        await _insertOrphanPhone(txn);
        await _insertPhoneInvalidDepartment(txn);
        await _insertCallsMissingSearchIndex(txn);
        await _insertTasksMissingSearchIndex(txn);
        await _insertUsersWithoutDepartment(txn);
        await _insertUsersInvalidDepartment(txn);
        await _insertTasksInvalidCall(txn);
        await _insertDepartmentsInvalidNameKey(txn);
        await _insertDepartmentInvalidFloor(txn);
        await _insertOrphanCallExternalLinks(txn);
        await _insertOrphanUserPhones(txn);
        await _insertOrphanDepartmentPhones(txn);
        await _insertOrphanUserEquipment(txn);
        await _insertEquipmentInvalidDepartment(txn);
        await _insertCallsDeletedLinkedEntities(txn);
        await _insertTasksDeletedLinkedEntities(txn);
        await _insertTasksTemporalInconsistency(txn);
        await _insertAuditMissingSearchText(txn);
        await _insertDokimastikoSharedAssetsScenario(txn);
        await insertInformatikiDeletionScenario(txn);
      });
    } finally {
      await db.close();
    }
  }

  Future<void> _insertBaseCatalog(Transaction txn) async {
    final kitchenKey = SearchTextNormalizer.normalizeForSearch('Debug Κουζίνα');
    final kitchenDeptId = await txn.insert('departments', {
      'name': 'Debug Κουζίνα',
      'name_key': kitchenKey,
      'is_deleted': 0,
    });

    await txn.insert('departments', {
      'name': 'Debug Μαγειρείο',
      'name_key': SearchTextNormalizer.normalizeForSearch('Debug Μαγειρείο'),
      'is_deleted': 0,
    });

    await txn.insert('users', {
      'first_name': 'Έγκυρος',
      'last_name': 'Υπάλληλος',
      'department_id': kitchenDeptId,
      'is_deleted': 0,
    });

    await txn.insert('categories', {
      'name': 'Debug Κατηγορία',
      'is_deleted': 0,
    });

    await txn.insert('phones', {
      'number': 'debug-valid-0001',
      'department_id': kitchenDeptId,
      'is_deleted': 0,
    });

    await txn.insert('equipment', {
      'code_equipment': 'DEBUG-VALID-PC',
      'type': 'Desktop',
      'is_deleted': 0,
    });

    await txn.insert('calls', {
      'phone_text': 'debug-valid-call',
      'status': 'completed',
      'search_index': 'debug valid call index',
      'lansweeper_state': 'unsent',
      'is_deleted': 0,
    });

    final now = DateTime.now().toIso8601String();
    await txn.insert('tasks', {
      'title': 'Debug έγκυρη εκκρεμότητα',
      'status': 'open',
      'search_index': 'debug valid task index',
      'created_at': now,
      'updated_at': now,
      'is_deleted': 0,
    });
  }

  Future<void> _insertOrphanPhone(Transaction txn) async {
    await txn.insert('phones', {
      'number': 'debug-orphan-phone',
      'department_id': null,
      'is_deleted': 0,
    });
  }

  /// Τηλέφωνο με department_id που λείπει εντελώς (hard-missing).
  Future<void> _insertPhoneInvalidDepartment(Transaction txn) async {
    await txn.insert('phones', {
      'number': 'debug-phone-missing-dept',
      'department_id': 990101,
      'is_deleted': 0,
    });
    // Soft-deleted τμήμα — ΔΕΝ πρέπει να εμφανιστεί ως εύρημα.
    final softDeletedDeptId = await txn.insert('departments', {
      'name': 'Debug Soft-Deleted Phone Dept',
      'name_key': 'debug_soft_del_phone_dept',
      'is_deleted': 1,
    });
    await txn.insert('phones', {
      'number': 'debug-phone-softdeleted-dept',
      'department_id': softDeletedDeptId,
      'is_deleted': 0,
    });
  }

  Future<void> _insertCallsMissingSearchIndex(Transaction txn) async {
    await txn.insert('calls', {
      'phone_text': 'debug-call-no-index',
      'status': 'completed',
      'search_index': '',
      'lansweeper_state': 'unsent',
      'is_deleted': 0,
    });
  }

  Future<void> _insertTasksMissingSearchIndex(Transaction txn) async {
    final now = DateTime.now().toIso8601String();
    await txn.insert('tasks', {
      'title': 'Debug εκκρεμότητα χωρίς ευρετήριο',
      'status': 'open',
      'search_index': '',
      'created_at': now,
      'updated_at': now,
      'is_deleted': 0,
    });
  }

  Future<void> _insertUsersWithoutDepartment(Transaction txn) async {
    await txn.insert('users', {
      'first_name': 'Χωρίς',
      'last_name': 'Τμήμα',
      'department_id': null,
      'is_deleted': 0,
    });
  }

  Future<void> _insertUsersInvalidDepartment(Transaction txn) async {
    final deletedDeptId = await txn.insert('departments', {
      'name': 'Debug Διαγραμμένο Τμήμα',
      'name_key': SearchTextNormalizer.normalizeForSearch(
        'Debug Διαγραμμένο Τμήμα',
      ),
      'is_deleted': 1,
    });
    await txn.insert('users', {
      'first_name': 'Άκυρο',
      'last_name': 'Τμήμα',
      'department_id': deletedDeptId,
      'is_deleted': 0,
    });
  }

  Future<void> _insertTasksInvalidCall(Transaction txn) async {
    final deletedCallId = await txn.insert('calls', {
      'phone_text': 'debug-deleted-call',
      'status': 'completed',
      'search_index': 'deleted call',
      'lansweeper_state': 'unsent',
      'is_deleted': 1,
    });
    final now = DateTime.now().toIso8601String();
    await txn.insert('tasks', {
      'title': 'Debug εκκρεμότητα άκυρη κλήση',
      'status': 'open',
      'search_index': 'debug invalid call task',
      'call_id': deletedCallId,
      'created_at': now,
      'updated_at': now,
      'is_deleted': 0,
    });
  }

  Future<void> _insertDepartmentsInvalidNameKey(Transaction txn) async {
    await txn.insert('departments', {
      'name': 'Debug Λάθος name_key',
      'name_key': 'totally_wrong_key',
      'is_deleted': 0,
    });
    await txn.insert('departments', {
      'name': 'Debug Κενό name_key',
      'name_key': '',
      'is_deleted': 0,
    });
  }

  /// Τμήμα με floor_id που λείπει εντελώς + μισή τοποθέτηση χάρτη.
  Future<void> _insertDepartmentInvalidFloor(Transaction txn) async {
    await txn.insert('departments', {
      'name': 'Debug Τμήμα Ανύπαρκτος Όροφος',
      'name_key': SearchTextNormalizer.normalizeForSearch(
        'Debug Τμήμα Ανύπαρκτος Όροφος',
      ),
      'floor_id': 990201,
      'map_floor': 990201,
      'map_x': 120.0,
      'map_y': 80.0,
      'map_width': 40.0,
      'map_height': 30.0,
      'is_deleted': 0,
    });
  }

  Future<void> _insertOrphanCallExternalLinks(Transaction txn) async {
    await txn.insert('call_external_links', {
      'call_id': 999_999,
      'external_id': 'debug-orphan-link',
      'provider': 'lansweeper',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _insertOrphanUserPhones(Transaction txn) async {
    final deletedUserId = await txn.insert('users', {
      'first_name': 'Διαγραμμένος',
      'last_name': 'Για Junction',
      'is_deleted': 1,
    });
    final phoneId = await txn.insert('phones', {
      'number': 'debug-junction-user-phone',
      'is_deleted': 0,
    });
    await txn.insert('user_phones', {
      'user_id': deletedUserId,
      'phone_id': phoneId,
    });
  }

  Future<void> _insertOrphanDepartmentPhones(Transaction txn) async {
    final deletedDeptId = await txn.insert('departments', {
      'name': 'Debug Διαγρ. για dept_phones',
      'name_key': 'debug_del_dept_phones',
      'is_deleted': 1,
    });
    final phoneId = await txn.insert('phones', {
      'number': 'debug-junction-dept-phone',
      'is_deleted': 0,
    });
    await txn.insert('department_phones', {
      'department_id': deletedDeptId,
      'phone_id': phoneId,
    });
  }

  Future<void> _insertOrphanUserEquipment(Transaction txn) async {
    final deletedUserId = await txn.insert('users', {
      'first_name': 'Διαγραμμένος',
      'last_name': 'Για Εξοπλισμό',
      'is_deleted': 1,
    });
    final equipmentId = await txn.insert('equipment', {
      'code_equipment': 'DEBUG-JUNCTION-EQ',
      'type': 'Laptop',
      'is_deleted': 0,
    });
    await txn.insert('user_equipment', {
      'user_id': deletedUserId,
      'equipment_id': equipmentId,
    });
  }

  /// Εξοπλισμός με department_id που λείπει εντελώς (hard-missing).
  Future<void> _insertEquipmentInvalidDepartment(Transaction txn) async {
    await txn.insert('equipment', {
      'code_equipment': 'DEBUG-EQ-MISSING-DEPT',
      'type': 'Desktop',
      'department_id': 990301,
      'is_deleted': 0,
    });
    // Soft-deleted τμήμα — ΔΕΝ πρέπει να εμφανιστεί ως εύρημα.
    final softDeletedDeptId = await txn.insert('departments', {
      'name': 'Debug Soft-Deleted Eq Dept',
      'name_key': 'debug_soft_del_eq_dept',
      'is_deleted': 1,
    });
    await txn.insert('equipment', {
      'code_equipment': 'DEBUG-EQ-SOFTDEL-DEPT',
      'type': 'Laptop',
      'department_id': softDeletedDeptId,
      'is_deleted': 0,
    });
  }

  /// Κλήση με αναφορές σε εγγραφές που ΛΕΙΠΟΥΝ εντελώς (hard-missing IDs).
  /// Σημ.: soft-deleted αναφορές δεν είναι εύρημα — είναι «ιστορική αλήθεια».
  Future<void> _insertCallsDeletedLinkedEntities(Transaction txn) async {
    await txn.insert('calls', {
      'phone_text': 'debug-call-missing-fks',
      'caller_text': 'Snapshot Καλών (ανύπαρκτος)',
      'equipment_text': 'SNAPSHOT-EQ',
      'status': 'completed',
      'search_index': 'debug call missing refs',
      'caller_id': 990001,
      'equipment_id': 990002,
      'category_id': 990003,
      'lansweeper_state': 'unsent',
      'is_deleted': 0,
    });

    // Επιπλέον: κλήση με soft-deleted αναφορά — ΔΕΝ πρέπει να εμφανιστεί ως
    // εύρημα (έλεγχος ότι η «ιστορική αλήθεια» δεν σημαίνεται ως σφάλμα).
    final softDeletedCallerId = await txn.insert('users', {
      'first_name': 'Soft',
      'last_name': 'Διαγραμμένος',
      'is_deleted': 1,
    });
    await txn.insert('calls', {
      'phone_text': 'debug-call-softdeleted-fk',
      'caller_text': 'Soft Διαγραμμένος',
      'status': 'completed',
      'search_index': 'debug call soft deleted ref',
      'caller_id': softDeletedCallerId,
      'lansweeper_state': 'unsent',
      'is_deleted': 0,
    });
  }

  /// Εκκρεμότητα με αναφορές σε εγγραφές που ΛΕΙΠΟΥΝ εντελώς (hard-missing IDs).
  Future<void> _insertTasksDeletedLinkedEntities(Transaction txn) async {
    final now = DateTime.now().toIso8601String();
    await txn.insert('tasks', {
      'title': 'Debug εκκρεμότητα ανύπαρκτες αναφορές',
      'status': 'open',
      'search_index': 'debug task missing refs',
      'user_text': 'Snapshot Task Caller (ανύπαρκτος)',
      'equipment_text': 'SNAPSHOT-TASK-EQ',
      'department_text': 'Snapshot Task Dept',
      'phone_text': 'snapshot-task-phone',
      'caller_id': 990011,
      'equipment_id': 990012,
      'department_id': 990013,
      'phone_id': 990014,
      'created_at': now,
      'updated_at': now,
      'is_deleted': 0,
    });

    // Επιπλέον: εκκρεμότητα με soft-deleted αναφορά — ΔΕΝ είναι εύρημα.
    final softDeletedDeptId = await txn.insert('departments', {
      'name': 'Debug Soft-Deleted Task Dept',
      'name_key': 'debug_soft_del_task_dept',
      'is_deleted': 1,
    });
    await txn.insert('tasks', {
      'title': 'Debug εκκρεμότητα soft-deleted τμήμα',
      'status': 'open',
      'search_index': 'debug task soft deleted dept',
      'department_text': 'Debug Soft-Deleted Task Dept',
      'department_id': softDeletedDeptId,
      'created_at': now,
      'updated_at': now,
      'is_deleted': 0,
    });
  }

  Future<void> _insertTasksTemporalInconsistency(Transaction txn) async {
    await txn.insert('tasks', {
      'title': 'Debug χρονική ασυνέπεια',
      'status': 'open',
      'search_index': 'debug temporal task',
      'created_at': '2026-06-10T12:00:00.000',
      'updated_at': '2026-06-09T12:00:00.000',
      'is_deleted': 0,
    });
  }

  Future<void> _insertDokimastikoSharedAssetsScenario(Transaction txn) async {
    final deptId = await txn.insert('departments', {
      'name': dokimastikoDepartmentName,
      'name_key': SearchTextNormalizer.normalizeForSearch(
        dokimastikoDepartmentName,
      ),
      'is_deleted': 0,
    });

    for (final phone in dokimastikoSharedPhones) {
      final phoneId = await txn.insert('phones', {
        'number': phone,
        'is_deleted': 0,
      });
      await txn.insert('department_phones', {
        'department_id': deptId,
        'phone_id': phoneId,
      });
    }

    for (final code in dokimastikoSharedEquipmentCodes) {
      await txn.insert('equipment', {
        'code_equipment': code,
        'department_id': deptId,
        'is_deleted': 0,
      });
    }
  }

  /// Σενάριο ελέγχου διαγραφών: τμήμα Πληροφορική με 6 υπαλλήλους,
  /// προσωπικά τηλέφωνα και owned εξοπλισμό (department_id NULL).
  ///
  /// Επιπλέον πολλαπλές συνδέσεις για δοκιμή απαρίθμησης:
  /// Δρόσος 2854/3604 → τηλέφωνο 9, εξοπλισμός 7· Βλάσης 2852/3602 → 5 και 3.
  Future<void> insertInformatikiDeletionScenario(Transaction txn) async {
    final deptId = await txn.insert('departments', {
      'name': informatikiDepartmentName,
      'name_key': SearchTextNormalizer.normalizeForSearch(
        informatikiDepartmentName,
      ),
      'is_deleted': 0,
    });

    int? drososPhoneId;
    int? drososEquipmentId;
    int? vlasisPhoneId;
    int? vlasisEquipmentId;

    for (var i = 0; i < informatikiEmployees.length; i++) {
      final employee = informatikiEmployees[i];
      final phoneNumber = informatikiPersonalPhones[i];
      final equipmentCode = informatikiEquipmentCodes[i];

      final userId = await txn.insert('users', {
        'first_name': employee.$1,
        'last_name': employee.$2,
        'department_id': deptId,
        'is_deleted': 0,
      });

      final phoneId = await txn.insert('phones', {
        'number': phoneNumber,
        'is_deleted': 0,
      });
      await txn.insert('user_phones', {'user_id': userId, 'phone_id': phoneId});

      final equipmentId = await txn.insert('equipment', {
        'code_equipment': equipmentCode,
        'department_id': null,
        'is_deleted': 0,
      });
      await txn.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': equipmentId,
      });

      if (phoneNumber == '2854') {
        drososPhoneId = phoneId;
        drososEquipmentId = equipmentId;
      } else if (phoneNumber == '2852') {
        vlasisPhoneId = phoneId;
        vlasisEquipmentId = equipmentId;
      }
    }

    final now = DateTime.now().toIso8601String();

    // Βασίλης Δρόσος — τηλέφωνο 2854: dept + 2 tasks + 5 calls (= 9 με κάτοχο).
    await txn.insert('department_phones', {
      'department_id': deptId,
      'phone_id': drososPhoneId,
    });
    for (var i = 0; i < 2; i++) {
      await txn.insert('tasks', {
        'title': 'Debug Δρόσος εκκρεμότητα τηλ. ${i + 1}',
        'status': 'open',
        'search_index': 'debug drosos phone task ${i + 1}',
        'phone_id': drososPhoneId,
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      });
    }
    for (var i = 0; i < 5; i++) {
      await txn.insert('calls', {
        'phone_text': '2854',
        'status': 'completed',
        'search_index': 'debug drosos phone call ${i + 1}',
        'lansweeper_state': 'unsent',
        'is_deleted': 0,
      });
    }

    // Βασίλης Δρόσος — εξοπλισμός 3604: 2 tasks + 4 calls (= 7 με κάτοχο).
    for (var i = 0; i < 2; i++) {
      await txn.insert('tasks', {
        'title': 'Debug Δρόσος εκκρεμότητα εξοπλ. ${i + 1}',
        'status': 'open',
        'search_index': 'debug drosos equipment task ${i + 1}',
        'equipment_id': drososEquipmentId,
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      });
    }
    for (var i = 0; i < 4; i++) {
      await txn.insert('calls', {
        'equipment_id': drososEquipmentId,
        'equipment_text': '3604',
        'status': 'completed',
        'search_index': 'debug drosos equipment call ${i + 1}',
        'lansweeper_state': 'unsent',
        'is_deleted': 0,
      });
    }

    // Βλάσης Οικονόμου — τηλέφωνο 2852: dept + 1 task + 2 calls (= 5 με κάτοχο).
    await txn.insert('department_phones', {
      'department_id': deptId,
      'phone_id': vlasisPhoneId,
    });
    await txn.insert('tasks', {
      'title': 'Debug Βλάσης εκκρεμότητα τηλ.',
      'status': 'open',
      'search_index': 'debug vlasis phone task',
      'phone_id': vlasisPhoneId,
      'created_at': now,
      'updated_at': now,
      'is_deleted': 0,
    });
    for (var i = 0; i < 2; i++) {
      await txn.insert('calls', {
        'phone_text': '2852',
        'status': 'completed',
        'search_index': 'debug vlasis phone call ${i + 1}',
        'lansweeper_state': 'unsent',
        'is_deleted': 0,
      });
    }

    // Βλάσης Οικονόμου — εξοπλισμός 3602: 1 task + 1 call (= 3 με κάτοχο).
    await txn.insert('tasks', {
      'title': 'Debug Βλάσης εκκρεμότητα εξοπλ.',
      'status': 'open',
      'search_index': 'debug vlasis equipment task',
      'equipment_id': vlasisEquipmentId,
      'created_at': now,
      'updated_at': now,
      'is_deleted': 0,
    });
    await txn.insert('calls', {
      'equipment_id': vlasisEquipmentId,
      'equipment_text': '3602',
      'status': 'completed',
      'search_index': 'debug vlasis equipment call',
      'lansweeper_state': 'unsent',
      'is_deleted': 0,
    });
  }

  Future<void> _insertAuditMissingSearchText(Transaction txn) async {
    await txn.insert('audit_log', {
      'action': 'DEBUG_SEED',
      'timestamp': DateTime.now().toIso8601String(),
      'user_performing': 'integrity-debug-seeder',
      'details': 'Τεχνητή εγγραφή audit χωρίς search_text για UX δοκιμή',
      'entity_type': AuditEntityTypes.user,
      'entity_id': 1,
      'entity_name': 'Debug Audit Target',
      'search_text': '',
    });
  }
}
