import 'package:call_logger/core/services/session_liveness_mark.dart';
import 'package:call_logger/core/services/station_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  SessionLivenessMark mark({
    String station = 'PC-3',
    String version = '0.46.0',
    DateTime? startedAt,
    DateTime? lastSeen,
  }) {
    return SessionLivenessMark(
      station: station,
      version: version,
      startedAt: startedAt ?? DateTime(2026, 9, 4, 18, 12),
      lastSeen: lastSeen ?? DateTime(2026, 9, 4, 18, 39),
    );
  }

  group('SessionLivenessMark · τι επιβιώνει της κατάρρευσης', () {
    test('ό,τι γράφεται, ξαναδιαβάζεται όπως ήταν', () {
      final original = mark();
      final restored = SessionLivenessMark.decode(original.encode());

      expect(restored, isNotNull);
      expect(restored!.station, 'PC-3');
      expect(restored.version, '0.46.0');
      expect(restored.startedAt, DateTime(2026, 9, 4, 18, 12));
      expect(restored.lastSeen, DateTime(2026, 9, 4, 18, 39));
    });

    test('το σημάδι ζωής μετακινεί μόνο το «μέχρι πότε»', () {
      final beat = mark().seenAt(DateTime(2026, 9, 4, 20, 5));

      expect(beat.startedAt, DateTime(2026, 9, 4, 18, 12));
      expect(beat.lastSeen, DateTime(2026, 9, 4, 20, 5));
    });

    test('ίχνος παλιάς μορφής ή αλλοιωμένο δεν διαβάζεται — και δεν σκάει', () {
      for (final raw in ['1', '', '   ', '{σκουπίδια', '[]', '{"a":1}']) {
        expect(
          SessionLivenessMark.decode(raw),
          isNull,
          reason: greekExpectMsg(
            'Το «$raw» δεν είναι ίχνος που εμπιστευόμαστε',
          ),
        );
      }
    });

    test('το μήνυμα ονομάζει έκδοση, σταθμό, ώρα και διάρκεια', () {
      expect(
        mark().describeLostRun(),
        'Η προηγούμενη εκτέλεση δεν τερμάτισε ομαλά '
        '(έκδοση 0.46.0, σταθμός PC-3): ξεκίνησε 04/09/2026 18:12, '
        'τελευταίο σημάδι ζωής 04/09/2026 18:39 — έζησε 27 λεπτά.',
      );
    });

    test('χωρίς ταυτότητα, το μήνυμα λέει μόνο ό,τι ξέρει', () {
      final anonymous = mark(station: '', version: '').describeLostRun();

      expect(anonymous, isNot(contains('(')));
      expect(anonymous, contains('ξεκίνησε 04/09/2026 18:12'));
    });
  });

  group('SessionLivenessMark.formatLifetime', () {
    test('κάτω από ένα λεπτό δεν προσποιείται ακρίβεια', () {
      expect(
        SessionLivenessMark.formatLifetime(const Duration(seconds: 40)),
        'λιγότερο από ένα λεπτό',
      );
    });

    test('λεπτά, ώρες, και τα δύο μαζί — στον ενικό και στον πληθυντικό', () {
      expect(
        SessionLivenessMark.formatLifetime(const Duration(minutes: 1)),
        '1 λεπτό',
      );
      expect(
        SessionLivenessMark.formatLifetime(const Duration(minutes: 27)),
        '27 λεπτά',
      );
      expect(
        SessionLivenessMark.formatLifetime(const Duration(hours: 1)),
        '1 ώρα',
      );
      expect(
        SessionLivenessMark.formatLifetime(
          const Duration(hours: 6, minutes: 41),
        ),
        '6 ώρες και 41 λεπτά',
      );
      expect(
        SessionLivenessMark.formatLifetime(
          const Duration(hours: 1, minutes: 1),
        ),
        '1 ώρα και 1 λεπτό',
      );
    });
  });

  group('StationName · ο σταθμός ως όνομα αρχείου', () {
    tearDown(() => StationName.reader = StationName.defaultReader);

    test('τελείες και κενά γίνονται παύλες', () {
      StationName.reader = () => 'pc-3.tmima.local';
      expect(StationName.fileSafe, 'pc-3-tmima-local');

      StationName.reader = () => 'Σταθμός Γραμματείας';
      expect(
        StationName.fileSafe,
        'Σταθμός-Γραμματείας',
        reason: greekExpectMsg('Τα ελληνικά γράμματα επιβιώνουν'),
      );
    });

    test('όνομα που δεν δίνεται ή δεν αφήνει τίποτα γίνεται «unknown»', () {
      StationName.reader = () => '';
      expect(StationName.fileSafe, StationName.unknownStation);

      StationName.reader = () => '///';
      expect(StationName.fileSafe, StationName.unknownStation);
    });

    test('πολύ μακρύ όνομα κόβεται — η διαδρομή έχει όριο', () {
      StationName.reader = () => 'Α' * 200;
      expect(StationName.fileSafe.length, StationName.maxLength);
    });

    test('σύστημα που πετάει δεν ρίχνει τίποτα', () {
      StationName.reader = () => throw StateError('δεν απαντά');
      expect(StationName.current, isEmpty);
      expect(StationName.fileSafe, StationName.unknownStation);
    });
  });
}
