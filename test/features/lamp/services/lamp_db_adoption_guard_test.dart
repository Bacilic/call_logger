// Φύλαξη υιοθέτησης βάσης Λάμπας — απόρριψη callLogger/hybrid και επιβεβαίωση overwrite.
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
        expect(decision.requiresOverwriteConfirmation, isFalse);
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
        expect(decision.requiresOverwriteConfirmation, isFalse);
        expect(decision.rejectionMessage, contains('equipment.db'));
        expect(decision.rejectionMessage, contains('θα την κατέστρεφε'));
      },
    );

    test(
      'επιλεγμένο lamp με ομώνυμο προορισμό lamp → επιβεβαίωση overwrite',
      () async {
        final decision = await decideLampDbAdoption(
          pickedPath: r'C:\Incoming\old_equipment.db',
          destinationPath: r'D:\Portable\Data Base\old_equipment.db',
          classify: (_) async => DatabaseFileKind.lamp,
          fileExists: (_) async => true,
        );

        expect(decision.allowed, isTrue);
        expect(decision.requiresOverwriteConfirmation, isTrue);
        expect(decision.rejectionMessage, isNull);
      },
    );

    test(
      'επιλεγμένο lamp χωρίς υπάρχοντα προορισμό → επιτρέπεται χωρίς επιβεβαίωση',
      () async {
        final decision = await decideLampDbAdoption(
          pickedPath: r'C:\Incoming\lamp_new.db',
          destinationPath: r'D:\Portable\Data Base\lamp_new.db',
          classify: (_) async => DatabaseFileKind.lamp,
          fileExists: (_) async => false,
        );

        expect(decision.allowed, isTrue);
        expect(decision.requiresOverwriteConfirmation, isFalse);
        expect(decision.rejectionMessage, isNull);
      },
    );

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
}
