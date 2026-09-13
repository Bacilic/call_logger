// Ποια «φυλαγμένη βάση» προσφέρεται στον χειριστή μετά από κακή επαναφορά.
//
//   flutter test test/features/database/services/pre_restore_snapshot_test.dart

import 'package:call_logger/features/database/services/pre_restore_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const current = r'C:\Δεδομένα\Hospital.db';

  DatabaseFileEntry at(String path, DateTime modified) =>
      (path: path, modified: modified);

  test('χωρίς υποψήφια, δεν προσφέρεται τίποτα', () {
    expect(
      latestPreRestoreSnapshot(
        currentDatabasePath: current,
        candidates: const [],
      ),
      isNull,
    );
  });

  test('βρίσκει τη φυλαγμένη βάση της τρέχουσας', () {
    final found = latestPreRestoreSnapshot(
      currentDatabasePath: current,
      candidates: [
        at(
          r'C:\Δεδομένα\Hospital_pre_restore_13-09-2026.db',
          DateTime(2026, 9, 13, 8),
        ),
      ],
    );
    expect(found?.fileName, 'Hospital_pre_restore_13-09-2026.db');
  });

  test('κρίνει η ΩΡΑ ΕΓΓΡΑΦΗΣ, όχι η αλφαβητική σειρά του ονόματος', () {
    // Δύο επαναφορές την ίδια μέρα: το δεύτερο όνομα έχει ώρα, το πρώτο όχι,
    // και αλφαβητικά το «_13-09-2026.db» προηγείται του «_13-09-2026_08-21.db».
    // Χρονικά όμως ισχύει το αντίθετο.
    final found = latestPreRestoreSnapshot(
      currentDatabasePath: current,
      candidates: [
        at(
          r'C:\Δεδομένα\Hospital_pre_restore_13-09-2026.db',
          DateTime(2026, 9, 13, 7, 43),
        ),
        at(
          r'C:\Δεδομένα\Hospital_pre_restore_13-09-2026_08-21.db',
          DateTime(2026, 9, 13, 8, 21),
        ),
      ],
    );
    expect(found?.fileName, 'Hospital_pre_restore_13-09-2026_08-21.db');
  });

  test('η φυλαγμένη ΑΛΛΗΣ βάσης δεν προσφέρεται', () {
    expect(
      latestPreRestoreSnapshot(
        currentDatabasePath: current,
        candidates: [
          at(
            r'C:\Δεδομένα\Ακτινολογικό_pre_restore_13-09-2026.db',
            DateTime(2026, 9, 13, 9),
          ),
        ],
      ),
      isNull,
      reason: 'Θα επανέφερε τη βάση άλλου τμήματος πάνω στη δική του',
    );
  });

  test('απλά αρχεία βάσης δίπλα δεν μπερδεύονται με φυλαγμένα', () {
    expect(
      latestPreRestoreSnapshot(
        currentDatabasePath: current,
        candidates: [
          at(r'C:\Δεδομένα\Hospital.db', DateTime(2026, 9, 13, 10)),
          at(r'C:\Δεδομένα\Hospital_shared.db', DateTime(2026, 9, 13, 10)),
          at(
            r'C:\Δεδομένα\Hospital_αναβαθμισμένη_04-09-2026.db',
            DateTime(2026, 9, 13, 10),
          ),
        ],
      ),
      isNull,
    );
  });

  test('αλυσίδα επαναφορών: κρατά την τελευταία', () {
    // Μετά από δεύτερη επαναφορά, η ήδη φυλαγμένη βάση γίνεται η τρέχουσα και
    // το νέο φυλαγμένο αρχείο κληρονομεί ολόκληρο το όνομά της.
    const chained = r'C:\Δεδομένα\Hospital_pre_restore_13-09-2026.db';
    final found = latestPreRestoreSnapshot(
      currentDatabasePath: chained,
      candidates: [
        at(
          r'C:\Δεδομένα\Hospital_pre_restore_13-09-2026_pre_restore_13-09-2026.db',
          DateTime(2026, 9, 13, 17, 41),
        ),
      ],
    );
    expect(found, isNotNull);
    expect(found!.savedAt.hour, 17);
  });

  test('αρχεία που δεν είναι βάσεις αγνοούνται', () {
    expect(
      latestPreRestoreSnapshot(
        currentDatabasePath: current,
        candidates: [
          at(
            r'C:\Δεδομένα\Hospital_pre_restore_13-09-2026.db-wal',
            DateTime(2026, 9, 13, 11),
          ),
          at(
            r'C:\Δεδομένα\Hospital_pre_restore_13-09-2026.txt',
            DateTime(2026, 9, 13, 11),
          ),
        ],
      ),
      isNull,
    );
  });
}
