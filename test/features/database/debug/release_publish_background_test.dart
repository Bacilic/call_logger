// Δημοσίευση έκδοσης — συμβόλαιο: «η δημοσίευση ανήκει στην εφαρμογή, όχι στην
// οθόνη: μία το πολύ εκτέλεση κάθε στιγμή, ορατή από παντού, με φινάλε που
// βρίσκει τον χρήστη όπου κι αν είναι».
//
// Το σενάριο-σπόρος: ο χρήστης πατά «Δημοσίευση», φεύγει από τα Σενάρια
// σφαλμάτων όσο το build τρέχει, και επιστρέφει. Χωρίς κατάσταση με ζωή
// εφαρμογής, η οθόνη ξαναχτίζεται «καθαρή»: τα κουμπιά είναι ξανά ενεργά και
// μπορεί να ξεκινήσει ΔΕΥΤΕΡΗ δημοσίευση παράλληλα με την πρώτη — δύο
// διεργασίες γράφουν ταυτόχρονα pubspec, changelog και φάκελο ενημερώσεων.
//
//   flutter test test/features/database/debug/release_publish_background_test.dart

import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/about/providers/app_version_provider.dart';
import 'package:call_logger/core/providers/main_nav_request_provider.dart';
import 'package:call_logger/core/updates/network_folder_classifier.dart';
import 'package:call_logger/core/widgets/main_nav_destination.dart';
import 'package:call_logger/features/database/debug/release_publish_finished_snackbar.dart';
import 'package:call_logger/features/database/debug/release_publish_run_provider.dart';
import 'package:call_logger/features/database/debug/release_publisher_card.dart';
import 'package:call_logger/features/database/debug/release_publisher_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory projectRoot;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('release_bg_');
    projectRoot = Directory(p.join(tempDir.path, 'project'));
    await Directory(p.join(projectRoot.path, 'assets')).create(recursive: true);
    SharedPreferences.setMockInitialValues({
      'update_folder_path': tempDir.path,
    });
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget appHost(ProviderContainer container, {required bool showCard,
      required ReleasePublisherService Function({
        required String updateFolderPath,
        void Function(String message)? onProgress,
      }) serviceFactory}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: showCard
              ? SingleChildScrollView(
                  child: ReleasePublisherCard(
                    networkFolderClassifier: _FixedKindClassifier(
                      NetworkFolderKind.unknown,
                    ),
                    networkClassifyDebounce: Duration.zero,
                    serviceFactory: serviceFactory,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  testWidgets(
    'φεύγοντας και επιστρέφοντας μεσούσης εκτέλεσης δεν επιτρέπεται δεύτερη',
    (tester) async {
      final container = ProviderContainer(
        overrides: [appVersionProvider.overrideWith((ref) async => '0.23.1')],
      );
      addTearDown(container.dispose);

      final gate = Completer<ReleasePublishResult>();
      var installerCalls = 0;
      ReleasePublisherService factory({
        required String updateFolderPath,
        void Function(String message)? onProgress,
      }) {
        return _GatedPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onWriteInstaller: () => installerCalls++,
          writeInstallerResult: () => gate.future,
        );
      }

      await tester.pumpWidget(
        appHost(container, showCard: true, serviceFactory: factory),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('release_update_folder_field')),
        tempDir.path,
      );
      await tester.pumpAndSettle();

      // Εκκίνηση αργής ενέργειας.
      await tester.tap(find.byKey(const Key('release_installer_only_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(installerCalls, 1);

      // Ο χρήστης φεύγει από την οθόνη — η κάρτα καταστρέφεται.
      await tester.pumpWidget(
        appHost(container, showCard: false, serviceFactory: factory),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // ...και επιστρέφει όσο η εκτέλεση ακόμη τρέχει.
      await tester.pumpWidget(
        appHost(container, showCard: true, serviceFactory: factory),
      );
      // Όχι pumpAndSettle: όσο τρέχει η εκτέλεση το χρονόμετρο ανανεώνεται.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final installerButton = tester.widget<OutlinedButton>(
        find.byKey(const Key('release_installer_only_button')),
      );
      expect(
        installerButton.onPressed,
        isNull,
        reason: greekExpectMsg(
          'Η εκτέλεση ακόμη τρέχει: ενεργό κουμπί σημαίνει ότι ο χρήστης '
          'μπορεί να ξεκινήσει δεύτερη δημοσίευση παράλληλα με την πρώτη',
        ),
      );
      final publishButton = tester.widget<FilledButton>(
        find.byKey(const Key('release_publish_button')),
      );
      expect(publishButton.onPressed, isNull);

      // Και το χρονόμετρο/ένδειξη εκτέλεσης είναι ορατά — η οθόνη «θυμάται».
      expect(find.byKey(const Key('release_elapsed_timer')), findsOneWidget);

      gate.complete(
        const ReleasePublishResult(
          status: ReleasePublishStatus.success,
          message: 'Ο εγκαταστάτης γράφτηκε.',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(installerCalls, 1);
    },
  );

  testWidgets('η επιστροφή μετά το φινάλε δείχνει το αποτέλεσμα στην κάρτα', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [appVersionProvider.overrideWith((ref) async => '0.23.1')],
    );
    addTearDown(container.dispose);

    final gate = Completer<ReleasePublishResult>();
    ReleasePublisherService factory({
      required String updateFolderPath,
      void Function(String message)? onProgress,
    }) {
      return _GatedPublisherService(
        projectRoot: projectRoot.path,
        updateFolderPath: updateFolderPath,
        onWriteInstaller: () {},
        writeInstallerResult: () => gate.future,
      );
    }

    await tester.pumpWidget(
      appHost(container, showCard: true, serviceFactory: factory),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_installer_only_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Φεύγει· η εκτέλεση ολοκληρώνεται όσο λείπει.
    await tester.pumpWidget(
      appHost(container, showCard: false, serviceFactory: factory),
    );
    gate.complete(
      const ReleasePublishResult(
        status: ReleasePublishStatus.success,
        message: 'Ο εγκαταστάτης γράφτηκε.',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Επιστρέφει: το αποτέλεσμα της εκτέλεσης δεν χάθηκε.
    await tester.pumpWidget(
      appHost(container, showCard: true, serviceFactory: factory),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Ο εγκαταστάτης γράφτηκε.'),
      findsOneWidget,
      reason: greekExpectMsg(
        'Το φινάλε που ήρθε όσο ο χρήστης έλειπε πρέπει να τον περιμένει '
        'στην κάρτα — αλλιώς δεν μαθαίνει ποτέ αν πέτυχε ή απέτυχε',
      ),
    );
  });

  group('snackbar φινάλε εκτός οθόνης', () {
    Future<ProviderContainer> pumpProbe(
      WidgetTester tester, {
      required bool publisherVisible,
    }) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: _SnackbarProbe(publisherVisible: publisherVisible),
          ),
        ),
      );
      return container;
    }

    Future<void> finishRun(
      ProviderContainer container, {
      required ReleasePublishResult result,
    }) async {
      final ok = await container
          .read(releasePublishRunProvider.notifier)
          .run(() async => result);
      expect(ok, isTrue);
    }

    testWidgets('εμφανίζεται με «Μετάβαση» και «Κλείσιμο»· η Μετάβαση πλοηγεί', (
      tester,
    ) async {
      final container = await pumpProbe(tester, publisherVisible: false);
      await finishRun(
        container,
        result: const ReleasePublishResult(
          status: ReleasePublishStatus.success,
          message: 'Δημοσιεύτηκε η έκδοση 0.23.2.',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const Key('release_publish_finished_snackbar')),
        findsOneWidget,
      );
      expect(find.textContaining('Δημοσιεύτηκε η έκδοση 0.23.2.'), findsOneWidget);
      expect(find.text('Μετάβαση'), findsOneWidget);
      expect(find.text('Κλείσιμο'), findsOneWidget);

      await tester.tap(find.byKey(const Key('release_publish_snackbar_go')));
      await tester.pumpAndSettle();

      expect(
        container.read(mainNavRequestProvider)?.destination,
        MainNavDestination.debugScenarios,
        reason: greekExpectMsg(
          'Η «Μετάβαση» πρέπει να ζητά πλοήγηση στα Σενάρια σφαλμάτων',
        ),
      );
      expect(
        find.byKey(const Key('release_publish_finished_snackbar')),
        findsNothing,
      );
    });

    testWidgets('το «Κλείσιμο» κλείνει χωρίς πλοήγηση', (tester) async {
      final container = await pumpProbe(tester, publisherVisible: false);
      await finishRun(
        container,
        result: const ReleasePublishResult(
          status: ReleasePublishStatus.failure,
          failedStep: 'flutter build',
          message: 'Κάτι πήγε στραβά.',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Αποτυχία στο βήμα'), findsOneWidget);

      await tester.tap(find.byKey(const Key('release_publish_snackbar_close')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('release_publish_finished_snackbar')),
        findsNothing,
      );
      expect(container.read(mainNavRequestProvider), isNull);
    });

    testWidgets('με ορατή την οθόνη δημοσίευσης ΔΕΝ εμφανίζεται', (
      tester,
    ) async {
      final container = await pumpProbe(tester, publisherVisible: true);
      await finishRun(
        container,
        result: const ReleasePublishResult(
          status: ReleasePublishStatus.success,
          message: 'Δημοσιεύτηκε.',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const Key('release_publish_finished_snackbar')),
        findsNothing,
        reason: greekExpectMsg(
          'Η κάρτα δείχνει ήδη το αποτέλεσμα — διπλή αγγελία είναι θόρυβος',
        ),
      );
    });
  });

  test('εξαίρεση στην ενέργεια δεν αφήνει το κλείδωμα κολλημένο', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(releasePublishRunProvider.notifier);

    final ok = await notifier.run(() async => throw StateError('έσκασε'));

    expect(ok, isTrue);
    final state = container.read(releasePublishRunProvider);
    expect(
      state.running,
      isFalse,
      reason: greekExpectMsg(
        'Αν το running μείνει true, τα κουμπιά κλειδώνουν για πάντα',
      ),
    );
    expect(state.completion!.isFailure, isTrue);
    expect(state.completion!.statusMessage, contains('έσκασε'));
  });
}

/// Μίνι-κέλυφος: καλεί τον ίδιο listener που καλεί το MainShell.
class _SnackbarProbe extends ConsumerWidget {
  const _SnackbarProbe({required this.publisherVisible});

  final bool publisherVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForReleasePublishFinishedSnackBar(
      ref,
      context,
      isPublisherScreenVisible: () => publisherVisible,
    );
    return const Scaffold(body: SizedBox.shrink());
  }
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

class _GatedPublisherService extends ReleasePublisherService {
  _GatedPublisherService({
    required super.projectRoot,
    required super.updateFolderPath,
    required this.onWriteInstaller,
    required this.writeInstallerResult,
  }) : super(
         buildReleaseDirectory: p.join(projectRoot, 'build'),
         processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
         clock: () => DateTime(2026, 8, 8),
       );

  final void Function() onWriteInstaller;
  final Future<ReleasePublishResult> Function() writeInstallerResult;

  @override
  Future<ReleasePublishPreview> preparePreview() async =>
      const ReleasePublishPreview(
        currentVersion: '0.23.1',
        currentBuild: 31,
        nextVersion: '0.23.2',
        nextBuild: 32,
        unreleasedEntryCount: 1,
        hasUnreleasedEntries: true,
        bumpKind: VersionBumpKind.patch,
      );

  @override
  Future<ReleasePublishResult> writeInstallerOnly() {
    onWriteInstaller();
    return writeInstallerResult();
  }
}
