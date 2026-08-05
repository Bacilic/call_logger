// Η «δοκιμαστική βάση σεναρίων» αναγνωρίζεται από υπογραφή ΜΕΣΑ στα δεδομένα,
// όχι από το όνομα του αρχείου. Συμβόλαιο: ο σπόρος που δημιουργεί τη
// δοκιμαστική βάση την υπογράφει στο περιεχόμενό της — η μετονομασία δεν την
// κρύβει, και η κανονική βάση δεν σημαίνεται ψευδώς όποιο όνομα κι αν έχει.
//
//   flutter test test/features/database/debug/debug_scenario_signature_test.dart --timeout 30s

import 'dart:io';

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/database/debug/integrity_debug_provider_refresh.dart';
import 'package:call_logger/features/database/debug/integrity_debug_seeder_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_reporter.dart';
import '../../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String hospitalPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    initSqfliteFfiForTests();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();

    tempDir = await Directory.systemTemp.createTemp('debug_signature_');
    hospitalPath = '${tempDir.path}/hospital.db';
    await DatabaseHelper.instance.createNewDatabaseFile(hospitalPath);
    await DatabaseHelper.instance.closeConnection();
    await SettingsService().setDatabasePath(hospitalPath);
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('ο σπορέας υπογράφει τη δοκιμαστική βάση μέσα στα δεδομένα της', () async {
    await DatabaseHelper.instance.initializeDatabase();
    final seeder = IntegrityDebugSeederService();
    final debugPath = await seeder.resolveDebugDatabasePath();

    final result = await seeder.seedAndActivate();
    expect(
      result.success,
      isTrue,
      reason: greekExpectMsg(
        'Προϋπόθεση: ο seeder ολοκληρώνεται (${result.errorMessage})',
      ),
    );

    final profile = await profileDatabaseFile(debugPath);
    expect(
      profile.hasDebugScenarioSignature,
      isTrue,
      reason: greekExpectMsg(
        'Χωρίς υπογραφή στο περιεχόμενο, η αναγνώριση θα κρεμόταν από το '
        'όνομα του αρχείου — που αλλάζει με μια μετονομασία',
      ),
    );
  });

  test('η υπογραφή ταξιδεύει με το περιεχόμενο — η μετονομασία δεν την κρύβει', () async {
    await DatabaseHelper.instance.initializeDatabase();
    final seeder = IntegrityDebugSeederService();
    final debugPath = await seeder.resolveDebugDatabasePath();
    await seeder.seedAndActivate();
    await DatabaseHelper.instance.closeConnection();

    final renamedPath = p.join(tempDir.path, 'patates.db');
    await File(debugPath).copy(renamedPath);

    final profile = await profileDatabaseFile(renamedPath);
    expect(
      profile.hasDebugScenarioSignature,
      isTrue,
      reason: greekExpectMsg(
        'Η «patates.db» με τεχνητά δεδομένα παραμένει δοκιμαστική — το είδος '
        'της βάσης το λέει το περιεχόμενο, όχι το όνομα',
      ),
    );
  });

  test('η ΕΝΕΡΓΗ δοκιμαστική βάση κρατά ανοιχτά τα σενάρια', () async {
    await DatabaseHelper.instance.initializeDatabase();
    await IntegrityDebugSeederService().seedAndActivate();

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(activeDatabaseHasDebugScenariosProvider.future),
      isTrue,
      reason: greekExpectMsg(
        'Τα σενάρια είναι ιδιότητα της ανοιχτής βάσης, όχι της επίσκεψης στην '
        'οθόνη — αλλιώς ο μόνος τρόπος να ξαναφανούν είναι νέος σπορέας',
      ),
    );
  });

  test('κανονική ενεργή βάση δεν ξεκλειδώνει σενάρια', () async {
    await DatabaseHelper.instance.initializeDatabase();

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(activeDatabaseHasDebugScenariosProvider.future),
      isFalse,
      reason: greekExpectMsg(
        'Σε αληθινή βάση οι κάρτες σεναρίων θα υπόσχονταν τεχνητά δεδομένα '
        'που δεν υπάρχουν',
      ),
    );
  });

  test('κανονική βάση δεν σημαίνεται — ακόμη κι αν λέγεται integrity_debug.db', () async {
    final hospitalProfile = await profileDatabaseFile(hospitalPath);
    expect(
      hospitalProfile.hasDebugScenarioSignature,
      isFalse,
      reason: greekExpectMsg('Κανονική βάση χωρίς υπογραφή σπορέα'),
    );

    // Κανονική (κενή) βάση που απλώς φέρει το όνομα της δοκιμαστικής — όπως
    // μετά από επαναφορά αληθινών δεδομένων πάνω στο ίδιο αρχείο.
    final fakeDir = Directory(p.join(tempDir.path, 'fake'));
    await fakeDir.create(recursive: true);
    final fakePath = p.join(
      fakeDir.path,
      IntegrityDebugSeederService.databaseFileName,
    );
    await DatabaseHelper.instance.createNewDatabaseFile(fakePath);
    await DatabaseHelper.instance.closeConnection();

    final fakeProfile = await profileDatabaseFile(fakePath);
    expect(
      fakeProfile.hasDebugScenarioSignature,
      isFalse,
      reason: greekExpectMsg(
        'Μετά από επαναφορά αληθινών δεδομένων πάνω στην integrity_debug.db, '
        'η λωρίδα «τεχνητά δεδομένα» θα έλεγε ψέματα',
      ),
    );
  });
}
