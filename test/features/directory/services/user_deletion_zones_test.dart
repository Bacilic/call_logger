// Ζώνες μαζικής διαγραφής υπαλλήλων: ποιοι θα ρωτηθούν και ποιοι όχι.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/services/user_deletion_zones_test.dart

import 'package:call_logger/features/directory/services/user_deletion_zones.dart';
import 'package:flutter_test/flutter_test.dart';

var _nextId = 0;

UserDeletionInventory _inv(String label, {int phones = 0, int equipment = 0}) {
  return UserDeletionInventory(
    userId: ++_nextId,
    displayLabel: label,
    exclusivePhoneCount: phones,
    exclusiveEquipmentCount: equipment,
  );
}

List<String> _labelsOf(List<UserDeletionInventory> zone) =>
    zone.map((i) => i.displayLabel).toList();

void main() {
  group('Κατάταξη σε ζώνες', () {
    test('χωρίζει όσους έχουν προσωπικά στοιχεία από τους υπόλοιπους', () {
      final zones = UserDeletionZones.from([
        _inv('Άδειος Α'),
        _inv('Με τηλέφωνο', phones: 1),
        _inv('Άδειος Β'),
        _inv('Με εξοπλισμό', equipment: 2),
      ]);

      expect(_labelsOf(zones.withAssets), ['Με τηλέφωνο', 'Με εξοπλισμό']);
      expect(_labelsOf(zones.empty), ['Άδειος Α', 'Άδειος Β']);
    });

    test('η σειρά μέσα σε κάθε ζώνη μένει όπως δόθηκε', () {
      final zones = UserDeletionZones.from([
        _inv('Ωμέγα', phones: 1),
        _inv('Άλφα', phones: 1),
      ]);

      expect(_labelsOf(zones.withAssets), ['Ωμέγα', 'Άλφα']);
    });
  });

  group('Πλήθος ερωτήσεων που ακολουθούν', () {
    test('αθροίζει τηλέφωνα και εξοπλισμό όλων', () {
      final zones = UserDeletionZones.from([
        _inv('Α', phones: 2, equipment: 1),
        _inv('Β', phones: 1),
        _inv('Γ'),
      ]);

      expect(zones.totalAssetCount, 4);
    });

    test('χωρίς στοιχεία: καμία ερώτηση', () {
      final zones = UserDeletionZones.from([_inv('Α'), _inv('Β')]);

      expect(zones.totalAssetCount, 0);
    });
  });

  group('Επικεφαλίδες', () {
    test('μία μόνο γεμάτη ζώνη: καμία επικεφαλίδα', () {
      final zones = UserDeletionZones.from([
        _inv('Α', phones: 1),
        _inv('Β', phones: 1),
      ]);

      expect(zones.showsZoneHeaders, isFalse);
    });

    test('και οι δύο ζώνες γεμάτες: επικεφαλίδες με πλήθος', () {
      final zones = UserDeletionZones.from([_inv('Α', phones: 1), _inv('Β')]);

      expect(zones.showsZoneHeaders, isTrue);
      expect(zones.withAssetsHeader, 'Με προσωπικά στοιχεία (1)');
    });

    test('η γραμμή των άδειων λέει ότι δεν θα ρωτηθεί τίποτα', () {
      final zones = UserDeletionZones.from([
        _inv('Α', phones: 1),
        _inv('Β'),
        _inv('Γ'),
      ]);

      expect(
        zones.emptyHeader,
        '2 υπάλληλοι χωρίς προσωπικά στοιχεία — διαγράφονται χωρίς ερώτηση',
      );
    });

    test('ένας άδειος: ενικός', () {
      final zones = UserDeletionZones.from([_inv('Α', phones: 1), _inv('Β')]);

      expect(
        zones.emptyHeader,
        '1 υπάλληλος χωρίς προσωπικά στοιχεία — διαγράφεται χωρίς ερώτηση',
      );
    });

    test('χωρίς άδειους: καμία γραμμή', () {
      final zones = UserDeletionZones.from([_inv('Α', phones: 1)]);

      expect(zones.emptyHeader, isNull);
    });
  });

  group('Γραμμές περίληψης ανά υπάλληλο', () {
    test('παραλείπει τα μηδενικά είδη', () {
      expect(_inv('Α', phones: 2).buildSummaryLines(), [
        '2 προσωπικά τηλέφωνα',
      ]);
    });

    test('ενικοί και για τα δύο είδη', () {
      expect(_inv('Α', phones: 1, equipment: 1).buildSummaryLines(), [
        '1 προσωπικό τηλέφωνο',
        '1 προσωπικός εξοπλισμός',
      ]);
    });
  });
}
