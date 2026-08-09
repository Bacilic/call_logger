// Οντότητες της Λάμπας χωρίς συνδεδεμένο εξοπλισμό.
//
// Συμβόλαιο (Διευθυντής 08/08/2026): «ΟΛΗ η πληροφορία στη βάση είναι
// αναζητήσιμη· τίποτα δεν αποκλείεται».
//
// Το σενάριο-σπόρος: αναζήτηση «Διευθυντής Αιματολογικού» (γραφείο 186, μηδέν
// εξοπλισμός) απαντούσε «δεν αντιστοιχεί σε καμία εγγραφή στη βάση της
// Λάμπας». Μέτρηση στη lampa.db: 360 τέτοιες εγγραφές, ανάμεσά τους 202
// ιδιοκτήτες — 40% του προσωπικού — με τηλέφωνα που δεν βρίσκονταν ποτέ.
//
//   flutter test test/core/database/old_database/lamp_unlinked_entities_test.dart

import 'package:call_logger/core/database/old_database/lamp_unlinked_entities.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  /// Ό,τι πληκτρολογεί ο χρήστης περνά πρώτα από την ίδια κανονικοποίηση με το
  /// ευρετήριο (τόνοι, τελικό «ς» → «σ»). Τα τεστ μιμούνται αυτή τη ροή.
  String q(String typed) => SearchTextNormalizer.normalizeForSearch(typed);

  // Πραγματική γραμμή της lampa.db: το γραφείο που δεν βρισκόταν με τίποτα.
  Map<String, Object?> officeRow186() => <String, Object?>{
    'id': 186,
    'office_name': 'Διευθυντής Αιματολογικού',
    'department_name': 'Αιματολογικό Εργαστήριο',
    'organization_name': 'Εργαστηριακός τομέας',
    'building': 'Β',
    'level': 1,
    'phones': null,
    'e_mail': null,
  };

  Map<String, Object?> ownerRow() => <String, Object?>{
    'id': 2891,
    'last_name': 'Τσουκαλά',
    'first_name': 'Δήμητρα',
    'phones': '2514',
    'e_mail': null,
    'office_name': 'Αιματολογικό Εργαστήριο',
    'department_name': 'Αιματολογικό Εργαστήριο',
  };

  group('χτίσιμο οντότητας', () {
    test('γραφείο: τίτλος το όνομα του γραφείου, όχι το τμήμα', () {
      final entity = buildLampUnlinkedEntity(
        LampUnlinkedEntityKind.office,
        officeRow186(),
      )!;

      expect(
        entity.title,
        'Διευθυντής Αιματολογικού',
        reason: greekExpectMsg(
          'Το τμήμα το μοιράζονται πέντε γραφεία — ως τίτλος δεν ξεχωρίζει '
          'κανένα',
        ),
      );
      expect(entity.subtitle, contains('τμήμα=Αιματολογικό Εργαστήριο'));
      expect(entity.id, 186);
    });

    test('ιδιοκτήτης: επώνυμο και όνομα μαζί', () {
      final entity = buildLampUnlinkedEntity(
        LampUnlinkedEntityKind.owner,
        ownerRow(),
      )!;

      expect(entity.title, 'Τσουκαλά Δήμητρα');
      expect(entity.subtitle, contains('τηλέφωνα=2514'));
    });

    test('γραμμή χωρίς αναγνωριστικό απορρίπτεται αντί να σκάσει', () {
      expect(
        buildLampUnlinkedEntity(LampUnlinkedEntityKind.office, <String, Object?>{
          'office_name': 'Κάπου',
        }),
        isNull,
      );
    });
  });

  group('αναζήτηση ελεύθερου κειμένου', () {
    test('βρίσκεται με το όνομά του — το αρχικό σφάλμα', () {
      final entity = buildLampUnlinkedEntity(
        LampUnlinkedEntityKind.office,
        officeRow186(),
      )!;

      expect(
        lampNormalizedTextContainsAll(
          entity.normalizedText,
          q('Διευθυντής Αιματολογικού'),
        ),
        isTrue,
        reason: greekExpectMsg(
          'Αυτή ακριβώς η αναζήτηση απαντούσε «δεν αντιστοιχεί σε καμία '
          'εγγραφή στη βάση»',
        ),
      );
    });

    test('βρίσκεται και με το αναγνωριστικό του', () {
      final entity = buildLampUnlinkedEntity(
        LampUnlinkedEntityKind.office,
        officeRow186(),
      )!;

      expect(
        lampNormalizedTextContainsAll(entity.normalizedText, '186'),
        isTrue,
        reason: greekExpectMsg(
          'Ο χρήστης βλέπει αναγνωριστικά στους διαλόγους επίλυσης και τα '
          'ψάχνει αυτούσια',
        ),
      );
    });

    test('το τηλέφωνο του ιδιοκτήτη είναι αναζητήσιμο', () {
      final entity = buildLampUnlinkedEntity(
        LampUnlinkedEntityKind.owner,
        ownerRow(),
      )!;

      expect(
        lampNormalizedTextContainsAll(entity.normalizedText, '2514'),
        isTrue,
        reason: greekExpectMsg(
          '310 ιδιοκτήτες έχουν τηλέφωνο και οι 202 ήταν αόρατοι στο φίλτρο',
        ),
      );
    });
  });

  group('αναζήτηση ανά πεδίο', () {
    late LampUnlinkedEntity office;
    late LampUnlinkedEntity owner;

    setUp(() {
      office = buildLampUnlinkedEntity(
        LampUnlinkedEntityKind.office,
        officeRow186(),
      )!;
      owner = buildLampUnlinkedEntity(
        LampUnlinkedEntityKind.owner,
        ownerRow(),
      )!;
    });

    test('το πεδίο Τμήμα φέρνει γραφεία, όχι ιδιοκτήτες', () {
      final filters = <String, String>{'office': q('Διευθυντής')};

      expect(lampUnlinkedMatchesFields(office, filters), isTrue);
      expect(
        lampUnlinkedMatchesFields(owner, filters),
        isFalse,
        reason: greekExpectMsg(
          'Το πεδίο «Τμήμα» ζητά γραφεία — ιδιοκτήτης εκεί είναι θόρυβος',
        ),
      );
    });

    test('το πεδίο Υπάλληλος φέρνει ιδιοκτήτες, όχι γραφεία', () {
      final filters = <String, String>{'owner': q('Τσουκαλά')};

      expect(lampUnlinkedMatchesFields(owner, filters), isTrue);
      expect(lampUnlinkedMatchesFields(office, filters), isFalse);
    });

    test('το τηλέφωνο αφορά και ιδιοκτήτες και γραφεία', () {
      expect(
        lampUnlinkedMatchesFields(owner, <String, String>{'phone': '2514'}),
        isTrue,
      );
      expect(
        kLampUnlinkedFieldKinds['phone'],
        containsAll(<LampUnlinkedEntityKind>[
          LampUnlinkedEntityKind.owner,
          LampUnlinkedEntityKind.office,
        ]),
      );
    });

    test('πεδίο αποκλειστικά εξοπλισμού αποκλείει κάθε ασύνδετη', () {
      for (final field in kLampEquipmentOnlySearchFields) {
        expect(
          lampUnlinkedMatchesFields(office, <String, String>{field: 'κατι'}),
          isFalse,
          reason: greekExpectMsg(
            'Το πεδίο «$field» υπάρχει μόνο πάνω σε εξοπλισμό — καμία '
            'ασύνδετη οντότητα δεν μπορεί να του απαντήσει',
          ),
        );
      }
    });

    test('συνδυασμός πεδίων: ένα εξοπλισμού μηδενίζει τα ασύνδετα', () {
      expect(
        lampUnlinkedMatchesFields(office, <String, String>{
          'office': q('Διευθυντής'),
          'code': '5005',
        }),
        isFalse,
      );
    });

    test('χωρίς κανένα φίλτρο δεν επιστρέφεται τίποτα', () {
      expect(lampUnlinkedMatchesFields(office, const <String, String>{}), isFalse);
    });
  });

  group('SQL ερωτημάτων', () {
    test('καλύπτονται και οι τέσσερις πίνακες αναφοράς', () {
      expect(
        kLampUnlinkedEntitySql.keys.toSet(),
        LampUnlinkedEntityKind.values.toSet(),
      );
    });

    // Χωρίς αυτό, το `NOT IN` της SQLite επιστρέφει πάντα κενό σύνολο μόλις
    // το υποερώτημα περιέχει έστω ένα NULL — και η λίστα βγαίνει σιωπηλά άδεια.
    test('κάθε υποερώτημα φιλτράρει τα NULL', () {
      for (final entry in kLampUnlinkedEntitySql.entries) {
        expect(
          entry.value,
          contains('IS NOT NULL'),
          reason: greekExpectMsg(
            'Το ερώτημα για ${entry.key.pluralLabel} θα έβγαζε πάντα κενό',
          ),
        );
      }
    });
  });
}
