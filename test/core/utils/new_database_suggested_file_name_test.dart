import 'package:call_logger/core/utils/new_database_suggested_file_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final now = DateTime(2026, 7, 18, 19, 23, 45);
  const dir = r'C:\data';

  bool existsIn(Set<String> names, String absolutePath) {
    return names.contains(p.basename(absolutePath));
  }

  test('προτείνει call_logger_yyyy-MM-dd.db όταν δεν υπάρχει', () {
    final name = suggestNewCallLoggerDatabaseFileName(
      directory: dir,
      now: now,
      fileExists: (_) => false,
    );
    expect(name, 'call_logger_2026-07-18.db');
  });

  test('αν υπάρχει ημερομηνία, προσθέτει ώρα HH-mm', () {
    final name = suggestNewCallLoggerDatabaseFileName(
      directory: dir,
      now: now,
      fileExists: (path) => existsIn({'call_logger_2026-07-18.db'}, path),
    );
    expect(name, 'call_logger_2026-07-18_19-23.db');
  });

  test('αν υπάρχει και ώρα, προσθέτει δευτερόλεπτα', () {
    final name = suggestNewCallLoggerDatabaseFileName(
      directory: dir,
      now: now,
      fileExists: (path) => existsIn({
        'call_logger_2026-07-18.db',
        'call_logger_2026-07-18_19-23.db',
      }, path),
    );
    expect(name, 'call_logger_2026-07-18_19-23-45.db');
  });

  test('αν υπάρχει και με δευτερόλεπτα, προσθέτει αριθμητικό επίθημα', () {
    final name = suggestNewCallLoggerDatabaseFileName(
      directory: dir,
      now: now,
      fileExists: (path) => existsIn({
        'call_logger_2026-07-18.db',
        'call_logger_2026-07-18_19-23.db',
        'call_logger_2026-07-18_19-23-45.db',
      }, path),
    );
    expect(name, 'call_logger_2026-07-18_19-23-45_2.db');
  });
}
