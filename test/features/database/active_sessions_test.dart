// Ποιες ανοιχτές εφαρμογές κρατούν τη βάση τώρα — η καθαρή λογική της λίστας.
//
//   flutter test test/features/database/active_sessions_test.dart

import 'package:call_logger/core/models/operator_presence.dart';
import 'package:call_logger/features/database/services/active_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

/// Η ώρα αναφοράς όλων των ελέγχων· καρφωτή, ώστε η «φρεσκάδα» να μην εξαρτάται
/// από το πότε τρέχει ο έλεγχος.
final DateTime _now = DateTime(2026, 9, 14, 12, 0);

PresenceWithName _mark({
  required int operatorId,
  required String station,
  required Duration ago,
  String? instance = 'C:\\app.exe',
  String? name,
  String? appVersion,
}) {
  return (
    presence: OperatorPresence(
      operatorId: operatorId,
      station: station,
      lastSeenAt: _now.subtract(ago),
      instance: instance,
      appVersion: appVersion,
    ),
    operatorName: name,
  );
}

void main() {
  group('Ενεργές συνεδρίες', () {
    test('φρέσκο ίχνος με κάτοχο μετράει· παλιό και ορφανό δεν μετρούν', () {
      final sessions = activeSessions(
        marks: [
          _mark(
            operatorId: 1,
            station: 'TEP-02',
            ago: const Duration(seconds: 30),
          ),
          // Πέρα από το παράθυρο φρεσκάδας: η εφαρμογή έκλεισε απότομα.
          _mark(
            operatorId: 2,
            station: 'GRAM-05',
            ago: const Duration(minutes: 10),
          ),
          // Παρέδωσε τον κάτοχο: η γραμμή μένει ως ιστορικό, όχι ως παρουσία.
          _mark(
            operatorId: 3,
            station: 'PICINIO',
            ago: const Duration(seconds: 5),
            instance: null,
          ),
        ],
        now: _now,
        myInstance: 'C:\\other.exe',
      );

      expect(
        sessions.map((s) => s.station),
        ['TEP-02'],
        reason: greekExpectMsg(
          'Ζωντανή είναι μόνο η συνεδρία που είναι και φρέσκια και με κάτοχο',
        ),
      );
    });

    test('η δική μου συνεδρία ξεχωρίζει και μπαίνει πρώτη', () {
      final sessions = activeSessions(
        marks: [
          _mark(
            operatorId: 1,
            station: 'TEP-02',
            ago: const Duration(seconds: 10),
            instance: 'C:\\other.exe',
          ),
          _mark(
            operatorId: 2,
            station: 'PICINIO',
            ago: const Duration(seconds: 50),
            instance: 'C:\\app.exe',
          ),
        ],
        now: _now,
        myInstance: 'C:\\app.exe',
      );

      expect(sessions.first.station, 'PICINIO');
      expect(sessions.first.isMine, isTrue);
      expect(
        otherSessions(sessions).map((s) => s.station),
        ['TEP-02'],
        reason: greekExpectMsg(
          'Ο φρουρός ρωτά για τους ΑΛΛΟΥΣ — η δική μου συνεδρία δεν μετράει',
        ),
      );
    });

    test('δύο προφίλ στον ίδιο υπολογιστή μετρούν ως ένας υπολογιστής', () {
      // Η κανονική και η δοκιμαστική εφαρμογή είναι δύο αληθινές παρουσίες,
      // αλλά ένα μηχάνημα — η περίληψη μετρά μηχανήματα.
      final sessions = activeSessions(
        marks: [
          _mark(
            operatorId: 1,
            station: 'PICINIO',
            ago: const Duration(seconds: 5),
            instance: 'C:\\app.exe',
          ),
          _mark(
            operatorId: 2,
            station: 'PICINIO',
            ago: const Duration(seconds: 8),
            instance: 'C:\\app.exe|test',
          ),
        ],
        now: _now,
        myInstance: 'C:\\app.exe',
      );

      expect(sessions, hasLength(2));
      expect(distinctStationCount(sessions), 1);
      expect(describeStationCount(1), '1 υπολογιστής');
      expect(describeStationCount(3), '3 υπολογιστές');
    });

    test('χωρίς ταυτότητα αντιγράφου καμία συνεδρία δεν λέγεται δική μου', () {
      // Όταν το σύστημα δεν δίνει διαδρομή εκτελέσιμου, η κενή ταυτότητα δεν
      // επιτρέπεται να ταιριάξει με ίχνη που κι αυτά δεν έχουν κάτοχο.
      final sessions = activeSessions(
        marks: [
          _mark(
            operatorId: 1,
            station: 'TEP-02',
            ago: const Duration(seconds: 5),
          ),
        ],
        now: _now,
        myInstance: '',
      );

      expect(sessions.single.isMine, isFalse);
      expect(otherSessions(sessions), hasLength(1));
    });
  });

  group('Περιγραφή συνεδρίας', () {
    test('σταθμός, όνομα και πόσο πριν', () {
      final sessions = activeSessions(
        marks: [
          _mark(
            operatorId: 1,
            station: 'TEP-02',
            ago: const Duration(minutes: 2),
            name: 'Βαρβάρα',
            instance: 'C:\\other.exe',
          ),
        ],
        now: _now,
        myInstance: 'C:\\app.exe',
      );

      expect(
        describeActiveSession(sessions.single, now: _now),
        'TEP-02 · Βαρβάρα · πριν από 2΄',
      );
    });

    test('η δική μου γραμμή λέει «εσείς» αντί για χρόνο', () {
      final sessions = activeSessions(
        marks: [
          _mark(
            operatorId: 1,
            station: 'PICINIO',
            ago: const Duration(minutes: 2),
            name: 'Βασίλης',
            instance: 'C:\\app.exe',
          ),
        ],
        now: _now,
        myInstance: 'C:\\app.exe',
      );

      expect(
        describeActiveSession(sessions.single, now: _now),
        'PICINIO · Βασίλης · εσείς',
      );
    });

    test('η έκδοση γράφεται μόνο όταν διαφέρει από τη δική μας', () {
      final sessions = activeSessions(
        marks: [
          _mark(
            operatorId: 1,
            station: 'PICINIO',
            ago: const Duration(seconds: 5),
            name: 'Βασίλης',
            instance: 'C:\\app.exe',
            appVersion: '1.59.0',
          ),
          _mark(
            operatorId: 2,
            station: 'TEP-02',
            ago: const Duration(seconds: 20),
            name: 'Βαρβάρα',
            instance: 'C:\\other.exe',
            appVersion: '1.59.0',
          ),
          _mark(
            operatorId: 3,
            station: 'GRAM-05',
            ago: const Duration(seconds: 20),
            name: 'Νίκος',
            instance: 'C:\\third.exe',
            appVersion: '1.57.0',
          ),
        ],
        now: _now,
        myInstance: 'C:\\app.exe',
      );

      final mine = myAppVersion(sessions);
      expect(mine, '1.59.0');

      final lines = [
        for (final s in sessions)
          describeActiveSession(s, now: _now, myAppVersion: mine),
      ];

      expect(
        lines.where((l) => l.contains('έκδοση')),
        ['GRAM-05 · Νίκος · μόλις τώρα · έκδοση 1.57.0'],
        reason: greekExpectMsg(
          'Μόνο η ΔΙΑΦΟΡΕΤΙΚΗ έκδοση πληροφορεί· η ίδια γεμίζει τη γραμμή',
        ),
      );
    });

    test('συνεδρία χωρίς όνομα χρήστη δεν εξαφανίζεται από τη λίστα', () {
      // Το προφίλ διαγράφηκε ενώ η εφαρμογή ήταν ανοιχτή: καλύτερα ένας
      // σταθμός χωρίς όνομα παρά μια συνεδρία που κρατά το αρχείο αόρατα.
      final sessions = activeSessions(
        marks: [
          _mark(
            operatorId: 9,
            station: 'GRAM-05',
            ago: const Duration(seconds: 5),
            instance: 'C:\\other.exe',
          ),
        ],
        now: _now,
        myInstance: 'C:\\app.exe',
      );

      expect(
        describeActiveSession(sessions.single, now: _now),
        'GRAM-05 · μόλις τώρα',
      );
    });
  });
}
