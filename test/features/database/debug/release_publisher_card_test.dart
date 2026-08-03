import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/about/providers/app_version_provider.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/core/updates/network_folder_classifier.dart';
import 'package:call_logger/core/widgets/draggable_dialog_shell.dart';
import 'package:call_logger/features/database/debug/publish_cli.dart';
import 'package:call_logger/features/database/debug/release_publisher_card.dart';
import 'package:call_logger/features/database/debug/release_publisher_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory projectRoot;
  String? clipboardText;

  NetworkFolderClassifier fixedKind(NetworkFolderKind kind) {
    return _FixedKindClassifier(kind);
  }

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final args = call.arguments as Map<Object?, Object?>;
              clipboardText = args['text'] as String?;
              return null;
            case 'Clipboard.getData':
              if (clipboardText == null) return null;
              return <String, Object?>{'text': clipboardText};
          }
          return null;
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    clipboardText = null;
    tempDir = await Directory.systemTemp.createTemp('release_card_');
    projectRoot = Directory(p.join(tempDir.path, 'project'));
    await Directory(p.join(projectRoot.path, 'assets')).create(recursive: true);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    String? initialFolder,
    String currentVersion = '0.23.1',
    NetworkFolderClassifier? networkFolderClassifier,
    ReleasePublisherService Function({
      required String updateFolderPath,
      void Function(String message)? onProgress,
    })?
    serviceFactory,
  }) async {
    if (initialFolder != null) {
      SharedPreferences.setMockInitialValues({
        'update_folder_path': initialFolder,
      });
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => currentVersion),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReleasePublisherCard(
                networkFolderClassifier:
                    networkFolderClassifier ??
                    fixedKind(NetworkFolderKind.unknown),
                networkClassifyDebounce: Duration.zero,
                serviceFactory: serviceFactory,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FilledButton findPublishButton(WidgetTester tester) {
    return tester.widget<FilledButton>(
      find.byKey(const Key('release_publish_button')),
    );
  }

  Finder tooltipContaining(String text) => find.byWidgetPredicate(
    (w) => w is Tooltip && (w.message ?? '').contains(text),
  );

  testWidgets('empty folder disables publish with tooltip', (tester) async {
    await pumpCard(tester);

    expect(findPublishButton(tester).onPressed, isNull);
    expect(
      tooltipContaining('Ορίστε έγκυρο εγγράψιμο φάκελο ενημερώσεων'),
      findsNWidgets(2),
    );
  });

  testWidgets('invalid folder disables publish with tooltip', (tester) async {
    await pumpCard(tester);

    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      r'C:\this\path\almost\certainly\does\not\exist_xyz_12345',
    );
    await tester.pumpAndSettle();

    expect(findPublishButton(tester).onPressed, isNull);
    expect(
      tooltipContaining('Ορίστε έγκυρο εγγράψιμο φάκελο ενημερώσεων'),
      findsNWidgets(2),
    );
  });

  // Τα δύο κουμπιά κάνουν πολύ διαφορετικά πράγματα: το ένα χτίζει ολόκληρη
  // την εφαρμογή, το άλλο γράφει ένα αρχείο. Η υπόδειξη πρέπει να το λέει
  // ΠΑΝΤΑ, όχι μόνο όταν το κουμπί είναι ανενεργό.
  testWidgets('κάθε κουμπί εξηγεί τι κάνει, και όταν είναι ενεργό', (
    tester,
  ) async {
    await pumpCard(tester, initialFolder: tempDir.path);
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    expect(findPublishButton(tester).onPressed, isNotNull);

    expect(tooltipContaining('χτίζει την εφαρμογή από την αρχή'), findsOneWidget);
    expect(
      tooltipContaining('Γράφει ΜΟΝΟ το αρχείο εγκατάστασης'),
      findsOneWidget,
    );
    expect(
      tooltipContaining('Ορίστε έγκυρο εγγράψιμο φάκελο'),
      findsNothing,
      reason: greekExpectMsg(
        'Με έγκυρο φάκελο η αιτία απενεργοποίησης δεν έχει νόημα',
      ),
    );
  });

  testWidgets('valid writable folder enables publish', (tester) async {
    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      networkFolderClassifier: fixedKind(NetworkFolderKind.unknown),
    );

    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    expect(findPublishButton(tester).onPressed, isNotNull);
    expect(
      find.byTooltip('Ορίστε έγκυρο εγγράψιμο φάκελο ενημερώσεων'),
      findsNothing,
    );
  });

  testWidgets('localOnly warning visible only for localOnly', (tester) async {
    await pumpCard(
      tester,
      networkFolderClassifier: fixedKind(NetworkFolderKind.localOnly),
    );

    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('release_update_folder_local_only_warning')),
      findsOneWidget,
    );
    expect(find.textContaining('τοπική διαδρομή'), findsOneWidget);
  });

  testWidgets('no warning for networkUnc', (tester) async {
    await pumpCard(
      tester,
      networkFolderClassifier: fixedKind(NetworkFolderKind.networkUnc),
    );

    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('release_update_folder_local_only_warning')),
      findsNothing,
    );
  });

  testWidgets('no warning for localShared', (tester) async {
    await pumpCard(
      tester,
      networkFolderClassifier: fixedKind(NetworkFolderKind.localShared),
    );

    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('release_update_folder_local_only_warning')),
      findsNothing,
    );
  });

  testWidgets('no warning for unknown', (tester) async {
    await pumpCard(
      tester,
      networkFolderClassifier: fixedKind(NetworkFolderKind.unknown),
    );

    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('release_update_folder_local_only_warning')),
      findsNothing,
    );
  });

  testWidgets(
    'publish with entries shows confirm dialog with version transition',
    (tester) async {
      var publishCalls = 0;

      await pumpCard(
        tester,
        initialFolder: tempDir.path,
        serviceFactory: ({required updateFolderPath, onProgress}) {
          return _TrackingPublisherService(
            projectRoot: projectRoot.path,
            updateFolderPath: updateFolderPath,
            onPublish: () => publishCalls++,
            preview: const ReleasePublishPreview(
              currentVersion: '0.23.1',
              currentBuild: 31,
              nextVersion: '0.23.2',
              nextBuild: 32,
              unreleasedEntryCount: 1,
              hasUnreleasedEntries: true,
              bumpKind: VersionBumpKind.patch,
            ),
          );
        },
      );
      await tester.enterText(
        find.byKey(const Key('release_update_folder_field')),
        tempDir.path,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('release_publish_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('release_confirm_dialog')), findsOneWidget);
      expect(find.textContaining('0.23.1+31 → 0.23.2+32'), findsOneWidget);
      expect(
        find.textContaining('Θα δημοσιευτεί ως patch → 0.23.2'),
        findsOneWidget,
      );
      expect(publishCalls, 0);

      await tester.tap(find.byKey(const Key('release_confirm_cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(publishCalls, 0);
    },
  );

  testWidgets('empty Unreleased shows warning; cancel does not publish', (
    tester,
  ) async {
    var publishCalls = 0;

    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      serviceFactory: ({required updateFolderPath, onProgress}) {
        return _TrackingPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onPublish: () => publishCalls++,
          preview: const ReleasePublishPreview(
            currentVersion: '0.23.1',
            currentBuild: 31,
            nextVersion: '0.23.2',
            nextBuild: 32,
            unreleasedEntryCount: 0,
            hasUnreleasedEntries: false,
            bumpKind: VersionBumpKind.patch,
          ),
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_publish_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const Key('release_empty_unreleased_dialog')),
      findsOneWidget,
    );
    expect(find.text('Δημοσίευση όπως είναι'), findsNothing);
    expect(find.byKey(const Key('release_empty_publish_anyway')), findsNothing);

    await tester.tap(find.byKey(const Key('release_empty_cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(publishCalls, 0);
  });

  // Ο χρήστης αποφασίζει για τη δημοσίευση κοιτάζοντας το ιστορικό από πίσω —
  // ένας καρφωμένος διάλογος τον υποχρεώνει να κλείσει και να ξανανοίξει.
  testWidgets('ο διάλογος «Κενό ιστορικό» μετακινείται από τον τίτλο', (
    tester,
  ) async {
    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      serviceFactory: ({required updateFolderPath, onProgress}) {
        return _TrackingPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onPublish: () {},
          preview: const ReleasePublishPreview(
            currentVersion: '0.23.1',
            currentBuild: 31,
            nextVersion: '0.23.2',
            nextBuild: 32,
            unreleasedEntryCount: 0,
            hasUnreleasedEntries: false,
            bumpKind: VersionBumpKind.patch,
          ),
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_publish_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final dialog = find.byKey(const Key('release_empty_unreleased_dialog'));
    expect(dialog, findsOneWidget);

    final before = tester.getTopLeft(dialog);
    await tester.drag(find.text('Κενό ιστορικό'), const Offset(40, 30));
    await tester.pump();
    final after = tester.getTopLeft(dialog);

    expect(
      after,
      isNot(before),
      reason: greekExpectMsg(
        'Το σύρσιμο του τίτλου πρέπει να μετακινεί τον διάλογο· χωρίς αυτό ο '
        'χρήστης δεν βλέπει τι κρύβεται από πίσω',
      ),
    );
  });

  testWidgets('ο διάλογος επιβεβαίωσης δημοσίευσης είναι επίσης μετακινήσιμος', (
    tester,
  ) async {
    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      serviceFactory: ({required updateFolderPath, onProgress}) {
        return _TrackingPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onPublish: () {},
          preview: const ReleasePublishPreview(
            currentVersion: '0.23.1',
            currentBuild: 31,
            nextVersion: '0.23.2',
            nextBuild: 32,
            unreleasedEntryCount: 3,
            hasUnreleasedEntries: true,
            bumpKind: VersionBumpKind.patch,
          ),
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_publish_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('release_confirm_dialog')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DraggableDialogShell),
        matching: find.byKey(const Key('release_confirm_dialog')),
      ),
      findsOneWidget,
      reason: greekExpectMsg(
        'Όλοι οι διάλογοι της Δημοσίευσης ακολουθούν το ίδιο μοτίβο — ένας '
        'καρφωμένος ανάμεσα σε μετακινούμενους είναι ασυνέπεια',
      ),
    );

    await tester.tap(find.byKey(const Key('release_confirm_cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('empty Unreleased dialog includes installer-only option', (
    tester,
  ) async {
    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      serviceFactory: ({required updateFolderPath, onProgress}) {
        return _TrackingPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onPublish: () {},
          preview: const ReleasePublishPreview(
            currentVersion: '0.23.1',
            currentBuild: 31,
            nextVersion: '0.23.2',
            nextBuild: 32,
            unreleasedEntryCount: 0,
            hasUnreleasedEntries: false,
            bumpKind: VersionBumpKind.patch,
          ),
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_publish_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Μόνο εγκαταστάτης'), findsOneWidget);
    expect(
      find.byKey(const Key('release_empty_installer_only')),
      findsOneWidget,
    );
  });

  testWidgets('installer button calls writeInstallerOnly not publish', (
    tester,
  ) async {
    var publishCalls = 0;
    var installerCalls = 0;

    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      serviceFactory: ({required updateFolderPath, onProgress}) {
        return _TrackingPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onPublish: () => publishCalls++,
          onWriteInstaller: () => installerCalls++,
          preview: const ReleasePublishPreview(
            currentVersion: '0.23.1',
            currentBuild: 31,
            nextVersion: '0.23.2',
            nextBuild: 32,
            unreleasedEntryCount: 1,
            hasUnreleasedEntries: true,
            bumpKind: VersionBumpKind.patch,
          ),
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_installer_only_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(installerCalls, 1);
    expect(publishCalls, 0);
  });

  testWidgets(
    'while slow installer runs both buttons disabled and timer shows',
    (tester) async {
      final gate = Completer<ReleasePublishResult>();

      await pumpCard(
        tester,
        initialFolder: tempDir.path,
        serviceFactory: ({required updateFolderPath, onProgress}) {
          return _TrackingPublisherService(
            projectRoot: projectRoot.path,
            updateFolderPath: updateFolderPath,
            onPublish: () {},
            preview: const ReleasePublishPreview(
              currentVersion: '0.23.1',
              currentBuild: 31,
              nextVersion: '0.23.2',
              nextBuild: 32,
              unreleasedEntryCount: 1,
              hasUnreleasedEntries: true,
              bumpKind: VersionBumpKind.patch,
            ),
            writeInstallerResult: () => gate.future,
          );
        },
      );
      await tester.enterText(
        find.byKey(const Key('release_update_folder_field')),
        tempDir.path,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('release_installer_only_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(findPublishButton(tester).onPressed, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('release_installer_only_button')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('release_copy_cli_button')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('release_cli_settings_button')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('release_elapsed_timer')), findsOneWidget);
      expect(find.textContaining('Χρόνος:'), findsOneWidget);

      gate.complete(
        const ReleasePublishResult(status: ReleasePublishStatus.success),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    },
  );

  testWidgets('οι γραμμές εξόδου εμφανίζονται και ανανεώνονται σε νέα εκτέλεση', (
    tester,
  ) async {
    void Function(String message)? reportProgress;

    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      serviceFactory: ({required updateFolderPath, onProgress}) {
        reportProgress = onProgress;
        return _TrackingPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onPublish: () {},
          preview: const ReleasePublishPreview(
            currentVersion: '0.23.1',
            currentBuild: 31,
            nextVersion: '0.23.2',
            nextBuild: 32,
            unreleasedEntryCount: 1,
            hasUnreleasedEntries: true,
            bumpKind: VersionBumpKind.patch,
          ),
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_installer_only_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(reportProgress, isNotNull);
    reportProgress!('Πρώτο βήμα');
    reportProgress!('Δεύτερο βήμα');
    await tester.pump();

    expect(find.byKey(const Key('release_build_output')), findsOneWidget);
    expect(find.textContaining('Πρώτο βήμα'), findsOneWidget);
    expect(find.textContaining('Δεύτερο βήμα'), findsOneWidget);

    // Νέα εκτέλεση: η έξοδος της προηγούμενης δεν πρέπει να παραμένει.
    await tester.tap(find.byKey(const Key('release_installer_only_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.textContaining('Πρώτο βήμα'),
      findsNothing,
      reason: greekExpectMsg(
        'Ανάμεικτη έξοδος δύο εκτελέσεων θα έστελνε τον χρήστη να κυνηγά '
        'σφάλμα που δεν συνέβη τώρα',
      ),
    );
  });

  testWidgets('copy CLI button writes command to clipboard', (tester) async {
    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      serviceFactory: ({required updateFolderPath, onProgress}) {
        return _TrackingPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onPublish: () {},
          preview: const ReleasePublishPreview(
            currentVersion: '0.23.1',
            currentBuild: 31,
            nextVersion: '0.23.2',
            nextBuild: 32,
            unreleasedEntryCount: 1,
            hasUnreleasedEntries: true,
            bumpKind: VersionBumpKind.patch,
          ),
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_copy_cli_button')));
    await tester.pumpAndSettle();

    final expected = buildPublishCliCommand(
      kDefaultPublishCliCommandTemplate,
      VersionBumpKind.patch,
      tempDir.path,
    );
    expect(clipboardText, expected);
    expect(find.textContaining(expected), findsOneWidget);
  });

  testWidgets('copy CLI button uses auto-detected minor bump from preview', (
    tester,
  ) async {
    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      serviceFactory: ({required updateFolderPath, onProgress}) {
        return _TrackingPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onPublish: () {},
          preview: const ReleasePublishPreview(
            currentVersion: '0.23.1',
            currentBuild: 31,
            nextVersion: '0.24.0',
            nextBuild: 32,
            unreleasedEntryCount: 1,
            hasUnreleasedEntries: true,
            bumpKind: VersionBumpKind.minor,
          ),
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_copy_cli_button')));
    await tester.pumpAndSettle();

    expect(
      clipboardText,
      buildPublishCliCommand(
        kDefaultPublishCliCommandTemplate,
        VersionBumpKind.minor,
        tempDir.path,
      ),
    );
  });

  testWidgets('CLI settings dialog saves and restores default template', (
    tester,
  ) async {
    await pumpCard(tester, initialFolder: tempDir.path);
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_cli_settings_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('release_cli_settings_dialog')),
      findsOneWidget,
    );

    const custom =
        'dart run tool/publish.dart --bump={bump} --folder="{folder}" --allow-empty';
    await tester.enterText(
      find.byKey(const Key('release_cli_template_field')),
      custom,
    );
    await tester.tap(find.byKey(const Key('release_cli_save_button')));
    await tester.pumpAndSettle();

    expect(
      await SettingsService().catalogs.getPublishCliCommandTemplate(),
      custom,
    );

    await tester.tap(find.byKey(const Key('release_cli_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('release_cli_reset_default_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('release_cli_save_button')));
    await tester.pumpAndSettle();

    expect(
      await SettingsService().catalogs.getPublishCliCommandTemplate(),
      kDefaultPublishCliCommandTemplate,
    );
  });

  testWidgets(
    'CLI settings dialog shows parameter help including allow-empty',
    (tester) async {
      await pumpCard(tester, initialFolder: tempDir.path);
      await tester.enterText(
        find.byKey(const Key('release_update_folder_field')),
        tempDir.path,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('release_cli_settings_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('--allow-empty'), findsOneWidget);
      expect(find.textContaining('{bump}'), findsWidgets);
      expect(find.textContaining('{folder}'), findsWidgets);
    },
  );

  testWidgets('copy CLI disabled when folder invalid', (tester) async {
    await pumpCard(tester);

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('release_copy_cli_button')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('release_cli_settings_button')),
          )
          .onPressed,
      isNotNull,
    );
  });
}

class _FixedKindClassifier extends NetworkFolderClassifier {
  _FixedKindClassifier(this.kind)
    : super(
        driveTypeResolver: (_) async => false,
        localSharesProvider: () async => const <String>[],
        isWindows: () => true,
      );

  final NetworkFolderKind kind;

  @override
  Future<NetworkFolderKind> classify(String path) async => kind;
}

class _TrackingPublisherService extends ReleasePublisherService {
  _TrackingPublisherService({
    required super.projectRoot,
    required super.updateFolderPath,
    required this.onPublish,
    required this.preview,
    this.onWriteInstaller,
    this.writeInstallerResult,
  }) : super(
         buildReleaseDirectory: p.join(projectRoot, 'build'),
         processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
         clock: () => DateTime(2026, 7, 19),
       );

  final void Function() onPublish;
  final void Function()? onWriteInstaller;
  final ReleasePublishPreview preview;
  final Future<ReleasePublishResult> Function()? writeInstallerResult;

  @override
  Future<ReleasePublishPreview> preparePreview() async => preview;

  @override
  Future<ReleasePublishResult> publish() async {
    onPublish();
    return const ReleasePublishResult(status: ReleasePublishStatus.success);
  }

  @override
  Future<ReleasePublishResult> writeInstallerOnly() async {
    onWriteInstaller?.call();
    if (writeInstallerResult != null) {
      return writeInstallerResult!();
    }
    return const ReleasePublishResult(status: ReleasePublishStatus.success);
  }
}
