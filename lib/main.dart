import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'core/widgets/app_init_wrapper.dart';
import 'features/calls/screens/widgets/call_header_form.dart';

/// Ελάχιστο πλάτος: γραμμή πεδίων + padding Κλήσεων (16*2) + extended NavigationRail (~280) + περιθώριο.
const double _kCallsScreenPaddingH = 32;
const double _kNavigationRailExtendedWidth = 280;
const double _kMinWindowWidthMargin = 20;
final double _kMinWindowWidth =
    kCallHeaderRowMinWidth + _kCallsScreenPaddingH + _kNavigationRailExtendedWidth + _kMinWindowWidthMargin;
const double _kMinWindowHeight = 640;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
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
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Καταγραφή Κλήσεων v1.0',
      locale: const Locale('el'),
      supportedLocales: const [
        Locale('el', 'GR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        textTheme: GoogleFonts.interTextTheme(),
      ),
      home: const AppInitWrapper(),
    );
  }
}
