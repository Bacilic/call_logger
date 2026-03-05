import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/database/database_helper.dart';
import 'core/services/settings_service.dart';
import 'core/widgets/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  String dbPath = await SettingsService().getDatabasePath();
  bool databaseInitSuccess = false;
  bool isLocalDevMode = false;

  try {
    await DatabaseHelper.instance.database;
    isLocalDevMode = DatabaseHelper.instance.isUsingLocalDb;
    dbPath = isLocalDevMode
        ? 'Data Base/call_logger.db (τοπική)'
        : (dbPath.isEmpty ? 'default' : dbPath);
    // ignore: avoid_print
    print('Η βάση δεδομένων αρχικοποιήθηκε στη διαδρομή: $dbPath');
    databaseInitSuccess = true;
  } catch (e, st) {
    // ignore: avoid_print
    print('Σφάλμα αρχικοποίησης βάσης: $e');
    // ignore: avoid_print
    print(st);
  }

  runApp(ProviderScope(
    child: MyApp(
      databaseInitSuccess: databaseInitSuccess,
      isLocalDevMode: isLocalDevMode,
    ),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.databaseInitSuccess,
    required this.isLocalDevMode,
  });

  final bool databaseInitSuccess;
  final bool isLocalDevMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Καταγραφή Κλήσεων v1.0',
      theme: ThemeData(
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        textTheme: GoogleFonts.interTextTheme(),
      ),
      home: MainShell(
        databaseInitSuccess: databaseInitSuccess,
        isLocalDevMode: isLocalDevMode,
      ),
    );
  }
}
