// Πότε ένα προφίλ θεωρείται «ανοιχτό αλλού» — ο κανόνας που κλειδώνει την
// επιλογή ταυτότητας, ελεγμένος χωρίς οθόνη και χωρίς βάση.
//
//   flutter test test/core/services/profile_availability_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/models/operator_presence.dart';
import 'package:call_logger/core/services/profile_availability.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime(2026, 9, 24, 12, 0);

Operator _profile(int id, {bool isAdmin = false}) => Operator(
  id: id,
  displayName: 'Προφίλ $id',
  isAdmin: isAdmin,
  createdAt: DateTime(2026, 1, 1),
);

OperatorPresence _mark(
  int operatorId, {
  required String station,
  required String? instance,
  Duration ago = Duration.zero,
}) => OperatorPresence(
  operatorId: operatorId,
  station: station,
  instance: instance,
  lastSeenAt: _now.subtract(ago),
);

ProfileAvailability _for(
  List<OperatorPresence> marks, {
  bool isAdmin = false,
  String myInstance = 'C:/app.exe|dev',
}) {
  final profile = _profile(1, isAdmin: isAdmin);
  final result = profileAvailability(
    profiles: [profile],
    marks: marks,
    now: _now,
    myInstance: myInstance,
  );
  return result[1]!;
}

void main() {
  group('Κλείδωμα προφίλ που κρατά άλλος', () {
    test('ζωντανό ίχνος από άλλο αντίγραφο κλειδώνει το προφίλ', () {
      final state = _for([
        _mark(1, station: 'POPINIO', instance: 'C:/app.exe|prod'),
      ]);

      expect(state.kind, ProfileLockKind.lockedElsewhere);
      expect(state.isLocked, isTrue);
      expect(state.station, 'POPINIO');
    });

    test('ίχνος του ΔΙΚΟΥ μου αντιγράφου δεν κλειδώνει', () {
      // Μετά από κατάρρευση και άμεση επανεκκίνηση στον ίδιο υπολογιστή το
      // ίχνος ανήκει στο ίδιο αντίγραφο: ο άνθρωπος δεν κλειδώνεται έξω από
      // τον εαυτό του.
      final state = _for([
        _mark(1, station: 'PICINIO', instance: 'C:/app.exe|dev'),
      ]);

      expect(state.kind, ProfileLockKind.free);
      expect(state.station, isNull);
    });

    test('ίχνος παλαιότερο από το παράθυρο φρεσκάδας δεν κλειδώνει', () {
      final state = _for([
        _mark(
          1,
          station: 'POPINIO',
          instance: 'C:/app.exe|prod',
          ago: OperatorPresence.onlineWindow + const Duration(seconds: 1),
        ),
      ]);

      expect(state.kind, ProfileLockKind.free);
    });

    test('παραδομένο ίχνος (κανονικό κλείσιμο) δεν κλειδώνει', () {
      final state = _for([_mark(1, station: 'POPINIO', instance: null)]);

      expect(state.kind, ProfileLockKind.free);
    });

    test('προφίλ διαχειριστή ζητά επιβεβαίωση αντί να κλειδώσει', () {
      final state = _for([
        _mark(1, station: 'POPINIO', instance: 'C:/app.exe|prod'),
      ], isAdmin: true);

      expect(state.kind, ProfileLockKind.adminOpenElsewhere);
      expect(state.isLocked, isFalse);
      expect(state.needsAdminConfirmation, isTrue);
      expect(state.station, 'POPINIO');
    });

    test('με δύο ζωντανά ίχνη δείχνεται ο σταθμός του πιο πρόσφατου', () {
      final state = _for([
        _mark(
          1,
          station: 'PALIOS',
          instance: 'C:/app.exe|a',
          ago: const Duration(minutes: 2),
        ),
        _mark(
          1,
          station: 'NEOS',
          instance: 'C:/app.exe|b',
          ago: const Duration(seconds: 10),
        ),
      ]);

      expect(state.station, 'NEOS');
    });

    test('προφίλ χωρίς κανένα ίχνος είναι ελεύθερο', () {
      expect(_for(const []).kind, ProfileLockKind.free);
    });

    test('ίχνος άλλου προφίλ δεν αγγίζει το δικό μας', () {
      final state = _for([
        _mark(2, station: 'POPINIO', instance: 'C:/app.exe|prod'),
      ]);

      expect(state.kind, ProfileLockKind.free);
    });
  });

  group('Ασφαλής απάντηση όταν λείπει η πληροφορία', () {
    test('προφίλ εκτός χάρτη θεωρείται ελεύθερο', () {
      // Η άγνοια πέφτει στην πλευρά που δεν εμποδίζει.
      final state = availabilityFor(
        const <int, ProfileAvailability>{},
        _profile(9),
      );

      expect(state.kind, ProfileLockKind.free);
    });
  });
}
