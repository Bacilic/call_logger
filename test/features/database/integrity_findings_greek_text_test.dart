// Τα κείμενα του Ελέγχου Ακεραιότητας παράγονται δυναμικά από ερωτήματα στη
// βάση, οπότε δεν αρκεί έλεγχος των σταθερών τίτλων: σπέρνουμε τη δοκιμαστική
// βάση σεναρίων, τρέχουμε τον πραγματικό έλεγχο και σαρώνουμε ό,τι βγήκε.
//
//   flutter test test/features/database/integrity_findings_greek_text_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/database_integrity_diagnostics.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/database/debug/integrity_debug_seeder_service.dart';
import 'package:call_logger/features/database/models/database_integrity_finding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_setup.dart';

/// Ονόματα πινάκων και στηλών που δεν επιτρέπεται να φτάσουν στον χρήστη.
const List<String> _technicalTerms = [
  'search_index',
  'search_text',
  'department_id',
  'call_id',
  'user_id',
  'phone_id',
  'equipment_id',
  'floor_id',
  'category_id',
  'entity_type',
  'entity_id',
  'name_key',
  'created_at',
  'updated_at',
  'is_deleted',
  'department_phones',
  'user_phones',
  'user_equipment',
  'call_external_links',
  'building_map_floors',
  'audit_log',
  'id=',
];

/// Το εύρημα των σχέσεων δείχνει σκόπιμα τον τεχνικό όρο δίπλα στο ελληνικό
/// όνομα — είναι διαγνωστικό και έρχεται ωμό από τη SQLite.
bool _allowsTechnicalNames(DatabaseIntegrityFinding f) =>
    f.checkType == IntegrityCheckType.foreignKeyViolations;

/// Αφαιρεί ό,τι είναι μέσα σε «…»: εκεί μπαίνουν τα **δεδομένα** του χρήστη
/// (ονόματα τμημάτων, τίτλοι εκκρεμοτήτων, κωδικοί), που δεν μεταφράζονται.
///
/// Είναι και το όριο που ελέγχει το τεστ: ορολογία της εφαρμογής έξω από τα
/// εισαγωγικά, δεδομένα μέσα.
String _withoutQuotedData(String text) =>
    text.replaceAll(RegExp('«[^»]*»'), '«…»');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    initSqfliteFfiForTests();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();

    tempDir = await Directory.systemTemp.createTemp('integrity_greek_');
    final path = '${tempDir.path}/hospital.db';
    await DatabaseHelper.instance.createNewDatabaseFile(path);
    await DatabaseHelper.instance.closeConnection();
    await SettingsService().setDatabasePath(path);
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('κανένα εύρημα δεν δείχνει όνομα πίνακα ή στήλης στον χρήστη', () async {
    await DatabaseHelper.instance.initializeDatabase();
    final seeded = await IntegrityDebugSeederService().seedAndActivate();
    expect(seeded.success, isTrue);

    final report = await DatabaseIntegrityDiagnostics().runChecks();
    expect(
      report.findings,
      isNotEmpty,
      reason: 'Ο σπορέας φτιάχνει προβλήματα — αν δεν βρέθηκε κανένα, το τεστ '
          'δεν αποδεικνύει τίποτα.',
    );

    final offenders = <String>[];
    for (final f in report.findings) {
      if (_allowsTechnicalNames(f)) continue;
      for (final raw in [f.title, f.description]) {
        final text = _withoutQuotedData(raw);
        for (final term in _technicalTerms) {
          if (text.contains(term)) {
            offenders.add('${f.checkType.name}: «$raw» → $term');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Τεχνικοί όροι σε κείμενο που διαβάζει ο χρήστης:\n'
          '${offenders.join('\n')}',
    );
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('οι παραβιάσεις σχέσεων κρατούν ελληνικό ΚΑΙ τεχνικό όνομα', () async {
    await DatabaseHelper.instance.initializeDatabase();
    await IntegrityDebugSeederService().seedAndActivate();

    final report = await DatabaseIntegrityDiagnostics().runChecks();
    final violations = report.findings
        .where((f) => f.checkType == IntegrityCheckType.foreignKeyViolations)
        .toList();

    expect(violations, isNotEmpty);
    for (final v in violations) {
      expect(
        v.description,
        contains('υπάρχει γραμμή που δείχνει σε ανύπαρκτη εγγραφή'),
      );
      // Ελληνικό όνομα μπροστά, τεχνικό σε παρένθεση.
      expect(v.description, matches(RegExp(r'[Α-Ωα-ω]+ \([a-z_]+\)')));
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
