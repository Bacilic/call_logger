// Εφαρμογή για μυνήματα τα ελληνικά γαι τα τεστ

import 'package:call_logger/core/widgets/app_init_wrapper.dart';
import 'package:call_logger/core/widgets/app_shell_with_global_fatal_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Ίδια δομή με [MyApp] χωρίς Google Fonts — το `flutter test` μπλοκάρει HTTP / επιστρέφει 400.
class CallLoggerTestMaterialApp extends StatelessWidget {
  const CallLoggerTestMaterialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Καταγραφή Κλήσεων (test)',
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
      ),
      home: const AppShellWithGlobalFatalError(child: AppInitWrapper()),
    );
  }
}
