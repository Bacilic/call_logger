import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'core/widgets/app_init_wrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final wm = WindowManager.instance;
    await wm.ensureInitialized();
    await wm.waitUntilReadyToShow(null, () async {
      await wm.show();
    });
    final display = await ScreenRetriever.instance.getPrimaryDisplay();
    final screenWidth = display.size.width;
    final bounds = await wm.getBounds();
    if (bounds.width > screenWidth) {
      await wm.setSize(Size(screenWidth, bounds.height));
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
        Locale('el'),
        Locale('en'),
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
