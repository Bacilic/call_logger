/// Re-export sqflite τύπων για callers εκτός `core/database/` χωρίς άμεσο package import.
library;

export 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show Database, DatabaseExecutor, Transaction, openDatabase;
