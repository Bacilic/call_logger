import 'package:call_logger/core/database/old_database/lamp_excel_validator.dart';
import 'package:call_logger/core/database/old_database/lamp_old_db_validator.dart';
import 'package:call_logger/core/providers/lamp_db_comparison_provider.dart';
import 'package:call_logger/core/providers/lamp_excel_path_health_provider.dart';
import 'package:call_logger/features/lamp/controllers/lamp_import_controller.dart';
import 'package:call_logger/features/lamp/controllers/lamp_integrity_controller.dart';
import 'package:call_logger/features/lamp/controllers/lamp_path_management.dart';
import 'package:call_logger/features/lamp/controllers/lamp_screen_host.dart';
import 'package:call_logger/features/lamp/controllers/lamp_search_controller.dart';
import 'package:call_logger/features/lamp/widgets/lamp_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubPath extends LampPathController {
  _StubPath() : super(host: _ThrowingHost());

  @override
  String? outputPathFormatWarning() => null;

  @override
  String? readPathFormatWarning() => null;
}

class _ThrowingHost implements LampScreenHost {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubSearch extends LampSearchController {
  _StubSearch(LampPathController path)
    : super(host: _ThrowingHost(), path: path);
}

class _StubImport extends LampImportController {
  _StubImport(LampPathController path)
    : super(host: _ThrowingHost(), path: path);
}

class _StubIntegrity extends LampIntegrityController {
  _StubIntegrity(LampPathController path)
    : super(host: _ThrowingHost(), path: path);
}

// Ο διάλογος είναι `ConsumerStatefulWidget`: παρακολουθεί δύο providers και
// καλεί `refresh()` σε post-frame callback. Χωρίς αδρανή stubs το τεστ θα
// άγγιζε πραγματικό SharedPreferences και βάση Λάμπας μέσω FFI — δηλαδή θα
// κρέμαγε στον εικονικό χρόνο του binding αντί να αποτύχει.
class _StubExcelPathHealth extends LampExcelPathHealthNotifier {
  @override
  Future<LampExcelCheckResult?> build() async => null;

  @override
  Future<void> refresh({String? pathOverride}) async {}
}

class _StubDbComparison extends LampDbComparisonNotifier {
  @override
  Future<List<String>> build() async => const <String>[];

  @override
  Future<void> refresh({
    String? readPathOverride,
    String? outputPathOverride,
  }) async {}
}

/// Στήνει τον host, ανοίγει τον διάλογο και τον αφήνει σταθερό.
Future<void> _openLampSettingsDialog(
  WidgetTester tester,
  LampSettingsDialogController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lampExcelPathHealthProvider.overrideWith(_StubExcelPathHealth.new),
        lampDbComparisonProvider.overrideWith(_StubDbComparison.new),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    openLampSettingsDialog(
                      context: context,
                      controller: controller,
                      registerDialogSetState: (_) {},
                      onDialogClosed: () {},
                    );
                  },
                  child: const Text('Άνοιγμα'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Άνοιγμα'));
  await tester.pumpAndSettle();
}

void main() {
  group('LampSettingsDialog layout', () {
    late _StubPath path;
    late _StubSearch search;
    late LampSettingsDialogController controller;

    setUp(() {
      path = _StubPath();
      search = _StubSearch(path);
      controller = LampSettingsDialogController(
        path: path,
        search: search,
        importController: _StubImport(path),
        integrityController: _StubIntegrity(path),
        getReadPathCheck: () => null,
        getOutputPathCheck: () =>
            const LampOldDbCheckResult(LampOldDbStatus.outputPendingCreation),
        getDialogFeedback: () => null,
        getDialogFeedbackIsError: () => false,
        onClearDialogFeedback: () {},
        onCopyDialogFeedback: (_) async {},
        onPickExcel: () async {},
        onPickReadDatabase: () async {},
        onPickDatabaseOutput: () async {},
        onMatchReadToOutput: () async {},
        onRunIntegrityCheck: () async {},
        onRunImport: () async {},
        onClose: (_) async {},
        isImporting: () => false,
        isIntegrityChecking: () => false,
      );
    });

    tearDown(() {
      search.dispose();
      path.dispose();
    });

    testWidgets('shows new field labels and info tooltips', (tester) async {
      await _openLampSettingsDialog(tester, controller);

      expect(find.text('Αρχείο Excel (πηγή δεδομένων)'), findsOneWidget);
      expect(
        find.text('Βάση δεδομένων που δημιουργεί το Excel'),
        findsOneWidget,
      );
      expect(
        find.text('Βάση Δεδομένων που χρησιμοποιεί η Λάμπα'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.info_outline), findsWidgets);
      expect(
        find.byIcon(Icons.info_outline).evaluate().length,
        greaterThanOrEqualTo(3),
      );
    });

    testWidgets('removed legacy action buttons are absent', (tester) async {
      await _openLampSettingsDialog(tester, controller);

      expect(find.text('Ίδιο με τη διαδρομή εξόδου'), findsNothing);
      expect(find.text('Έλεγχος & αποθήκευση διαδρομών'), findsNothing);
    });

    testWidgets('arrow button reflects disabled state with tooltip', (
      tester,
    ) async {
      path.outputDbController.text = '';
      path.readDbController.text = r'C:\read.db';

      await _openLampSettingsDialog(tester, controller);

      final arrowButtons = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == Icons.arrow_downward,
      );
      expect(arrowButtons, findsOneWidget);
      final iconButton = tester.widget<IconButton>(arrowButtons);
      expect(iconButton.onPressed, isNull);

      final tooltipFinder = find.ancestor(
        of: arrowButtons,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message == 'Η διαδρομή της βάσης εξόδου είναι κενή',
        ),
      );
      expect(tooltipFinder, findsOneWidget);
    });

    testWidgets('import button sits below output status panel', (tester) async {
      await _openLampSettingsDialog(tester, controller);

      final outputLabel = tester.getTopLeft(
        find.text('Βάση δεδομένων που δημιουργεί το Excel'),
      );
      final importButton = tester.getTopLeft(
        find.text('Δημιουργία βάσης από Excel'),
      );
      final readLabel = tester.getTopLeft(
        find.text('Βάση Δεδομένων που χρησιμοποιεί η Λάμπα'),
      );

      expect(importButton.dy, greaterThan(outputLabel.dy));
      expect(readLabel.dy, greaterThan(importButton.dy));
    });

    testWidgets('pending read check message mentions automatic validation', (
      tester,
    ) async {
      await _openLampSettingsDialog(tester, controller);

      expect(find.textContaining('γίνεται αυτόματα'), findsWidgets);
    });

    testWidgets('output db tooltip describes recreate not update', (
      tester,
    ) async {
      await _openLampSettingsDialog(tester, controller);

      final outputTooltip = find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.contains('θα διαγραφεί και θα ξαναδημιουργηθεί') ??
                false),
      );
      expect(outputTooltip, findsOneWidget);

      final updateTooltip = find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.contains('θα ενημερωθεί') ?? false),
      );
      expect(updateTooltip, findsNothing);
    });

    testWidgets('output path check shows recreate message when db is valid', (
      tester,
    ) async {
      final outputCheckController = LampSettingsDialogController(
        path: path,
        search: search,
        importController: _StubImport(path),
        integrityController: _StubIntegrity(path),
        getReadPathCheck: () => null,
        getOutputPathCheck: () =>
            const LampOldDbCheckResult(LampOldDbStatus.outputWillUpdate),
        getDialogFeedback: () => null,
        getDialogFeedbackIsError: () => false,
        onClearDialogFeedback: () {},
        onCopyDialogFeedback: (_) async {},
        onPickExcel: () async {},
        onPickReadDatabase: () async {},
        onPickDatabaseOutput: () async {},
        onMatchReadToOutput: () async {},
        onRunIntegrityCheck: () async {},
        onRunImport: () async {},
        onClose: (_) async {},
        isImporting: () => false,
        isIntegrityChecking: () => false,
      );

      await _openLampSettingsDialog(tester, outputCheckController);

      expect(
        find.textContaining('θα διαγραφεί και θα ξαναδημιουργηθεί'),
        findsOneWidget,
      );
    });
  });
}
