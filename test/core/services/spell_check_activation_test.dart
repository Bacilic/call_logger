// Ο ορθογραφικός έλεγχος χωρίς λεξικό-πυρήνα: προειδοποίηση, ποτέ απαγόρευση.
//
// Ο χρήστης μπορεί να θέλει να χτίσει προσωπικό λεξικό από το μηδέν — νόμιμη
// χρήση. Αυτό που δεν επιτρέπεται είναι να μείνει ο διακόπτης αναμμένος μετά
// την αφαίρεση του πυρήνα, υπογραμμίζοντας σχεδόν κάθε λέξη σαν βλάβη.
//
//   flutter test test/core/services/spell_check_activation_test.dart

import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/core/services/spell_check_activation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('πότε προειδοποιούμε', () {
    test('άναμμα χωρίς πυρήνα: ναι', () {
      expect(
        shouldWarnEnablingSpellCheck(
          turningOn: true,
          coreLexiconLoaded: false,
        ),
        isTrue,
      );
    });

    test('άναμμα με φορτωμένο πυρήνα: όχι', () {
      expect(
        shouldWarnEnablingSpellCheck(turningOn: true, coreLexiconLoaded: true),
        isFalse,
        reason: 'Με λεξικό η ρύθμιση κάνει ακριβώς ό,τι υπόσχεται.',
      );
    });

    test('σβήσιμο: ποτέ, με ή χωρίς πυρήνα', () {
      expect(
        shouldWarnEnablingSpellCheck(
          turningOn: false,
          coreLexiconLoaded: false,
        ),
        isFalse,
      );
      expect(
        shouldWarnEnablingSpellCheck(turningOn: false, coreLexiconLoaded: true),
        isFalse,
      );
    });
  });

  group('το κείμενο κάτω από τον διακόπτη', () {
    test('χωρίς πυρήνα λέει τι θα δει ο χρήστης', () {
      final text = spellCheckSubtitle(coreLexiconLoaded: false);

      expect(text, contains('λεξικό-πυρήνας'));
      expect(
        text,
        contains('προσωπικού'),
        reason:
            'Πρέπει να λέει ΚΑΙ τι εξακολουθεί να δουλεύει, αλλιώς μοιάζει '
            'με βλάβη αντί για επιλογή.',
      );
    });

    test('με πυρήνα δεν αναφέρει καθόλου το πρόβλημα', () {
      final text = spellCheckSubtitle(coreLexiconLoaded: true);

      expect(text, isNot(contains('Δεν έχει φορτωθεί')));
    });
  });

  group('η απενεργοποίηση αφήνει συνεπή κατάσταση', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('σβήνει τον έλεγχο ΚΑΙ την προβολή του Λεξικού', () async {
      final settings = SettingsService();
      await settings.windowUi.setEnableSpellCheck(true);
      await settings.windowUi.setShowDictionaryNav(true);

      await SpellCheckActivation.disable(settings);

      expect(await settings.windowUi.getEnableSpellCheck(), isFalse);
      expect(
        await settings.windowUi.getShowDictionaryNav(),
        isFalse,
        reason:
            'Η αποθηκευμένη ρύθμιση δεν επιτρέπεται να λέει άλλα από αυτά που '
            'δείχνει η οθόνη — το «Λεξικό» κρύβεται όσο ο έλεγχος είναι κλειστός.',
      );
    });

    test('είναι αδιάφορη στην αρχική κατάσταση', () async {
      final settings = SettingsService();
      await settings.windowUi.setEnableSpellCheck(false);
      await settings.windowUi.setShowDictionaryNav(false);

      await SpellCheckActivation.disable(settings);

      expect(await settings.windowUi.getEnableSpellCheck(), isFalse);
      expect(await settings.windowUi.getShowDictionaryNav(), isFalse);
    });
  });
}
