import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'core/database/database_init_result.dart';
import 'core/widgets/app_init_wrapper.dart';
import 'core/widgets/app_shell_with_global_fatal_error.dart';
import 'core/widgets/global_fatal_error_notifier.dart';
import 'features/calls/screens/widgets/call_header_form.dart';

/// Ελάχιστο πλάτος: γραμμή πεδίων + padding Κλήσεων (16*2) + extended NavigationRail (~280) + περιθώριο.
const double _kCallsScreenPaddingH = 32;
const double _kNavigationRailExtendedWidth = 280;
const double _kMinWindowWidthMargin = 20;

final double _kMinWindowWidth =
    kCallHeaderRowMinWidth +
    _kCallsScreenPaddingH +
    _kNavigationRailExtendedWidth +
    _kMinWindowWidthMargin;
const double _kMinWindowHeight = 640;

void _routeFatalErrorToUi(Object exception, StackTrace stack) {
  globalFatalErrorNotifier.value = DatabaseInitResult.fromException(
    exception,
    null,
    stack,
  );
}

bool _platformAsyncErrorHandler(Object error, StackTrace stack) {
  _routeFatalErrorToUi(error, stack);
  return true;
}

void _rootZoneErrorHandler(Object error, StackTrace stack) {
  _routeFatalErrorToUi(error, stack);
}

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      final st = details.stack ?? StackTrace.empty;
      _routeFatalErrorToUi(details.exception, st);
    };

    PlatformDispatcher.instance.onError = _platformAsyncErrorHandler;

    unawaited(_bootstrapAndRunApp());
  }, _rootZoneErrorHandler);
}

Future<void> _bootstrapAndRunApp() async {
  if (Platform.isWindows) {
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final wm = WindowManager.instance;
      await wm.ensureInitialized();
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
      title: 'Καταγραφή Κλήσεων v1.0',
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
