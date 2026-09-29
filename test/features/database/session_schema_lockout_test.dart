import 'package:call_logger/core/services/app_instance_registry.dart';
import 'package:call_logger/features/database/services/active_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ο σταθμός που θα μείνει έξω από τη βάση — και η σιωπή όπου δεν ξέρουμε.
///
/// **Το σενάριο πεδίου (28/09):** η βάση αναβαθμίστηκε σε σχήμα 67 ενώ ο
/// POPINIO την κρατούσε ανοιχτή με έκδοση 0.57.1, που διαβάζει έως το 66. Η
/// οθόνη εμφάνιζε και τους τρεις αριθμούς και δεν έλεγε ότι ο συνάδελφος θα
/// μείνει έξω μόλις κλείσει την εφαρμογή του.
void main() {
  ActiveSession session({
    String station = 'POPINIO',
    String? version = '0.57.1',
    int? ceiling = 66,
    bool isMine = false,
  }) => ActiveSession(
    station: station,
    lastSeenAt: DateTime(2026, 9, 28, 16, 32),
    isMine: isMine,
    appVersion: version,
    schemaCeiling: ceiling,
  );

  group('ποιος μένει έξω', () {
    test('ταβάνι χαμηλότερο από το σχήμα της βάσης = μένει έξω', () {
      expect(session().cannotReopenSchema(67), isTrue);
    });

    test('ταβάνι ίσο με το σχήμα = μπορεί', () {
      expect(session(ceiling: 67).cannotReopenSchema(67), isFalse);
    });

    test('ταβάνι υψηλότερο = μπορεί', () {
      expect(session(ceiling: 68).cannotReopenSchema(67), isFalse);
    });

    test('η δική μας συνεδρία δεν προειδοποιείται ποτέ', () {
      // Η βάση είναι ανοιχτή από εμάς — μια προειδοποίηση εδώ θα αντίφασκε με
      // την ίδια την οθόνη που τη δείχνει.
      expect(
        session(ceiling: 66, isMine: true).cannotReopenSchema(67),
        isFalse,
      );
    });
  });

  group('σιωπή όπου δεν ξέρουμε', () {
    test('άγνωστο ταβάνι δεν γεννά προειδοποίηση', () {
      expect(session(ceiling: null).cannotReopenSchema(67), isFalse);
    });

    test('άγνωστο σχήμα βάσης δεν γεννά προειδοποίηση', () {
      expect(session().cannotReopenSchema(null), isFalse);
    });
  });

  group('το μήνυμα', () {
    test('ο σταθμός που μένει έξω το λέει', () {
      final text = describeActiveSession(
        session(),
        now: DateTime(2026, 9, 28, 16, 32),
        myAppVersion: '0.58.0',
        databaseSchemaVersion: 67,
      );

      expect(text, contains('POPINIO'));
      expect(text, contains('0.57.1'));
      expect(text, contains('δεν θα μπορεί να ξανανοίξει τη βάση'));
    });

    test('ο σταθμός που μπορεί δεν λέει τίποτα παραπάνω', () {
      final text = describeActiveSession(
        session(ceiling: 67),
        now: DateTime(2026, 9, 28, 16, 32),
        myAppVersion: '0.58.0',
        databaseSchemaVersion: 67,
      );

      expect(text, isNot(contains('δεν θα μπορεί')));
    });

    test('άγνωστο ταβάνι αφήνει τη γραμμή όπως ήταν', () {
      final text = describeActiveSession(
        session(ceiling: null),
        now: DateTime(2026, 9, 28, 16, 32),
        myAppVersion: '0.58.0',
        databaseSchemaVersion: 67,
      );

      expect(text, isNot(contains('δεν θα μπορεί')));
    });

    test('η έκδοση γράφεται ακόμη κι όταν ταυτίζεται με τη δική μας', () {
      // Χωρίς αυτήν ο χρήστης διαβάζει «δεν θα μπορεί» χωρίς τον αριθμό που
      // το εξηγεί.
      final text = describeActiveSession(
        session(version: '0.58.0', ceiling: 66),
        now: DateTime(2026, 9, 28, 16, 32),
        myAppVersion: '0.58.0',
        databaseSchemaVersion: 67,
      );

      expect(text, contains('0.58.0'));
      expect(text, contains('δεν θα μπορεί'));
    });
  });

  group('το ταβάνι μιας έκδοσης', () {
    final known = [
      AppInstanceRecord(
        executablePath: r'F:\Release\call_logger.exe',
        version: '0.57.1',
        lastSeen: DateTime(2026, 9, 23),
        schemaVersion: 66,
      ),
      AppInstanceRecord(
        executablePath: r'F:\Debug\call_logger.exe',
        version: '0.58.0',
        lastSeen: DateTime(2026, 9, 28),
        schemaVersion: 67,
      ),
    ];

    test('βρίσκεται από το τοπικό μητρώο, για ΞΕΝΟ σταθμό', () {
      // Το ταβάνι είναι ιδιότητα του build: η 0.57.1 διαβάζει έως 66 παντού.
      expect(AppInstanceRegistry.schemaCeilingForVersion(known, '0.57.1'), 66);
    });

    test('έκδοση που δεν έτρεξε ποτέ εδώ δίνει «δεν ξέρω»', () {
      expect(
        AppInstanceRegistry.schemaCeilingForVersion(known, '0.42.0'),
        isNull,
      );
    });

    test('κενή έκδοση δίνει «δεν ξέρω»', () {
      expect(AppInstanceRegistry.schemaCeilingForVersion(known, ''), isNull);
      expect(AppInstanceRegistry.schemaCeilingForVersion(known, null), isNull);
    });

    test('εγγραφή χωρίς καταγεγραμμένο ταβάνι δίνει «δεν ξέρω»', () {
      final older = [
        AppInstanceRecord(
          executablePath: r'F:\Old\call_logger.exe',
          version: '0.50.0',
          lastSeen: DateTime(2026, 1, 1),
        ),
      ];
      expect(
        AppInstanceRegistry.schemaCeilingForVersion(older, '0.50.0'),
        isNull,
      );
    });
  });

  test('η λίστα των αποκλεισμένων κρατά μόνο όσους μένουν έξω', () {
    final all = [
      session(station: 'POPINIO', ceiling: 66),
      session(station: 'PICINIO', ceiling: 67, isMine: true),
      session(station: 'ΑΓΝΩΣΤΟΣ', ceiling: null),
    ];

    final locked = sessionsLockedOutBySchema(all, 67);

    expect(locked, hasLength(1));
    expect(locked.single.station, 'POPINIO');
  });
}
