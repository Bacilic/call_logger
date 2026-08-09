// Αρίθμηση σειράς σε διπλότυπους σειριακούς.
//
// Οι τιμές είναι αληθινές, από τη Λάμπα: το barcode `NLSHR125070` σε 20
// scanner, το κλειδί `3XNJY-…` σε 20 υπολογιστές, η σειρά
// `10NXMP0026001-1 … -10` που φτιάχτηκε ήδη χειροκίνητα, και τα τέσσερα
// πληκτρολόγια Dell με σειριακό σκέτη παύλα.
//
//   flutter test test/core/database/old_database/lamp_serial_series_test.dart

import 'package:call_logger/core/database/old_database/lamp_serial_series.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  group('αρίθμηση', () {
    test('η σειρά ξεκινά από το 1 και ακολουθεί τον κωδικό', () {
      final plan = lampBuildSerialSeries(
        template: 'NLSHR125070-$kLampSeriesCounterToken',
        // Δίνονται ανακατεμένοι: η σειρά πρέπει να προκύψει, όχι να δοθεί.
        equipmentCodes: <int>[3822, 3818, 3820],
        takenSerials: <String>['NLSHR125070'],
      );

      expect(plan.assignments.map((a) => a.code), <int>[3818, 3820, 3822]);
      expect(
        plan.assignments.map((a) => a.serial),
        <String>['NLSHR125070-1', 'NLSHR125070-2', 'NLSHR125070-3'],
        reason: greekExpectMsg(
          'Η υπάρχουσα σειρά της βάσης δεν έχει γυμνό πρώτο — όλες οι '
          'εγγραφές παίρνουν αριθμό',
        ),
      );
    });

    test('ελεύθερο πρότυπο με τον τελεστή οπουδήποτε', () {
      final plan = lampBuildSerialSeries(
        template: 'Πληκτρολόγιο USB Dell (61)-$kLampSeriesCounterToken',
        equipmentCodes: <int>[789, 790],
        takenSerials: const <String>[],
      );

      expect(plan.assignments.map((a) => a.serial), <String>[
        'Πληκτρολόγιο USB Dell (61)-1',
        'Πληκτρολόγιο USB Dell (61)-2',
      ]);
    });

    test('προσπερνά αριθμούς που κρατά ήδη άλλο μηχάνημα', () {
      final plan = lampBuildSerialSeries(
        template: '5210131128244-$kLampSeriesCounterToken',
        equipmentCodes: <int>[100, 200],
        takenSerials: <String>['5210131128244-1', '5210131128244-3'],
      );

      expect(
        plan.assignments.map((a) => a.serial),
        <String>['5210131128244-2', '5210131128244-4'],
        reason: greekExpectMsg(
          'Η μοναδικότητα ισχύει ανά μοντέλο· πατώντας κατειλημμένο αριθμό '
          'η εγγραφή θα αποτύγχανε στη μέση της συναλλαγής',
        ),
      );
    });

    test('συνεχίζει υπάρχουσα σειρά και το λέει', () {
      final plan = lampBuildSerialSeries(
        template: '10NXMP0026001-$kLampSeriesCounterToken',
        equipmentCodes: <int>[500],
        takenSerials: <String>[
          for (var i = 1; i <= 10; i++) '10NXMP0026001-$i',
        ],
      );

      expect(plan.assignments.single.serial, '10NXMP0026001-11');
      expect(plan.continuationNote, contains('1 έως 10'));
      expect(plan.continuationNote, contains('συνεχίζει από το 11'));
    });

    test('χωρίς υπάρχουσα σειρά δεν λέει τίποτα', () {
      final plan = lampBuildSerialSeries(
        template: 'NLSHR125070-$kLampSeriesCounterToken',
        equipmentCodes: <int>[1, 2],
        takenSerials: const <String>[],
      );

      expect(plan.continuationNote, isNull);
    });

    test('πρότυπο χωρίς τελεστή δεν παράγει τίποτα', () {
      final plan = lampBuildSerialSeries(
        template: 'NLSHR125070',
        equipmentCodes: <int>[1, 2],
        takenSerials: const <String>[],
      );

      expect(
        plan.isEmpty,
        isTrue,
        reason: greekExpectMsg(
          'Χωρίς τον τελεστή και οι δύο εγγραφές θα έπαιρναν την ίδια τιμή '
          'και το διπλότυπο θα έμενε ακέραιο, απλώς με άλλο κείμενο',
        ),
      );
      expect(lampSeriesTemplateIsValid('NLSHR125070'), isFalse);
      expect(
        lampSeriesTemplateIsValid('NLSHR125070-$kLampSeriesCounterToken'),
        isTrue,
      );
    });
  });

  group('πρόταση προτύπου', () {
    test('με χρήσιμο σειριακό χτίζεται πάνω του', () {
      expect(
        lampSuggestedSeriesTemplate(
          serial: 'NLSHR125070',
          modelName: 'Hand Held Barcode Scanner',
          modelId: 554,
        ),
        'NLSHR125070-$kLampSeriesCounterToken',
      );
    });

    test('με σκέτη παύλα μπαίνει το μοντέλο', () {
      expect(
        lampSuggestedSeriesTemplate(
          serial: '-',
          modelName: 'Πληκτρολόγιο USB Dell',
          modelId: 61,
        ),
        'Πληκτρολόγιο USB Dell (61)-$kLampSeriesCounterToken',
        reason: greekExpectMsg(
          'Η παύλα ως αφετηρία παρήγαγε «--1»· η σύμβαση του νοσοκομείου '
          'βάζει το μοντέλο στη θέση του σειριακού που λείπει',
        ),
      );
    });

    test('όταν ούτε το μοντέλο λέει κάτι, μένει το αναγνωριστικό', () {
      expect(
        lampSuggestedSeriesTemplate(serial: '-', modelName: '-', modelId: 60),
        '60-$kLampSeriesCounterToken',
      );
    });

    test('σειριακός που ανήκει ήδη σε σειρά δίνει τη ρίζα', () {
      expect(
        lampSuggestedSeriesTemplate(serial: '10NXMP0026001-7'),
        '10NXMP0026001-$kLampSeriesCounterToken',
      );
    });
  });

  group('τιμές που δεν λένε τίποτα', () {
    test('παύλα, τελεία, κενό, πολύ κοντά', () {
      expect(lampSerialIsPlaceholder('-'), isTrue);
      expect(lampSerialIsPlaceholder('  '), isTrue);
      expect(lampSerialIsPlaceholder('.'), isTrue);
      expect(lampSerialIsPlaceholder('0'), isTrue);
      expect(lampSerialIsPlaceholder(null), isTrue);
      expect(lampSerialIsPlaceholder('AB'), isTrue);
    });

    test('πραγματικός σειριακός δεν είναι κενός', () {
      expect(lampSerialIsPlaceholder('NLSHR125070'), isFalse);
      expect(lampSerialIsPlaceholder('0317'), isFalse);
    });
  });

  group('αναγνώριση σειράς', () {
    test('παύλα και παρένθεση', () {
      expect(lampSerialSeriesMember('10NXMP0026001-7')?.root, '10NXMP0026001');
      expect(lampSerialSeriesMember('10NXMP0026001-7')?.index, 7);
      expect(lampSerialSeriesMember('MX-B427W (2)')?.root, 'MX-B427W');
      expect(lampSerialSeriesMember('MX-B427W (2)')?.index, 2);
    });

    test('σειριακός με παύλες που ΔΕΝ είναι σειρά', () {
      expect(
        lampSerialSeriesMember('CN-03H7YR-LO300-787-03UV-A03'),
        isNull,
        reason: greekExpectMsg(
          'Το τελευταίο τμήμα δεν είναι σκέτος αριθμός — αλλιώς κάθε '
          'σειριακός της Dell θα θεωρούνταν σειρά',
        ),
      );
      expect(lampSerialSeriesMember('NLSHR125070'), isNull);
    });

    test('το «29-352-20250306-1» είναι σειρά με σύνθετη ρίζα', () {
      final member = lampSerialSeriesMember('29-352-20250306-1');
      expect(member?.root, '29-352-20250306');
      expect(member?.index, 1);
    });
  });

  group('κλειδιά αδειών', () {
    test('το πρότυπο πέντε πεντάδων αναγνωρίζεται', () {
      expect(
        lampSerialLooksLikeLicenseKey(
          serial: '3XNJY-9J4GT-Y7DJ8-9R98M-XBT6Y',
        ),
        isTrue,
        reason: greekExpectMsg(
          'Είκοσι υπολογιστές με την ίδια volume license δεν είναι σφάλμα· '
          'η αρίθμηση θα κατέστρεφε την πληροφορία',
        ),
      );
    });

    test('το μοντέλο μαρτυρά λογισμικό', () {
      expect(
        lampSerialLooksLikeLicenseKey(
          serial: 'Δυσανάγνωστος',
          modelName: 'Windows XP Pro',
        ),
        isTrue,
      );
    });

    test('barcode προϊόντος δεν είναι άδεια', () {
      expect(
        lampSerialLooksLikeLicenseKey(
          serial: '8716309093675',
          modelName: 'KB-103',
          categoryName: 'Περιφερειακό',
        ),
        isFalse,
      );
    });
  });
}
