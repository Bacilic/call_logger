import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum LampDatabaseMode { read, write }

/// Διαχειρίζεται αποκλειστικά τη σύνδεση της βάσης «Λάμπα».
class LampDatabaseProvider {
  LampDatabaseProvider._();

  static final LampDatabaseProvider instance = LampDatabaseProvider._();

  Database? _database;
  String? _path;
  LampDatabaseMode? _mode;

  Future<Database> open(
    String path, {
    LampDatabaseMode mode = LampDatabaseMode.read,
  }) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      throw ArgumentError('Δεν έχει οριστεί διαδρομή βάσης Λάμπα.');
    }

    if (_database != null &&
        _database!.isOpen &&
        _path == normalizedPath &&
        _mode == mode) {
      return _database!;
    }

    await close();

    if (!await File(normalizedPath).exists()) {
      throw FileSystemException(
        'Δεν βρέθηκε το αρχείο βάσης Λάμπα.',
        normalizedPath,
      );
    }

    _database = await openDatabase(
      normalizedPath,
      readOnly: mode == LampDatabaseMode.read,
      singleInstance: false,
    );
    _path = normalizedPath;
    _mode = mode;
    return _database!;
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    _path = null;
    _mode = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
