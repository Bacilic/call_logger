import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_excel_validator.dart';
import 'package:call_logger/core/database/old_database/lamp_settings_store.dart';
import 'package:call_logger/core/database/old_database/old_excel_importer.dart';
import 'package:call_logger/features/lamp/controllers/lamp_import_controller.dart';
import 'package:call_logger/features/lamp/controllers/lamp_path_management.dart';
import 'package:call_logger/features/lamp/controllers/lamp_screen_host.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/lamp_network_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:call_logger/features/lamp/widgets/lamp_import_report_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// No-op ανανέωση σύγκρισης — αποφεύγει την εξάρτηση από ζωντανό [WidgetRef].
Future<void> _noopComparison({
  required String readPath,
  required String outputPath,
}) async {}

class _FakeHost implements LampScreenHost {
  _FakeHost({required this.importer});

  final OldExcelImporter importer;
  int importerCallCount = 0;
  int confirmationCallCount = 0;
  final snackMessages = <String>[];

  @override
  bool mounted = true;

  @override
  StateSetter? lampSettingsDialogSetState;

  @override
  void notifyState() {}

  @override
  void showSnack(
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 5),
  }) {
    snackMessages.add(message);
  }

  @override
  Future<void> showLampErrorDialog(String message) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #shared) {
      return LampScreenShared(
        settings: LampSettingsStore(),
        repository: OldEquipmentRepository(),
        issueResolutionService: LampIssueResolutionService(),
        networkIssueResolutionService: LampNetworkIssueResolutionService(),
        migrationService: LampMigrationService(),
        importer: _CountingImporter(
          delegate: importer,
          onCall: () => importerCallCount++,
        ),
      );
    }
    if (invocation.memberName == #context) {
      return _FakeBuildContext();
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CountingImporter extends OldExcelImporter {
  _CountingImporter({required this.delegate, required this.onCall});

  final OldExcelImporter delegate;
  final VoidCallback onCall;

  @override
  Future<LampImportResult> importExcel({
    required String excelPath,
    required String databasePath,
    LampImportProgressCallback? onProgress,
  }) {
    onCall();
    return delegate.importExcel(
      excelPath: excelPath,
      databasePath: databasePath,
      onProgress: onProgress,
    );
  }
}

class _FakeImporter extends OldExcelImporter {
  @override
  Future<LampImportResult> importExcel({
    required String excelPath,
    required String databasePath,
    LampImportProgressCallback? onProgress,
  }) async {
    onProgress?.call(const LampImportProgress('Ανάγνωση Excel'));
    return LampImportResult(
      databasePath: databasePath,
      importedRows: const <String, int>{'equipment': 1},
      issueCount: 0,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
  });

  LampImportController buildController({
    required _FakeHost host,
    required LampPathController path,
    RecreateConfirmationCallback? confirmRecreateExistingDatabase,
    required ImportReportFlowCallback showImportReportDialog,
  }) {
    return LampImportController(
      host: host,
      path: path,
      confirmRecreateExistingDatabase: confirmRecreateExistingDatabase,
      showImportReportDialog: showImportReportDialog,
      refreshDbComparison: _noopComparison,
    );
  }

  group('LampImportController.runImport', () {
    test(
      'asks confirmation before import when output db already exists',
      () async {
        final host = _FakeHost(importer: _FakeImporter());
        final path = LampPathController(host: host);
        addTearDown(path.dispose);

        final importController = buildController(
          host: host,
          path: path,
          confirmRecreateExistingDatabase: ({required fileName}) async {
            host.confirmationCallCount++;
            return true;
          },
          showImportReportDialog: ({
            required stopwatch,
            required readPathContext,
            required importRunner,
          }) async {
            await importRunner((_) {});
            return const LampImportReportOutcome(
              action: LampImportReportCloseAction.dismiss,
            );
          },
        );

        final tempDir = await Directory.systemTemp.createTemp('lamp_import_ctl');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final excelPath = p.join(tempDir.path, 'test.xlsx');
        final dbPath = p.join(tempDir.path, 'existing.db');
        await File(excelPath).writeAsString('excel');
        await File(dbPath).writeAsBytes(<int>[1, 2, 3]);

        path.excelController.text = excelPath;
        path.outputDbController.text = dbPath;

        await importController.runImport(
          onImportStart: () {},
          onImportSuccess: (_) {},
          afterImportValidate: () async {},
          onImportFailureReload: () async {},
        );

        expect(host.confirmationCallCount, 1);
        expect(host.importerCallCount, 1);
        expect(host.snackMessages, isEmpty);
      },
    );

    test('skips confirmation when output db does not exist', () async {
      final host = _FakeHost(importer: _FakeImporter());
      final path = LampPathController(host: host);
      addTearDown(path.dispose);

      final importController = buildController(
        host: host,
        path: path,
        showImportReportDialog: ({
          required stopwatch,
          required readPathContext,
          required importRunner,
        }) async {
          await importRunner((_) {});
          return const LampImportReportOutcome(
            action: LampImportReportCloseAction.dismiss,
          );
        },
      );

      final tempDir = await Directory.systemTemp.createTemp('lamp_import_ctl2');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final excelPath = p.join(tempDir.path, 'test.xlsx');
      final dbPath = p.join(tempDir.path, 'new.db');
      await File(excelPath).writeAsString('excel');

      path.excelController.text = excelPath;
      path.outputDbController.text = dbPath;

      await importController.runImport(
        onImportStart: () {},
        onImportSuccess: (_) {},
        afterImportValidate: () async {},
        onImportFailureReload: () async {},
      );

      expect(host.importerCallCount, 1);
    });

    test('με κενή ανάγνωση η νέα βάση γίνεται βάση ανάγνωσης', () async {
      final host = _FakeHost(importer: _FakeImporter());
      final path = LampPathController(host: host);
      addTearDown(path.dispose);

      final importController = buildController(
        host: host,
        path: path,
        showImportReportDialog: ({
          required stopwatch,
          required readPathContext,
          required importRunner,
        }) async {
          expect(readPathContext.readPathEmpty, isTrue);
          await importRunner((_) {});
          return const LampImportReportOutcome(
            action: LampImportReportCloseAction.dismiss,
          );
        },
      );

      final tempDir =
          await Directory.systemTemp.createTemp('lamp_import_empty_read');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final excelPath = p.join(tempDir.path, 'test.xlsx');
      final dbPath = p.join(tempDir.path, 'new.db');
      await File(excelPath).writeAsString('excel');

      path.excelController.text = excelPath;
      path.outputDbController.text = dbPath;
      path.readDbController.text = '';

      final result = await importController.runImport(
        onImportStart: () {},
        onImportSuccess: (_) {},
        afterImportValidate: () async {},
        onImportFailureReload: () async {},
      );

      expect(path.readDbController.text, dbPath);
      expect(result.successMessage, contains('ευθυγραμμίστηκε'));
    });

    test(
      'με γεμάτη διαφορετική ανάγνωση χωρίς διακόπτη η ανάγνωση δεν αλλάζει',
      () async {
        final host = _FakeHost(importer: _FakeImporter());
        final path = LampPathController(host: host);
        addTearDown(path.dispose);

        final importController = buildController(
          host: host,
          path: path,
          showImportReportDialog: ({
            required stopwatch,
            required readPathContext,
            required importRunner,
          }) async {
            expect(readPathContext.readDiffersFromOutput, isTrue);
            await importRunner((_) {});
            return const LampImportReportOutcome(
              action: LampImportReportCloseAction.dismiss,
              setAsReadDatabase: false,
            );
          },
        );

        final tempDir =
            await Directory.systemTemp.createTemp('lamp_import_keep_read');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final excelPath = p.join(tempDir.path, 'test.xlsx');
        final dbPath = p.join(tempDir.path, 'new_out.db');
        final readPath = p.join(tempDir.path, 'existing_read.db');
        await File(excelPath).writeAsString('excel');

        path.excelController.text = excelPath;
        path.outputDbController.text = dbPath;
        path.readDbController.text = readPath;

        final result = await importController.runImport(
          onImportStart: () {},
          onImportSuccess: (_) {},
          afterImportValidate: () async {},
          onImportFailureReload: () async {},
        );

        expect(path.readDbController.text, readPath);
        expect(path.outputDbController.text, dbPath);
        expect(result.successMessage, contains('παρέμεινε ξεχωριστή'));
      },
    );

    test('με ενεργό διακόπτη η ανάγνωση γίνεται η νέα βάση', () async {
      final host = _FakeHost(importer: _FakeImporter());
      final path = LampPathController(host: host);
      addTearDown(path.dispose);

      final importController = buildController(
        host: host,
        path: path,
        showImportReportDialog: ({
          required stopwatch,
          required readPathContext,
          required importRunner,
        }) async {
          await importRunner((_) {});
          return const LampImportReportOutcome(
            action: LampImportReportCloseAction.dismiss,
            setAsReadDatabase: true,
          );
        },
      );

      final tempDir =
          await Directory.systemTemp.createTemp('lamp_import_switch_on');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final excelPath = p.join(tempDir.path, 'test.xlsx');
      final dbPath = p.join(tempDir.path, 'new_out.db');
      final readPath = p.join(tempDir.path, 'existing_read.db');
      await File(excelPath).writeAsString('excel');

      path.excelController.text = excelPath;
      path.outputDbController.text = dbPath;
      path.readDbController.text = readPath;

      await importController.runImport(
        onImportStart: () {},
        onImportSuccess: (_) {},
        afterImportValidate: () async {},
        onImportFailureReload: () async {},
      );

      expect(path.readDbController.text, dbPath);
    });

    test('μετά επιτυχημένη εισαγωγή επιστρέφεται μήνυμα επιτυχίας', () async {
      final host = _FakeHost(importer: _FakeImporter());
      final path = LampPathController(host: host);
      addTearDown(path.dispose);

      final importController = buildController(
        host: host,
        path: path,
        showImportReportDialog: ({
          required stopwatch,
          required readPathContext,
          required importRunner,
        }) async {
          await importRunner((_) {});
          return const LampImportReportOutcome(
            action: LampImportReportCloseAction.runIntegrityCheck,
          );
        },
      );

      final tempDir =
          await Directory.systemTemp.createTemp('lamp_import_integrity');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final excelPath = p.join(tempDir.path, 'test.xlsx');
      final dbPath = p.join(tempDir.path, 'new.db');
      await File(excelPath).writeAsString('excel');

      path.excelController.text = excelPath;
      path.outputDbController.text = dbPath;

      final result = await importController.runImport(
        onImportStart: () {},
        onImportSuccess: (_) {},
        afterImportValidate: () async {},
        onImportFailureReload: () async {},
      );

      expect(result.successMessage, isNotNull);
      expect(result.runIntegrityCheck, isTrue);
    });

    test(
      'δεν καλεί importer όταν το Excel διαγράφηκε πριν το κλικ',
      () async {
        final host = _FakeHost(importer: _FakeImporter());
        final path = LampPathController(host: host);
        addTearDown(path.dispose);

        final importController = buildController(
          host: host,
          path: path,
          showImportReportDialog: ({
            required stopwatch,
            required readPathContext,
            required importRunner,
          }) async {
            await importRunner((_) {});
            return const LampImportReportOutcome(
              action: LampImportReportCloseAction.dismiss,
            );
          },
        );

        final tempDir =
            await Directory.systemTemp.createTemp('lamp_import_del_excel');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final excelPath = p.join(tempDir.path, 'vanished.xlsx');
        final dbPath = p.join(tempDir.path, 'out.db');
        await File(excelPath).writeAsBytes(<int>[1, 2, 3]);

        path.excelController.text = excelPath;
        path.outputDbController.text = dbPath;

        await File(excelPath).delete();

        final result = await importController.runImport(
          onImportStart: () {},
          onImportSuccess: (_) {},
          afterImportValidate: () async {},
          onImportFailureReload: () async {},
        );

        expect(host.importerCallCount, 0);
        expect(result.failureMessage, isNotNull);
        expect(result.failureMessage, contains('δεν βρέθηκε'));
        expect(host.snackMessages, isNotEmpty);
        expect(host.snackMessages.last, contains('δεν βρέθηκε'));
      },
    );
  });

  group('LampImportController.excelImportDisabledReason', () {
    test('επιστρέφει μήνυμα Excel όταν η κατάσταση είναι missing', () {
      final host = _FakeHost(importer: _FakeImporter());
      final path = LampPathController(host: host);
      addTearDown(path.dispose);

      final importController = LampImportController(
        host: host,
        path: path,
        refreshDbComparison: _noopComparison,
      );

      path.excelController.text = r'C:\missing\source.xlsx';
      path.outputDbController.text = r'C:\out\lamp.db';

      const excelCheck = LampExcelCheckResult(LampExcelStatus.missing);
      final reason = importController.excelImportDisabledReason(
        excelPathCheck: excelCheck,
      );

      expect(reason, excelCheck.userMessageGreek);
    });
  });
}
