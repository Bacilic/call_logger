// Το ψευδώνυμο του υπαλλήλου: πού ζει, πού φαίνεται, τι ξεμπλοκάρει.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/user_nickname_test.dart

import 'package:call_logger/core/utils/name_parser.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/catalog_validation_finding.dart';
import 'package:call_logger/features/directory/models/catalog_validation_rules.dart';
import 'package:call_logger/features/directory/services/catalog_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = CatalogValidationService(
    CatalogValidationRules(emptyDepartmentEnabled: false),
  );

  group('Το ψευδώνυμο ταξιδεύει από και προς τη βάση', () {
    test('γράφεται και ξαναδιαβάζεται', () {
      final saved = UserModel(
        id: 1,
        lastName: 'Παπαγεωργίου',
        firstName: 'Γεωργία',
        nickname: 'Γωγώ',
      ).toMap();

      expect(saved['nickname'], 'Γωγώ');
      expect(UserModel.fromMap({...saved, 'id': 1}).nickname, 'Γωγώ');
    });

    test('το σβήσιμο φτάνει στη βάση ως κενό, δεν αγνοείται', () {
      // Χωρίς αυτό, η παλιά τιμή θα επιβίωνε σιωπηλά στην ενημέρωση.
      final cleared = UserModel(
        id: 1,
        lastName: 'Παπαγεωργίου',
        firstName: 'Γεωργία',
        nickname: '   ',
      ).toMap();

      expect(cleared.containsKey('nickname'), isTrue);
      expect(cleared['nickname'], isNull);
    });
  });

  group('Πώς εμφανίζεται', () {
    final gogo = UserModel(
      id: 1,
      lastName: 'Παπαγεωργίου',
      firstName: 'Γεωργία',
      nickname: 'Γωγώ',
      departmentName: 'Ακτινολογικό',
    );

    test('με ψευδώνυμο: μπαίνει μπροστά, σε παρένθεση', () {
      expect(gogo.nameWithNickname, '(Γωγώ) Γεωργία Παπαγεωργίου');
      expect(
        gogo.fullNameWithDepartment,
        '(Γωγώ) Γεωργία Παπαγεωργίου (Ακτινολογικό)',
      );
    });

    test('το σκέτο όνομα ΔΕΝ το κουβαλά — πάει σε Lansweeper και PDF', () {
      expect(gogo.name, 'Γεωργία Παπαγεωργίου');
    });

    test('χωρίς ψευδώνυμο: τίποτα δεν αλλάζει', () {
      final plain = UserModel(
        id: 2,
        lastName: 'Δρόσος',
        firstName: 'Βασίλης',
        departmentName: 'Πληροφορική',
      );

      expect(plain.nameWithNickname, 'Βασίλης Δρόσος');
      expect(plain.fullNameWithDepartment, 'Βασίλης Δρόσος (Πληροφορική)');
    });
  });

  group('Καθαρισμός του εμφανιζόμενου κειμένου', () {
    test('φεύγουν και το ψευδώνυμο μπροστά και το τμήμα πίσω', () {
      expect(
        NameParserUtility.stripDisplayDecorations(
          '(Γωγώ) Γεωργία Παπαγεωργίου (Ακτινολογικό)',
        ),
        'Γεωργία Παπαγεωργίου',
      );
    });

    test('σκέτο όνομα με τμήμα: όπως πάντα', () {
      expect(
        NameParserUtility.stripDisplayDecorations(
          'Βασίλης Δρόσος (Πληροφορική)',
        ),
        'Βασίλης Δρόσος',
      );
    });

    test('όνομα που είναι ΜΟΝΟ παρένθεση δεν εξαφανίζεται', () {
      expect(NameParserUtility.stripDisplayDecorations('(3π)'), '(3π)');
    });

    test('το επώνυμο ΔΕΝ χάνεται όταν το όνομα έχει παρένθεση στη μέση', () {
      // Με κόψιμο στην πρώτη « (» το αποτέλεσμα ήταν σκέτο «Βίκυ»: ο νέος
      // καλών θα δημιουργούνταν χωρίς επώνυμο.
      expect(
        NameParserUtility.stripDisplayDecorations(
          'Βίκυ (Βασιλική) Κίτσιου (Γραφείο Κίνησης)',
        ),
        'Βίκυ (Βασιλική) Κίτσιου',
      );
    });

    test('ο νέος καλών παίρνει το σωστό όνομα, όχι το ψευδώνυμο', () {
      final clean = NameParserUtility.stripDisplayDecorations(
        '(Σίσυ) Στεφανία Στεφανίδου (Γραμματεία)',
      );
      final parsed = NameParserUtility.parse(clean);

      expect(parsed.firstName, 'Στεφανία');
      expect(parsed.lastName, 'Στεφανίδου');
    });
  });

  group('Ο διαχωρισμός του ψευδωνύμου από το όνομα', () {
    test('«(Γωγώ) Γεωργία» χωρίζεται στα δύο', () {
      final split = NameParserUtility.splitNicknameFromName('(Γωγώ) Γεωργία');

      expect(split?.nickname, 'Γωγώ');
      expect(split?.name, 'Γεωργία');
    });

    test('χωρίς παρένθεση: τίποτα', () {
      expect(NameParserUtility.splitNicknameFromName('Γεωργία'), isNull);
    });

    test('παρένθεση χωρίς όνομα μετά: τίποτα', () {
      expect(NameParserUtility.splitNicknameFromName('(3π)'), isNull);
    });

    test('κενή παρένθεση: τίποτα', () {
      expect(NameParserUtility.splitNicknameFromName('() Γεωργία'), isNull);
    });

    test('«Βίκυ (Βασιλική)»: το ΑΝΤΙΣΤΡΟΦΟ σχήμα χωρίζεται κι αυτό', () {
      // Τρεις από τις τέσσερις εγγραφές της βάσης είναι γραμμένες έτσι.
      // Το ψευδώνυμο μένει το πρώτο, ό,τι κι αν περικλείει η παρένθεση.
      final split = NameParserUtility.splitNicknameFromName('Βίκυ (Βασιλική)');

      expect(split?.nickname, 'Βίκυ');
      expect(split?.name, 'Βασιλική');
    });

    test('και τα τέσσερα πραγματικά ονόματα της βάσης χωρίζονται', () {
      const real = {
        'Βίκυ (Βασιλική)': ('Βίκυ', 'Βασιλική'),
        '(Γωγώ) Γεωργία': ('Γωγώ', 'Γεωργία'),
        'Βάσω (Βασιλική)': ('Βάσω', 'Βασιλική'),
        'Νίκη (Νικολίτσα)': ('Νίκη', 'Νικολίτσα'),
      };
      for (final entry in real.entries) {
        final split = NameParserUtility.splitNicknameFromName(entry.key);
        expect(split?.nickname, entry.value.$1, reason: entry.key);
        expect(split?.name, entry.value.$2, reason: entry.key);
      }
    });
  });

  group('Ο κανόνας που εντοπίζει τα παλιά δεδομένα', () {
    List<CatalogValidationFinding> nicknameFindings(List<UserModel> users) {
      return service
          .scan(users: users, departments: const [], equipment: const [])
          .where((f) => f.fieldLabel == 'Ψευδώνυμο')
          .toList();
    }

    test('όνομα με ψευδώνυμο σε παρένθεση: εύρημα με τα δύο κομμάτια', () {
      final findings = nicknameFindings([
        UserModel(id: 1, lastName: 'Παπαγεωργίου', firstName: '(Γωγώ) Γεωργία'),
      ]);

      expect(findings, hasLength(1));
      expect(
        findings.single.message,
        'Το «Γωγώ» μοιάζει με ψευδώνυμο μέσα στο όνομα — '
        'με δικό του πεδίο, το όνομα μένει «Γεωργία»',
      );
      expect(findings.single.primary.focusedField, 'nickname');
    });

    test('ΚΑΙ ΤΑ ΤΕΣΣΕΡΑ ονόματα της βάσης δίνουν εύρημα', () {
      final findings = nicknameFindings([
        UserModel(id: 1, lastName: 'Κίτσιου', firstName: 'Βίκυ (Βασιλική)'),
        UserModel(id: 4, lastName: 'Παπαγεωργίου', firstName: '(Γωγώ) Γεωργία'),
        UserModel(id: 34, lastName: 'Λιάκη', firstName: 'Βάσω (Βασιλική)'),
        UserModel(id: 35, lastName: 'Ρούσση', firstName: 'Νίκη (Νικολίτσα)'),
      ]);

      expect(findings, hasLength(4));
    });

    test('με συμπληρωμένο πεδίο: κανένα εύρημα — η μεταφορά έγινε', () {
      final findings = nicknameFindings([
        UserModel(
          id: 1,
          lastName: 'Παπαγεωργίου',
          firstName: '(Γωγώ) Γεωργία',
          nickname: 'Γωγώ',
        ),
      ]);

      expect(findings, isEmpty);
    });

    test('σβηστός διακόπτης: κανένα εύρημα', () {
      const off = CatalogValidationService(
        CatalogValidationRules(
          emptyDepartmentEnabled: false,
          nicknameInNameEnabled: false,
        ),
      );
      final findings = off
          .scan(
            users: [
              UserModel(
                id: 1,
                lastName: 'Παπαγεωργίου',
                firstName: '(Γωγώ) Γεωργία',
              ),
            ],
            departments: const [],
            equipment: const [],
          )
          .where((f) => f.fieldLabel == 'Ψευδώνυμο')
          .toList();

      expect(findings, isEmpty);
    });
  });

  group('Το διπλότυπο που σήμερα χάνεται', () {
    test('με χωρισμένο ψευδώνυμο, ο έλεγχος πιάνει το ίδιο πρόσωπο', () {
      final findings = service
          .scan(
            users: [
              UserModel(id: 1, lastName: 'Παπαγεωργίου', firstName: 'Γεωργία'),
              UserModel(
                id: 2,
                lastName: 'Παπαγεωργίου',
                firstName: 'Γεωργία',
                nickname: 'Γωγώ',
              ),
            ],
            departments: const [],
            equipment: const [],
          )
          .where((f) => f.type == CatalogFindingType.nameConflict)
          .toList();

      expect(findings, hasLength(1));
      expect(findings.single.records, hasLength(2));
    });
  });
}
