// Τι λέει η γραμμή κάτω από τον «Φάκελο ελέγχου ενημερώσεων».
//
// Το πεδίο δείχνει την ΕΝΕΡΓΗ διαδρομή, όχι τη ρύθμιση: με κενή κοινή ρύθμιση
// γεμίζει από τον φάκελο εγκατάστασης αυτού του υπολογιστή. Οι δύο περιπτώσεις
// μοιάζουν ίδιες στην οθόνη και δεν είναι — η μία αφορά όλους, η άλλη ένα
// μηχάνημα. Εδώ φυλάγεται ακριβώς αυτή η διάκριση.
//
//   flutter test test/features/settings/update_folder_hint_test.dart

import 'package:call_logger/features/settings/utils/update_folder_hint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateFolderHint.forState', () {
    test('αποθηκευμένη ρύθμιση: λέει ότι αφορά όλους', () {
      final text = UpdateFolderHint.forState(
        fieldValue: r'\\server\updates',
        installerFolder: r'C:\Setup',
        hasSavedSetting: true,
      );

      expect(text, UpdateFolderHint.sharedAcrossMachines);
      expect(
        text,
        isNot(contains(r'C:\Setup')),
        reason:
            'Όσο η ρύθμιση έχει τιμή, ο φάκελος εγκατάστασης δεν παίζει '
            'κανέναν ρόλο — δεν διαβάζεται καν.',
      );
    });

    test('ίδια διαδρομή ΧΩΡΙΣ αποθηκευμένη ρύθμιση: δεν αφορά όλους', () {
      final text = UpdateFolderHint.forState(
        fieldValue: r'C:\Setup',
        installerFolder: r'C:\Setup',
        hasSavedSetting: false,
      );

      expect(text, UpdateFolderHint.fromInstallerNotSaved);
      expect(
        text,
        isNot(UpdateFolderHint.sharedAcrossMachines),
        reason:
            'Η τιμή φαίνεται ίδια με ρύθμιση, αλλά κανείς δεν την όρισε — '
            'το να πούμε «ισχύει για όλους» θα ήταν ψέμα.',
      );
    });

    test('κενό πεδίο με καταγεγραμμένη εγκατάσταση: δείχνει τη διαδρομή', () {
      final text = UpdateFolderHint.forState(
        fieldValue: '',
        installerFolder: r'C:\Users\Bacilic\Desktop\Updates',
        hasSavedSetting: false,
      );

      expect(text, contains(r'C:\Users\Bacilic\Desktop\Updates'));
      expect(text, contains('εγκαταστάθηκε'));
    });

    test('κενό πεδίο χωρίς εγκατάσταση: λέει ότι δεν θα γίνει έλεγχος', () {
      expect(
        UpdateFolderHint.forState(
          fieldValue: '',
          installerFolder: null,
          hasSavedSetting: false,
        ),
        UpdateFolderHint.noSourceAtAll,
      );
    });

    test('μόνο κενά στο πεδίο μετρούν ως κενό', () {
      expect(
        UpdateFolderHint.forState(
          fieldValue: '   ',
          installerFolder: null,
          hasSavedSetting: false,
        ),
        UpdateFolderHint.noSourceAtAll,
      );
    });

    test('κενός φάκελος εγκατάστασης ισοδυναμεί με ανύπαρκτο', () {
      expect(
        UpdateFolderHint.forState(
          fieldValue: '',
          installerFolder: '  ',
          hasSavedSetting: false,
        ),
        UpdateFolderHint.noSourceAtAll,
      );
    });

    test('πουθενά δεν αναφέρεται το όνομα του αρχείου', () {
      final states = [
        UpdateFolderHint.forState(
          fieldValue: 'x',
          installerFolder: null,
          hasSavedSetting: true,
        ),
        UpdateFolderHint.forState(
          fieldValue: 'x',
          installerFolder: 'x',
          hasSavedSetting: false,
        ),
        UpdateFolderHint.forState(
          fieldValue: '',
          installerFolder: r'C:\a',
          hasSavedSetting: false,
        ),
        UpdateFolderHint.forState(
          fieldValue: '',
          installerFolder: null,
          hasSavedSetting: false,
        ),
      ];

      for (final text in states) {
        expect(
          text,
          isNot(contains('update_source.json')),
          reason:
              'Το όνομα του αρχείου δεν λέει τίποτα σε όποιον δεν ξέρει τι '
              'είναι — η θέση του δεν βοηθά, η προέλευσή του ναι.',
        );
      }
    });
  });

  group('UpdateFolderHint.isNoSourceState', () {
    test('αληθές μόνο όταν δεν υπάρχει καμία πηγή', () {
      expect(
        UpdateFolderHint.isNoSourceState(fieldValue: '', installerFolder: null),
        isTrue,
      );
      expect(
        UpdateFolderHint.isNoSourceState(
          fieldValue: '',
          installerFolder: r'C:\a',
        ),
        isFalse,
      );
      expect(
        UpdateFolderHint.isNoSourceState(
          fieldValue: 'x',
          installerFolder: null,
        ),
        isFalse,
      );
    });
  });
}
