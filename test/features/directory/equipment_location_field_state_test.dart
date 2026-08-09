// Unit tests: ο διακόπτης «Ακολουθεί τη θέση του κατόχου».
//
//   flutter test test/features/directory/equipment_location_field_state_test.dart

import 'package:call_logger/features/directory/models/equipment_location_field_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('αρχική κατάσταση από τη βάση', () {
    test('κενό αποθηκευμένο location σημαίνει «ακολουθεί»', () {
      final s = EquipmentLocationFieldState.fromStored(
        storedLocation: null,
        ownerLocation: 'πρώτο θρανίο δεξιά',
      );

      expect(s.followsOwner, isTrue);
      expect(s.displayText, 'πρώτο θρανίο δεξιά');
      expect(s.valueToStore, isNull);
      expect(s.diverges, isFalse);
    });

    test('αποθηκευμένη τιμή σημαίνει δική του θέση', () {
      final s = EquipmentLocationFieldState.fromStored(
        storedLocation: 'δίπλα στην πόρτα',
        ownerLocation: 'πρώτο θρανίο δεξιά',
      );

      expect(s.followsOwner, isFalse);
      expect(s.displayText, 'δίπλα στην πόρτα');
      expect(s.valueToStore, 'δίπλα στην πόρτα');
      expect(s.diverges, isTrue);
    });
  });

  group('το τσεκάρισμα και το ξετσεκάρισμα είναι αναίρεση', () {
    test('η δική του τιμή επιστρέφει ακέραιη', () {
      final start = EquipmentLocationFieldState.fromStored(
        storedLocation: 'δίπλα στην πόρτα',
        ownerLocation: 'δίπλα στο πολυμηχάνημα',
      );

      final checked = start.follow();
      expect(checked.displayText, 'δίπλα στο πολυμηχάνημα');
      expect(checked.valueToStore, isNull);

      final unchecked = checked.unfollow();
      expect(
        unchecked.displayText,
        'δίπλα στην πόρτα',
        reason: 'το ξετσεκάρισμα επαναφέρει — δεν κρατά τη θέση του κατόχου',
      );
      expect(unchecked.valueToStore, 'δίπλα στην πόρτα');
    });

    test('επαναλαμβανόμενη εναλλαγή δεν αλλοιώνει την τιμή', () {
      var s = EquipmentLocationFieldState.fromStored(
        storedLocation: 'δίπλα στην πόρτα',
        ownerLocation: 'δίπλα στο πολυμηχάνημα',
      );

      for (var i = 0; i < 3; i++) {
        s = s.follow().unfollow();
      }

      expect(s.displayText, 'δίπλα στην πόρτα');
      expect(s.valueToStore, 'δίπλα στην πόρτα');
    });

    test('χωρίς δική του τιμή, το ξετσεκάρισμα δίνει αφετηρία', () {
      final s = EquipmentLocationFieldState.fromStored(
        storedLocation: null,
        ownerLocation: 'πρώτο θρανίο δεξιά',
      ).unfollow();

      expect(
        s.displayText,
        'πρώτο θρανίο δεξιά',
        reason: 'ο χρήστης διορθώνει, δεν γράφει από λευκή σελίδα',
      );
    });
  });

  group('καμία διπλοεγγραφή', () {
    test('τιμή ταυτόσημη με του κατόχου αποθηκεύεται ως «ακολουθεί»', () {
      final s = EquipmentLocationFieldState.fromStored(
        storedLocation: null,
        ownerLocation: 'πρώτο θρανίο δεξιά',
      ).unfollow();

      expect(s.followsOwner, isFalse);
      expect(
        s.valueToStore,
        isNull,
        reason: 'ίδιο κείμενο με του κατόχου δεν είναι δική του θέση',
      );
      expect(s.diverges, isFalse);
    });

    test('η ένδειξη απόκλισης σιωπά όταν η τιμή συμπίπτει', () {
      final s = EquipmentLocationFieldState.fromStored(
        storedLocation: 'πρώτο θρανίο δεξιά',
        ownerLocation: 'πρώτο θρανίο δεξιά',
      );

      expect(s.diverges, isFalse);
    });

    test('άδειασμα του πεδίου επιστρέφει στο «ακολουθεί»', () {
      final s = EquipmentLocationFieldState.fromStored(
        storedLocation: 'δίπλα στην πόρτα',
        ownerLocation: 'πρώτο θρανίο δεξιά',
      ).typed('   ');

      expect(s.valueToStore, isNull);
    });
  });

  group('πληκτρολόγηση', () {
    test('σβήνει τον διακόπτη και κρατά το κείμενο', () {
      final s = EquipmentLocationFieldState.fromStored(
        storedLocation: null,
        ownerLocation: 'πρώτο θρανίο δεξιά',
      ).typed('κάτω από το παράθυρο');

      expect(s.followsOwner, isFalse);
      expect(s.valueToStore, 'κάτω από το παράθυρο');
      expect(s.diverges, isTrue);
    });

    test('το πληκτρολογημένο επιβιώνει από εναλλαγή του διακόπτη', () {
      final s = EquipmentLocationFieldState.fromStored(
        storedLocation: null,
        ownerLocation: 'πρώτο θρανίο δεξιά',
      ).typed('κάτω από το παράθυρο').follow().unfollow();

      expect(s.displayText, 'κάτω από το παράθυρο');
      expect(s.valueToStore, 'κάτω από το παράθυρο');
    });
  });

  group('αλλαγή κατόχου', () {
    test('η δική του θέση δεν παρασύρεται', () {
      final s = EquipmentLocationFieldState.fromStored(
        storedLocation: 'κάτω από το παράθυρο',
        ownerLocation: 'πρώτο θρανίο δεξιά',
      ).withOwnerLocation('απέναντι από το αρχείο');

      expect(s.displayText, 'κάτω από το παράθυρο');
      expect(s.valueToStore, 'κάτω από το παράθυρο');
    });

    test('όσο ακολουθεί, δείχνει τη θέση του νέου κατόχου', () {
      final s = EquipmentLocationFieldState.fromStored(
        storedLocation: null,
        ownerLocation: 'πρώτο θρανίο δεξιά',
      ).withOwnerLocation('απέναντι από το αρχείο');

      expect(s.displayText, 'απέναντι από το αρχείο');
      expect(s.valueToStore, isNull);
    });
  });
}
