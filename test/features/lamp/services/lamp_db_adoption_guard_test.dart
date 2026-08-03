// Φύλαξη υιοθέτησης βάσης Λάμπας — απόρριψη callLogger/hybrid, σύγκρουση ονόματος
// και ονοματοδοσία «διατήρηση και των δύο».
//
//   flutter test test/features/lamp/services/lamp_db_adoption_guard_test.dart

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/features/lamp/services/lamp_db_adoption_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decideLampDbAdoption', () {
    test(
      'επιλεγμένο callLogger → απόρριψη με όνομα αρχείου στο μήνυμα',
      () async {
        final decision = await decideLampDbAdoption(
          pickedPath: r'C:\Data\call_logger.db',
          destinationPath: r'D:\Portable\Data Base\call_logger.db',
          classify: (_) async => DatabaseFileKind.callLogger,
          fileExists: (_) async => false,
        );

        expect(decision.allowed, isFalse);
        expect(decision.destinationExists, isFalse);
        expect(decision.rejectionMessage, contains('call_logger.db'));
        expect(
          decision.rejectionMessage,
          contains('βάση της Καταγραφής Κλήσεων'),
        );
      },
    );

    test(
      'επιλεγμένο lamp με ομώνυμο προορισμό callLogger → απόρριψη',
      () async {
        Future<DatabaseFileKind> classify(String path) async {
          if (path.contains(r'\Portable\')) {
            return DatabaseFileKind.callLogger;
          }
          return DatabaseFileKind.lamp;
        }

        final decision = await decideLampDbAdoption(
          pickedPath: r'C:\Incoming\equipment.db',
          destinationPath: r'D:\Portable\Data Base\equipment.db',
          classify: classify,
          fileExists: (_) async => true,
        );

        expect(decision.allowed, isFalse);
        expect(decision.rejectionMessage, contains('equipment.db'));
        expect(decision.rejectionMessage, contains('θα την κατέστρεφε'));
      },
    );

    test(
      'επιλεγμένο lamp με ομώνυμο προορισμό lamp → σύγκρουση προς επίλυση',
      () async {
        final decision = await decideLampDbAdoption(
          pickedPath: r'C:\Incoming\old_equipment.db',
          destinationPath: r'D:\Portable\Data Base\old_equipment.db',
          classify: (_) async => DatabaseFileKind.lamp,
          fileExists: (_) async => true,
        );

        expect(decision.allowed, isTrue);
        expect(decision.destinationExists, isTrue);
        expect(decision.destinationIsConfiguredOutput, isFalse);
        expect(decision.rejectionMessage, isNull);
      },
    );

    test(
      'ο προορισμός είναι η ρυθμισμένη βάση εξόδου → σημαιοδοτείται',
      () async {
        final decision = await decideLampDbAdoption(
          pickedPath: r'C:\Incoming\old_equipment 2.db',
          destinationPath: r'D:\Portable\Data Base\old_equipment 2.db',
          configuredOutputPath: r'D:\Portable\Data Base\old_equipment 2.db',
          classify: (_) async => DatabaseFileKind.lamp,
          fileExists: (_) async => true,
        );

        expect(decision.allowed, isTrue);
        expect(decision.destinationExists, isTrue);
        expect(decision.destinationIsConfiguredOutput, isTrue);
      },
    );

    test(
      'άλλη ρυθμισμένη έξοδος → η σύγκρουση δεν σημαιοδοτείται ως έξοδος',
      () async {
        final decision = await decideLampDbAdoption(
          pickedPath: r'C:\Incoming\old_equipment 2.db',
          destinationPath: r'D:\Portable\Data Base\old_equipment 2.db',
          configuredOutputPath: r'D:\Portable\Data Base\alli_vasi.db',
          classify: (_) async => DatabaseFileKind.lamp,
          fileExists: (_) async => true,
        );

        expect(decision.destinationExists, isTrue);
        expect(decision.destinationIsConfiguredOutput, isFalse);
      },
    );

    test(
      'επιλεγμένο lamp χωρίς υπάρχοντα προορισμό → καμία σύγκρουση',
      () async {
        final decision = await decideLampDbAdoption(
          pickedPath: r'C:\Incoming\lamp_new.db',
          destinationPath: r'D:\Portable\Data Base\lamp_new.db',
          classify: (_) async => DatabaseFileKind.lamp,
          fileExists: (_) async => false,
        );

        expect(decision.allowed, isTrue);
        expect(decision.destinationExists, isFalse);
        expect(decision.rejectionMessage, isNull);
      },
    );

    test('ίδιο φυσικό αρχείο πηγής/προορισμού → καμία σύγκρουση', () async {
      final decision = await decideLampDbAdoption(
        pickedPath: r'D:\Portable\Data Base\lamp.db',
        destinationPath: r'D:\Portable\Data Base\lamp.db',
        classify: (_) async => DatabaseFileKind.lamp,
        fileExists: (_) async => true,
      );

      expect(decision.allowed, isTrue);
      expect(decision.destinationExists, isFalse);
    });

    test('επιλεγμένο hybrid → απόρριψη', () async {
      final decision = await decideLampDbAdoption(
        pickedPath: r'C:\Data\mixed.db',
        destinationPath: r'D:\Portable\Data Base\mixed.db',
        classify: (_) async => DatabaseFileKind.hybrid,
        fileExists: (_) async => false,
      );

      expect(decision.allowed, isFalse);
      expect(decision.rejectionMessage, contains('mixed.db'));
    });
  });

  group('lampAdoptionKeepBothFileName', () {
    test('προσθέτει ημερομηνία και κρατά την κατάληξη', () {
      final name = lampAdoptionKeepBothFileName(
        directory: r'D:\Portable\Data Base',
        pickedPath: r'C:\Incoming\old_equipment 2.db',
        now: DateTime(2026, 7, 31, 14, 32),
        fileExists: (_) => false,
      );

      expect(name, 'old_equipment 2_31-07-2026.db');
    });

    test('κλιμακώνει σε ώρα όταν υπάρχει ομώνυμο της ίδιας ημέρας', () {
      final name = lampAdoptionKeepBothFileName(
        directory: r'D:\Portable\Data Base',
        pickedPath: r'C:\Incoming\lamp.db',
        now: DateTime(2026, 7, 31, 14, 32),
        fileExists: (path) => path.endsWith('lamp_31-07-2026.db'),
      );

      expect(name, 'lamp_31-07-2026_14-32.db');
    });
  });
}
