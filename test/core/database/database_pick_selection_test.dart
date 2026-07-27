// Ταξινόμηση επιλογής επιλογέα βάσης (.db vs .zip).
//
//   flutter test test/core/database/database_pick_selection_test.dart

import 'package:call_logger/core/database/database_path_pick_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyPickedDatabasePath', () {
    test('.zip → backupArchive', () {
      expect(
        classifyPickedDatabasePath(r'E:\backups\call_logger_2026.zip'),
        DatabasePickKind.backupArchive,
      );
    });

    test('.ZIP (κεφαλαία) → backupArchive', () {
      expect(
        classifyPickedDatabasePath(r'E:\backups\call_logger_2026.ZIP'),
        DatabasePickKind.backupArchive,
      );
    });

    test('.db → databaseFile', () {
      expect(
        classifyPickedDatabasePath(r'C:\data\call_logger.db'),
        DatabasePickKind.databaseFile,
      );
    });

    test('χωρίς κατάληξη → databaseFile', () {
      expect(
        classifyPickedDatabasePath(r'C:\data\call_logger'),
        DatabasePickKind.databaseFile,
      );
    });

    test('«zip» μόνο στο όνομα, κατάληξη .db → databaseFile', () {
      expect(
        classifyPickedDatabasePath(r'C:\data\backup_zip_2026.db'),
        DatabasePickKind.databaseFile,
      );
    });
  });
}
