import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import 'core/database/database_init_result.dart';
import 'core/widgets/app_init_wrapper.dart';
import 'core/widgets/app_shell_with_global_fatal_error.dart';
import 'core/widgets/global_fatal_error_notifier.dart';
import 'features/calls/screens/widgets/call_header_form.dart';

/// Ελάχιστο πλάτος: γραμμή πεδίων + padding Κλήσεων (16*2) + συμπυγμένο NavigationRail + περιθώριο.
const double _kCallsScreenPaddingH = 32;
const double _kNavigationRailMinWidth = 80;
const double _kMinWindowWidthMargin = 20;

final double _kMinWindowWidth =
    kCallHeaderRowMinWidth +
    _kCallsScreenPaddingH +
    _kNavigationRailMinWidth +
    _kMinWindowWidthMargin;
const double _kMinWindowHeight = 640;

void _routeFatalErrorToUi(Object exception, StackTrace stack) {
  final result = DatabaseInitResult.fromException(exception, null, stack);
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
  _routeFatalErrorToUi(error, stack);
  return true;
}

void _rootZoneErrorHandler(Object error, StackTrace stack) {
  _routeFatalErrorToUi(error, stack);
}

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

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
        _routeFatalErrorToUi(details.exception, st);
      };

      PlatformDispatcher.instance.onError = _platformAsyncErrorHandler;

      unawaited(_bootstrapAndRunApp());
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
  if (Platform.isWindows) {
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final wm = WindowManager.instance;
      await wm.ensureInitialized();
      try {
        final pkg = await PackageInfo.fromPlatform();
        await wm.setTitle(windowTitleWithVersionLabel(pkg.version));
      } catch (_) {}
      final display = await ScreenRetriever.instance.getPrimaryDisplay();
      final screenWidth = display.size.width;
      final screenHeight = display.size.height;
      final minW = math.min(_kMinWindowWidth, screenWidth);
      final minH = math.min(_kMinWindowHeight, screenHeight);
      await wm.setMinimumSize(Size(minW, minH));
      await wm.waitUntilReadyToShow(null, () async {
        await wm.show();
      });
      final bounds = await wm.getBounds();
      var newW = math.min(screenWidth, math.max(bounds.width, minW));
      var newH = math.min(screenHeight, math.max(bounds.height, minH));
      if ((newW - bounds.width).abs() > 0.5 ||
          (newH - bounds.height).abs() > 0.5) {
        await wm.setSize(Size(newW, newH));
      }
      await wm.center();
    } catch (_) {}
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.interTextTheme();
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        textTheme: textTheme,
        dataTableTheme: DataTableThemeData(
          headingRowHeight: 42,
          headingTextStyle: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ),
      home: const AppShellWithGlobalFatalError(child: AppInitWrapper()),
    );
  }
}
