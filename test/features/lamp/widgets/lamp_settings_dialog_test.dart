import 'package:call_logger/core/database/old_database/lamp_old_db_validator.dart';
import 'package:call_logger/features/lamp/controllers/lamp_import_controller.dart';
import 'package:call_logger/features/lamp/controllers/lamp_integrity_controller.dart';
import 'package:call_logger/features/lamp/controllers/lamp_path_management.dart';
import 'package:call_logger/features/lamp/controllers/lamp_screen_host.dart';
import 'package:call_logger/features/lamp/controllers/lamp_search_controller.dart';
import 'package:call_logger/features/lamp/widgets/lamp_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubPath extends LampPathController {
  _StubPath()
      : super(
          host: _ThrowingHost(),
        );

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
      : super(
          host: _ThrowingHost(),
          path: path,
        );
}

class _StubImport extends LampImportController {
  _StubImport(LampPathController path)
      : super(host: _ThrowingHost(), path: path);
}

class _StubIntegrity extends LampIntegrityController {
  _StubIntegrity(LampPathController path)
      : super(host: _ThrowingHost(), path: path);
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
        getOutputPathCheck: () => const LampOldDbCheckResult(
          LampOldDbStatus.outputPendingCreation,
        ),
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
      await tester.pumpWidget(
        MaterialApp(
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
      );
      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();

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
      expect(find.byIcon(Icons.info_outline).evaluate().length, greaterThanOrEqualTo(3));
    });

    testWidgets('removed legacy action buttons are absent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
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
      );
      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();

      expect(find.text('Ίδιο με τη διαδρομή εξόδου'), findsNothing);
      expect(find.text('Έλεγχος & αποθήκευση διαδρομών'), findsNothing);
    });

    testWidgets('arrow button reflects disabled state with tooltip', (tester) async {
      path.outputDbController.text = '';
      path.readDbController.text = r'C:\read.db';

      await tester.pumpWidget(
        MaterialApp(
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
      );
      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();

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
              widget.message ==
                  'Η διαδρομή της βάσης εξόδου είναι κενή',
        ),
      );
      expect(tooltipFinder, findsOneWidget);
    });

    testWidgets('import button sits below output status panel', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
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
      );
      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();

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

    testWidgets('pending read check message mentions automatic validation',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
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
      );
      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('γίνεται αυτόματα'),
        findsWidgets,
      );
    });

    testWidgets('output db tooltip describes recreate not update', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
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
      );
      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();

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

    testWidgets('output path check shows recreate message when db is valid',
        (tester) async {
      final outputCheckController = LampSettingsDialogController(
        path: path,
        search: search,
        importController: _StubImport(path),
        integrityController: _StubIntegrity(path),
        getReadPathCheck: () => null,
        getOutputPathCheck: () => const LampOldDbCheckResult(
          LampOldDbStatus.outputWillUpdate,
        ),
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

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      openLampSettingsDialog(
                        context: context,
                        controller: outputCheckController,
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
      );
      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('θα διαγραφεί και θα ξαναδημιουργηθεί'),
        findsOneWidget,
      );
    });
  });
}
