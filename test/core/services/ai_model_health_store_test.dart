// Η υγεία των μοντέλων ΤΝ, γραμμένη και ξαναδιαβασμένη από τον υπολογιστή.
//
//   flutter test test/core/services/ai_model_health_store_test.dart

import 'package:call_logger/core/services/ai_model_cooldown_registry.dart';
import 'package:call_logger/core/services/ai_model_health_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Αποθήκευση και ανάγνωση', () {
    test('ό,τι γράφτηκε ξαναδιαβάζεται ίδιο', () {
      final entries = [
        AiModelDowntime(
          model: 'gemini-flash-latest',
          until: DateTime(2026, 1, 1, 12, 34, 0),
          reason: AiModelDownReason.quotaExhausted,
          blocking: true,
        ),
        AiModelDowntime(
          model: 'lathos-onoma',
          until: DateTime(2026, 1, 1, 12, 10, 0),
          reason: AiModelDownReason.modelNotFound,
          blocking: false,
        ),
      ];

      final restored = decodeAiModelDowntimes(encodeAiModelDowntimes(entries));

      expect(restored, hasLength(2));
      expect(restored.first.model, 'gemini-flash-latest');
      expect(restored.first.until, DateTime(2026, 1, 1, 12, 34, 0));
      expect(restored.first.reason, AiModelDownReason.quotaExhausted);
      expect(restored.first.blocking, isTrue);
      expect(restored.last.reason, AiModelDownReason.modelNotFound);
      expect(restored.last.blocking, isFalse);
    });

    test('η αιτία επιβιώνει — αλλιώς το μήνυμα θα ξεχνούσε το γιατί', () {
      for (final reason in AiModelDownReason.values) {
        final restored = decodeAiModelDowntimes(
          encodeAiModelDowntimes([
            AiModelDowntime(
              model: 'm',
              until: DateTime(2026, 1, 1),
              reason: reason,
              blocking: false,
            ),
          ]),
        );

        expect(restored.single.reason, reason);
      }
    });

    test('κενό ή χαλασμένο κείμενο δίνει άδεια λίστα, όχι σφάλμα', () {
      expect(decodeAiModelDowntimes(''), isEmpty);
      expect(decodeAiModelDowntimes('   '), isEmpty);
      expect(decodeAiModelDowntimes('όχι json'), isEmpty);
      expect(decodeAiModelDowntimes('{"m":"x"}'), isEmpty);
    });

    test('εγγραφή χωρίς όνομα ή χωρίς χρόνο αγνοείται', () {
      expect(
        decodeAiModelDowntimes('[{"m":"","u":"2026-01-01T12:00:00.000"}]'),
        isEmpty,
      );
      expect(decodeAiModelDowntimes('[{"m":"x","u":"χαλασμένο"}]'), isEmpty);
    });
  });
}
