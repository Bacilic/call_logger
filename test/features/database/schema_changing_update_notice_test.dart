// Πότε η ενημέρωση προειδοποιεί ότι θα αλλάξει τη δομή της κοινής βάσης.
//
//   flutter test test/features/database/schema_changing_update_notice_test.dart

import 'package:call_logger/features/database/widgets/schema_changing_update_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('πακέτο με νεότερο σχήμα από το αρχείο → προειδοποιεί', () {
    expect(
      updateChangesDatabaseSchema(
        packageSchemaVersion: 67,
        fileSchemaVersion: 66,
      ),
      isTrue,
    );
  });

  test('η βάση είναι ήδη σε αυτό το σχήμα → σιωπή', () {
    // Ο συνάδελφος που αποκλείστηκε επειδή η βάση προχώρησε πριν από εκείνον:
    // πρέπει να ενημερωθεί χωρίς κανένα εμπόδιο.
    expect(
      updateChangesDatabaseSchema(
        packageSchemaVersion: 67,
        fileSchemaVersion: 67,
      ),
      isFalse,
    );
  });

  test('πακέτο που δεν δηλώνει σχήμα → σιωπή, όχι εικασία', () {
    expect(
      updateChangesDatabaseSchema(
        packageSchemaVersion: null,
        fileSchemaVersion: 66,
      ),
      isFalse,
    );
  });

  test('βάση που δεν απάντησε → σιωπή', () {
    expect(
      updateChangesDatabaseSchema(
        packageSchemaVersion: 67,
        fileSchemaVersion: null,
      ),
      isFalse,
    );
    expect(
      updateChangesDatabaseSchema(
        packageSchemaVersion: 67,
        fileSchemaVersion: 0,
      ),
      isFalse,
    );
  });
}
