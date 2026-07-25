// Καθαρή λογική επιλογής υποψηφίου βάσης μέσα σε .zip.
//
//   flutter test test/features/database/services/backup_zip_candidate_selection_test.dart

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/features/database/services/backup_zip_candidate_selection.dart';
import 'package:call_logger/features/database/services/backup_zip_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

BackupZipEligibleCandidate _eligible(String name) => BackupZipEligibleCandidate(
      entryName: name,
      displayName: name,
      sizeBytes: 10,
      profile: const DatabaseFileProfile(kind: DatabaseFileKind.callLogger),
    );

void main() {
  test('κανένας έγκυρος υποψήφιος → αποτυχία με μήνυμα που ονομάζει τι βρέθηκε',
      () {
    final decision = decideBackupZipCandidateSelection(
      BackupZipInventory(
        eligibleCandidates: const [],
        rejectedCandidates: [
          BackupZipRejectedCandidate(
            entryName: 'lamp.db',
            displayName: 'lamp.db',
            sizeBytes: 1,
            reason: 'βάση Λάμπας',
          ),
          BackupZipRejectedCandidate(
            entryName: 'x.db',
            displayName: 'x.db',
            sizeBytes: 1,
            reason: 'άγνωστο σχήμα',
          ),
        ],
        isFullBackupArchive: false,
        totalDatabaseEntries: 2,
      ),
    );

    expect(decision.kind, BackupZipCandidateSelectionKind.none);
    expect(decision.failureMessage, contains('2'));
    expect(decision.failureMessage, contains('Λάμπας'));
    expect(decision.selected, isNull);
    expect(decision.requiresUserChoice, isFalse);
  });

  test('ακριβώς ένας υποψήφιος → αυτόματη επιλογή χωρίς ερώτηση', () {
    final only = _eligible('call_logger.db');
    final decision = decideBackupZipCandidateSelection(
      BackupZipInventory(
        eligibleCandidates: [only],
        rejectedCandidates: const [],
        isFullBackupArchive: false,
        totalDatabaseEntries: 1,
      ),
    );

    expect(decision.kind, BackupZipCandidateSelectionKind.automatic);
    expect(decision.selected, same(only));
    expect(decision.requiresUserChoice, isFalse);
  });

  test('δύο ή περισσότεροι → υποχρεωτική ερώτηση, ποτέ αυτόματη επιλογή', () {
    final decision = decideBackupZipCandidateSelection(
      BackupZipInventory(
        eligibleCandidates: [
          _eligible('giannis.db'),
          _eligible('db1.db'),
          _eligible('call_logger.db'),
        ],
        rejectedCandidates: const [],
        isFullBackupArchive: true,
        totalDatabaseEntries: 3,
      ),
    );

    expect(decision.kind, BackupZipCandidateSelectionKind.requiresChoice);
    expect(decision.requiresUserChoice, isTrue);
    expect(decision.selected, isNull);
  });
}
