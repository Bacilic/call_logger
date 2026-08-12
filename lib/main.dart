import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'core/about/version_display.dart';
import 'core/config/app_config.dart';
import 'core/init/startup_engine_failure.dart';
import 'core/init/startup_journal.dart';
import 'core/init/startup_notices.dart';
import 'core/init/startup_window_placement.dart';
import 'core/updates/update_providers.dart';
import 'core/utils/windows_cli_error_dialog.dart';
import 'core/services/app_close_controller.dart';
import 'core/services/crash_log_service.dart';
import 'core/services/settings_service.dart';
import 'core/errors/app_error_result.dart';
import 'core/errors/nonfatal_font_error_classifier.dart';
import 'core/widgets/crash_restart_notice.dart';
import 'core/widgets/app_init_wrapper.dart';
import 'core/widgets/app_shell_with_global_fatal_error.dart';
import 'core/widgets/global_fatal_error_notifier.dart';

void _routeFatalErrorToUi(Object exception, StackTrace stack) {
  final result = AppErrorResult.fromException(exception, stack);
  final phase = WidgetsBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.persistentCallbacks ||
      phase == SchedulerPhase.midFrameMicrotasks) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      globalFatalErrorNotifier.value = result;
    });
    return;
  }
  globalFatalErrorNotifier.value = result;
}

bool _isNonFatalUiLayoutErrorMessage(String message) {
  final lower = message.toLowerCase();
  return lower.contains('overflowed') ||
      lower.contains('renderflex') ||
      lower.contains('renderbox');
}

bool _isIgnorableHardwareKeyboardAssertion(Object exception) {
  final msg = exception.toString();
  return msg.contains('hardware_keyboard.dart') &&
      msg.contains('A KeyDownEvent is dispatched') &&
      msg.contains('!_pressedKeys.containsKey(event.physicalKey)');
}

/// True αν το σφάλμα δεν πρέπει να εμφανιστεί ως «κατάρρευση» εφαρμογής / βάσης.
bool _isNonFatalFrameworkNoise(Object error) {
  return _isIgnorableHardwareKeyboardAssertion(error);
}

bool _platformAsyncErrorHandler(Object error, StackTrace stack) {
  if (_isNonFatalFrameworkNoise(error)) {
    if (kDebugMode) {
      debugPrint(
        'Αγνοήθηκε γνωστό desync πληκτρολογίου Flutter/Windows (όχι σφάλμα εφαρμογής).',
      );
    }
    return true;
  }
  if (isNonFatalFontLoadError(error, stack)) {
    CrashLogService.instanceOrNull?.logError(error, stack, fatal: false);
    return true;
  }
  CrashLogService.instanceOrNull?.logError(error, stack, fatal: true);
  _routeFatalErrorToUi(error, stack);
  return true;
}

void _rootZoneErrorHandler(Object error, StackTrace stack) {
  if (isNonFatalFontLoadError(error, stack)) {
    CrashLogService.instanceOrNull?.logError(error, stack, fatal: false);
    return;
  }
  if (!_isNonFatalFrameworkNoise(error)) {
    CrashLogService.instanceOrNull?.logError(error, stack, fatal: true);
  }
  _routeFatalErrorToUi(error, stack);
}

Future<void> main(List<String> arguments) async {
  final journal = StartupJournal.instance;

  final cliStep = journal.begin('Έλεγχος ορισμάτων εκκίνησης');
  final cliValidation = AppConfig.validateCliArguments(arguments);
  if (!cliValidation.isValid) {
    cliStep.fail(cliValidation.buildErrorMessage());
    showWindowsCliErrorDialog(cliValidation.buildErrorMessage());
    exit(1);
  }
  cliStep.ok();

  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Το debug build απομονώνεται αυτόματα στο προφίλ «dev»: τρέχει από τον
      // επεξεργαστή κώδικα, όπου δεν υπάρχει συντόμευση για να περαστεί όρισμα.
      final profileStep = journal.begin('Επιλογή προφίλ δεδομένων');
      await AppConfig.configureFromCliArguments(
        arguments,
        defaultProfileWhenAbsent: kDebugMode
            ? AppConfig.debugDefaultProfileName
            : null,
      );
      profileStep.ok();

      // Εκκρεμής ενημέρωση: αν υπάρχει έτοιμο πακέτο από προηγούμενη «Αναμονή»,
      // εφάρμοσέ το τώρα (εκκίνηση updater + κλείσιμο) πριν φορτώσει η εφαρμογή.
      final pendingStep = journal.begin('Έλεγχος εκκρεμούς ενημέρωσης');
      if (await maybeApplyPendingUpdateOnStartup()) {
        pendingStep.ok('Εφαρμογή εκκρεμούς ενημέρωσης');
        return; // η εφαρμογή κλείνει· ο updater θα την ξανανοίξει.
      }
      pendingStep.skip();

      FlutterError.onError = (FlutterErrorDetails details) {
        final st = details.stack ?? StackTrace.empty;
        if (_isIgnorableHardwareKeyboardAssertion(details.exception)) {
          // Δεν καλούμε presentError: αποφεύγει πλημμύρα στην κονσόλα· γνωστό ζήτημα
          // Flutter + Windows (π.χ. ελληνικό layout / IME). Δες flutter/flutter #141091.
          if (kDebugMode) {
            debugPrint(
              'HardwareKeyboard assertion (αγνοήθηκε): ${details.exceptionAsString()}',
            );
          }
          return;
        }
        if (kReleaseMode &&
            _isNonFatalUiLayoutErrorMessage(details.exceptionAsString())) {
          debugPrint(
            'UI layout error (αγνοήθηκε σε release): ${details.exceptionAsString()}',
          );
          return;
        }
        if (isNonFatalFontLoadError(details.exception, st)) {
          CrashLogService.instanceOrNull?.logError(
            details.exception,
            st,
            fatal: false,
          );
          return;
        }
        CrashLogService.instanceOrNull?.logError(
          details.exception,
          st,
          fatal: false,
        );
        _routeFatalErrorToUi(details.exception, st);
      };

      PlatformDispatcher.instance.onError = _platformAsyncErrorHandler;

      await _bootstrapAndRunApp();
    },
    _rootZoneErrorHandler,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        // Το sqflite_common τυπώνει κάθε αποτυχία openDatabase· η οθόνα σφάλματος
        // ήδη ενημερώνει τον χρήστη — αποφεύγουμε θόρυβο στην Debug Console.
        if (line.startsWith('error ') &&
            line.endsWith(' during open, closing...')) {
          return;
        }
        parent.print(zone, line);
      },
    ),
  );
}

Future<void> _bootstrapAndRunApp() async {
  final journal = StartupJournal.instance;
  String appVersion = 'unknown';
  if (Platform.isWindows) {
    final engineStep = journal.begin('Φόρτωση μηχανής SQLite');
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      engineStep.ok();
    } catch (e, st) {
      // Δεν σταματά εδώ: ο έλεγχος βάσης δίνει πολύ καλύτερο μήνυμα από
      // «databaseFactory not initialized». Η γραμμή μένει ως προειδοποίηση.
      engineStep.warn(e.toString());
      recordStartupEngineFailure(e, st);
    }

    final windowStep = journal.begin('Προετοιμασία παραθύρου');
    try {
      final wm = WindowManager.instance;
      await wm.ensureInitialized();
      // Η ευθύνη κλεισίματος ανήκει στη διεργασία, όχι σε widget: εγκαθίσταται
      // μία φορά εδώ ώστε το X/Alt+F4 να λειτουργεί σε ΟΠΟΙΑΔΗΠΟΤΕ οθόνη —
      // και στις οθόνες σφάλματος που αντικαθιστούν το κύριο κέλυφος.
      await appCloseController.install();
      try {
        if (AppConfig.hasActiveProfile) {
          await wm.setTitle(
            windowTitleWithProfileLabel(AppConfig.activeProfile!),
          );
        } else {
          final pkg = await PackageInfo.fromPlatform();
          appVersion = pkg.version;
          await wm.setTitle(windowTitleWithVersionLabel(pkg.version));
        }
      } catch (e, st) {
        recordStartupNotice('Τίτλος παραθύρου / έκδοση', e, st);
      }
      final display = await ScreenRetriever.instance.getPrimaryDisplay();
      // Φάση 1: η κάρτα της εκκίνησης. Το ελάχιστο μέγεθος και οι
      // αποθηκευμένες διαστάσεις μπαίνουν μόλις φύγει η οθόνη εκκίνησης —
      // δες StartupWindowPlacement.
      await StartupWindowPlacement.applySplashWindow(
        windowManager: wm,
        screenWidth: display.size.width,
        screenHeight: display.size.height,
      );
      await wm.waitUntilReadyToShow(null, () async {
        await wm.show();
      });
      windowStep.ok();
    } catch (e) {
      windowStep.warn(e.toString());
    }
  }

  final logStep = journal.begin('Άνοιγμα ημερολογίου καταρρεύσεων');
  try {
    if (appVersion == 'unknown') {
      final pkg = await PackageInfo.fromPlatform();
      appVersion = pkg.version;
    }
    final settings = SettingsService();
    // Το CrashLogService.onShutdown() ΔΕΝ καλείται πλέον από WindowListener εδώ
    // (ο παλιός _CrashLogShutdownListener αφαιρέθηκε επίτηδες). Καλείται τώρα ως
    // ένα από τα βήματα του ShutdownCoordinator («Κλείσιμο ημερολογίου
    // καταγραφής»), ώστε να μην εκτελείται δύο φορές και να έχει σωστή σειρά ως
    // προς το κλείσιμο της βάσης. Δες lib/core/services/shutdown_coordinator.dart.
    await CrashLogService.initialize(
      databasePath: await settings.getDatabasePath(),
      appVersion: appVersion,
      retentionCount: await settings.catalogs.getCrashLogRetentionCount(),
    );
    logStep.ok();
  } catch (e, st) {
    logStep.warn(e.toString());
    recordStartupNotice('Ημερολόγιο καταρρεύσεων', e, st);
  }

  flushStartupNoticesToCrashLog();

  // Ό,τι έγινε ως εδώ δεν ξανατρέχει — ούτε στην επαναδοκιμή, ούτε στην
  // εναλλαγή βάσης. Σφραγίζεται ώστε να επιβιώνει κάθε νέας προσπάθειας.
  journal.sealBootPrefix();

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.showStartupSplash = true});

  /// Αν θα προβληθεί η οθόνη εκκίνησης. Δες [AppInitWrapper.showStartupSplash].
  final bool showStartupSplash;

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.interTextTheme().apply(
      fontFamilyFallback: const ['Segoe UI'],
    );
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
    return MaterialApp(
      title: 'Καταγραφή Κλήσεων',
      locale: const Locale('el'),
      supportedLocales: const [Locale('el', 'GR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        colorScheme: colorScheme,
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        scaffoldBackgroundColor: colorScheme.surface,
        textTheme: textTheme,
        dataTableTheme: DataTableThemeData(
          headingRowHeight: 42,
          headingTextStyle: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ),
      home: CrashRestartNotice(
        child: AppShellWithGlobalFatalError(
          child: AppInitWrapper(showStartupSplash: showStartupSplash),
        ),
      ),
    );
  }
}
