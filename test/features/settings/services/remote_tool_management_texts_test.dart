// Καθαρή λογική και κείμενα διαχείρισης απομακρυσμένων εργαλείων.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/settings/services/remote_tool_management_texts_test.dart

import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/settings/services/remote_tool_management_texts.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteTool _tool(String name, {List<RemoteToolArgument> arguments = const []}) {
  return RemoteTool(
    id: 1,
    name: name,
    role: ToolRole.vnc,
    executablePath: r'C:\vnc.exe',
    sortOrder: 1,
    isActive: true,
    arguments: arguments,
  );
}

void main() {
  group('Σύνοψη ορισμάτων λίστας', () {
    test('απόκρυψη κωδικού στη σύνοψη λίστας', () {
      final tool = _tool(
        'VNC Test',
        arguments: const [
          RemoteToolArgument(value: '-password=pass99', isActive: true),
        ],
      );

      expect(remoteToolArgumentsSummary(tool), '-password=***');
    });
  });

  group('Θέση μετά από αναδιάταξη', () {
    test('μετακίνηση προς τα κάτω: newIndex > oldIndex αφαιρεί 1', () {
      expect(reorderedPositionOneBased(0, 2), 2);
      expect(reorderedPositionOneBased(0, 4), 4);
      expect(reorderedPositionOneBased(1, 3), 3);
    });

    test('μετακίνηση προς τα πάνω: newIndex <= oldIndex → newIndex + 1', () {
      expect(reorderedPositionOneBased(3, 0), 1);
      expect(reorderedPositionOneBased(2, 1), 2);
      expect(reorderedPositionOneBased(2, 2), 3);
    });

    test('από αρχή στο τέλος και αντίστροφα', () {
      expect(reorderedPositionOneBased(0, 5), 5);
      expect(reorderedPositionOneBased(4, 0), 1);
    });
  });

  group('Όνομα αντιγράφου', () {
    test('ελεύθερο όνομα: σκέτη κατάληξη «(αντίγραφο)»', () {
      final name = uniqueRemoteToolCloneName('AnyDesk', [_tool('AnyDesk')]);

      expect(name, 'AnyDesk (αντίγραφο)');
    });

    test('πιασμένο αντίγραφο: αρίθμηση από το 2', () {
      final name = uniqueRemoteToolCloneName('AnyDesk', [
        _tool('AnyDesk'),
        _tool('AnyDesk (αντίγραφο)'),
      ]);

      expect(name, 'AnyDesk (αντίγραφο) 2');
    });

    test('η σύγκριση αγνοεί πεζά/κεφαλαία και κενά στις άκρες', () {
      final name = uniqueRemoteToolCloneName('AnyDesk', [
        _tool('  anydesk (αντίγραφο)  '),
      ]);

      expect(name, 'AnyDesk (αντίγραφο) 2');
    });
  });

  group('Υπόδειξη χρήσης ως προεπιλογή', () {
    test('κανένας, ένας και πολλοί εξοπλισμοί', () {
      expect(remoteToolUsageTooltip(0), contains('κανέναν'));
      expect(remoteToolUsageTooltip(1), 'Ενεργοποιημένο σε 1 εξοπλισμό.');
      expect(remoteToolUsageTooltip(4), 'Ενεργοποιημένο σε 4 εξοπλισμούς.');
    });
  });

  group('Απενεργοποίηση', () {
    test('ενικός και πληθυντικός στην ερώτηση', () {
      expect(remoteToolDeactivationQuestion(1), contains('σε 1 εξοπλισμό.'));
      expect(remoteToolDeactivationQuestion(3), contains('σε 3 εξοπλισμούς.'));
    });

    test('ο καθησυχασμός ονομάζει το εργαλείο', () {
      expect(
        remoteToolDeactivationReassurance('AnyDesk'),
        contains('«AnyDesk»'),
      );
    });
  });

  group('Ετικέτα εξοπλισμού με χειροκίνητο στόχο', () {
    test('συνθέτει «κωδικός (στόχος)»', () {
      expect(
        equipmentManualTargetLabel('1001', '123456789'),
        '1001 (123456789)',
      );
    });

    test('χωρίς στόχο μένει μόνο ο κωδικός', () {
      expect(equipmentManualTargetLabel('1001', '   '), '1001');
    });

    test('χωρίς κωδικό δείχνει παύλα αντί για κενό', () {
      expect(equipmentManualTargetLabel('  ', '10.0.0.5'), '— (10.0.0.5)');
    });
  });

  group('Γραμμή προεπιλογής στην απομάκρυνση', () {
    test('κανένας εξοπλισμός: σκέτη ερώτηση απομάκρυνσης', () {
      final line = remoteToolRemovalDefaultUsageLine(
        toolName: 'AnyDesk',
        defaultUsageCount: 0,
      );

      expect(line, 'Να απομακρυνθεί από τη λίστα το εργαλείο «AnyDesk»;');
    });

    test('ένας εξοπλισμός: ενικός', () {
      final line = remoteToolRemovalDefaultUsageLine(
        toolName: 'AnyDesk',
        defaultUsageCount: 1,
      );

      expect(line, contains('σε 1 εξοπλισμό.'));
    });

    test('πολλοί εξοπλισμοί: πληθυντικός με το πλήθος', () {
      final line = remoteToolRemovalDefaultUsageLine(
        toolName: 'AnyDesk',
        defaultUsageCount: 7,
      );

      expect(line, contains('σε 7 εξοπλισμούς.'));
    });
  });

  group('Γραμμή εξοπλισμών με χειροκίνητο στόχο', () {
    test('κενή λίστα: καμία γραμμή', () {
      expect(remoteToolManualTargetsLine(const []), isNull);
    });

    test('ένας: ενικός με το όνομά του', () {
      final line = remoteToolManualTargetsLine(const ['1001 (123456789)']);

      expect(line, contains('Υπάρχει 1 εξοπλισμός'));
      expect(line, contains('• 1001 (123456789)'));
    });

    test('πέντε: όλοι ονομαστικά, χωρίς «ακόμη»', () {
      final labels = [for (var i = 1; i <= 5; i++) '100$i (τιμή$i)'];

      final line = remoteToolManualTargetsLine(labels)!;

      expect(line, contains('Υπάρχουν 5 εξοπλισμοί'));
      for (final label in labels) {
        expect(line, contains('• $label'));
      }
      expect(line, isNot(contains('ακόμη')));
    });

    test('έξι: πέντε ονομαστικά και ο έκτος ως υπόλοιπο', () {
      final labels = [for (var i = 1; i <= 6; i++) '100$i (τιμή$i)'];

      final line = remoteToolManualTargetsLine(labels)!;

      expect(line, contains('Υπάρχουν 6 εξοπλισμοί'));
      expect(line, contains('• 1005 (τιμή5)'));
      expect(line, isNot(contains('1006')));
      expect(line, contains('• +1 ακόμη'));
    });
  });
}
