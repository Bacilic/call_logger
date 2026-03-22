import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/init/app_init_provider.dart';
import 'package:call_logger/core/init/app_initializer.dart';
import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Σταθερές δεδομένων δοκιμών (απομονωμένη βάση + seed).
const String kTestPhoneDigits = '2345';
const String kTestUserFirstName = 'Δοκιμή';
const String kTestUserLastName = 'Χρήστης';
const String kTestEquipmentCode = 'PC-TEST';
const String kTestDepartmentName = 'Τμήμα Δοκιμών';
const String kTestCategoryName = 'Δοκιμαστική Κατηγορία';
const String kTestHistorySearchMarker = 'TEST_ELL_MARKER';

Directory? _testTempDir;

/// Προώθηση UI χωρίς [pumpAndSettle]: στην οθόνη Κλήσεων το χρονόμετρο κλήσης
/// ([Timer.periodic]) κρατά πάντα pending frame, οπότε το `pumpAndSettle` θα έληγε
/// μόνο μετά το timeout (πολλαπλά δευτερόλεπτα ανά κλήση) ή θα «έδενε» τη σουίτα.
///
/// [totalSimulated] ~ συνολικός εικονικός χρόνος που δίνουμε στο binding (βήμα × επαναλήψεις).
Future<void> pumpUntilSettled(
  WidgetTester tester, {
  int steps = 30,
  Duration step = const Duration(milliseconds: 60),
}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(step);
  }
}

/// Μεγαλύτερη αναμονή μετά την πρώτη φόρτωση (async providers, debounce ~350ms).
Future<void> pumpUntilSettledLong(WidgetTester tester) async {
  await pumpUntilSettled(tester, steps: 45, step: const Duration(milliseconds: 60));
}

/// Αρχικοποίηση sqflite FFI (υποχρεωτικό για desktop/unit tests).
void initSqfliteFfiForTests() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// Δημιουργεί πίνακα τμημάτων αν λείπει (νέα κενή βάση από `_onCreate`).
Future<void> _ensureDepartmentsTable() async {
  final db = await DatabaseHelper.instance.database;
  await db.execute('''
    CREATE TABLE IF NOT EXISTS departments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      building TEXT,
      color TEXT DEFAULT '#1976D2',
      notes TEXT,
      map_floor TEXT,
      map_x REAL DEFAULT 0.0,
      map_y REAL DEFAULT 0.0,
      map_width REAL DEFAULT 0.0,
      map_height REAL DEFAULT 0.0,
      is_deleted INTEGER DEFAULT 0
    )
  ''');
}

/// Γεμίζει την απομονωμένη βάση με ελάχιστο κατάλογο για ροές κλήσεων/ιστορικού.
Future<void> seedIsolatedTestDatabase() async {
  final db = await DatabaseHelper.instance.database;
  await _ensureDepartmentsTable();
  await db.delete('tasks');
  await db.delete('calls');
  try {
    await db.delete('user_equipment');
  } catch (_) {
    // Παλιά απομονωμένα αρχεία πριν το Milestone 1 (M2M).
  }
  try {
    await db.delete('user_phones');
  } catch (_) {
    // Παλιά απομονωμένα αρχεία πριν το Milestone 2 (M2M τηλεφώνων).
  }
  try {
    await db.delete('phones');
  } catch (_) {}
  await db.delete('equipment');
  await db.delete('users');
  await db.delete('categories');
  await db.delete('departments');

  final deptId = await db.insert('departments', {
    'name': kTestDepartmentName,
    'building': '',
    'is_deleted': 0,
  });

  final userId = await db.insert('users', {
    'first_name': kTestUserFirstName,
    'last_name': kTestUserLastName,
    'department_id': deptId,
    'is_deleted': 0,
  });
  final phoneId = await db.insert('phones', {'number': kTestPhoneDigits});
  await db.insert('user_phones', {
    'user_id': userId,
    'phone_id': phoneId,
  });

  final equipmentId = await db.insert('equipment', {
    'code_equipment': kTestEquipmentCode,
    'type': 'Desktop',
    'is_deleted': 0,
  });
  await db.insert('user_equipment', {
    'user_id': userId,
    'equipment_id': equipmentId,
  });

  await db.insert('categories', {
    'name': kTestCategoryName,
    'is_deleted': 0,
  });

  LookupService.instance.resetForReload();
  await LookupService.instance.loadFromDatabase();
}

/// Επιπλέον εγγραφή κλήσης για δοκιμές αναζήτησης στο Ιστορικό (μετά το [seedIsolatedTestDatabase]).
Future<void> seedTestCallRowForHistorySearch() async {
  await DatabaseHelper.instance.insertCall(
    CallModel(
      phoneText: kTestPhoneDigits,
      issue: '$kTestHistorySearchMarker ιστορικό αναζήτηση',
      status: 'completed',
    ),
  );
}

/// Δεσμεύει προσωρινό αρχείο SQLite και ανοίγει απομονωμένη βάση.
Future<void> bindCallLoggerIsolatedTestDatabase() async {
  initSqfliteFfiForTests();
  _testTempDir ??= await Directory.systemTemp.createTemp('call_logger_test_');
  final dbPath = p.join(_testTempDir!.path, 'isolated_test.db');
  await DatabaseHelper.bindTestDatabaseFile(dbPath);
  await DatabaseHelper.instance.database;
  await seedIsolatedTestDatabase();
}

/// Καθαρισμός μετά την ομάδα δοκιμών.
Future<void> releaseCallLoggerTestDatabase() async {
  await DatabaseHelper.instance.closeConnection();
  DatabaseHelper.releaseTestDatabaseBinding();
  try {
    if (_testTempDir != null && await _testTempDir!.exists()) {
      await _testTempDir!.delete(recursive: true);
    }
  } catch (_) {}
  _testTempDir = null;
}

/// Κοινά overrides Riverpod για τεστ με πραγματική απομονωμένη βάση.
/// Επιστρέφει λίστα overrides για [ProviderScope].
List<Override> callLoggerTestProviderOverrides() {
  return <Override>[
    appInitProvider.overrideWith(
      (ref) async => AppInitResult(
        result: DatabaseInitResult.success(),
        isLocalDevMode: true,
      ),
    ),
    lookupServiceProvider.overrideWith((ref) async {
      final service = LookupService.instance;
      service.resetForReload();
      await service.loadFromDatabase();
      return LookupLoadResult(service: service);
    }),
    showActiveTimerProvider.overrideWith((ref) async => true),
    showAnyDeskRemoteProvider.overrideWith((ref) async => true),
    showTasksBadgeProvider.overrideWith((ref) async => true),
  ];
}

/// `setUpAll` / `tearDownAll` για αρχεία που χρειάζονται απομονωμένη βάση.
void registerCallLoggerIsolatedDatabaseHooks() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await bindCallLoggerIsolatedTestDatabase();
  });
  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });
}

/// Όπως [registerCallLoggerIsolatedDatabaseHooks] χωρίς `TestWidgetsFlutterBinding` —
/// καλέστε πρώτα `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`.
void registerCallLoggerIsolatedDatabaseHooksIntegration() {
  setUpAll(() async {
    await bindCallLoggerIsolatedTestDatabase();
  });
  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });
}
