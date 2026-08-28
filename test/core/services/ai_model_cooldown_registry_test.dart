import 'package:call_logger/core/services/ai_model_cooldown_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiModelCooldownRegistry', () {
    test('markUnavailable / isInCooldown / availableAt με ψεύτικο ρολόι', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      expect(registry.isInCooldown('model-a'), isFalse);
      expect(registry.availableAt('model-a'), isNull);

      registry.markUnavailable('model-a', const Duration(seconds: 10));
      expect(registry.isInCooldown('model-a'), isTrue);
      expect(registry.availableAt('model-a'), DateTime(2026, 1, 1, 12, 0, 10));

      now = DateTime(2026, 1, 1, 12, 0, 9);
      expect(registry.isInCooldown('model-a'), isTrue);

      now = DateTime(2026, 1, 1, 12, 0, 10);
      expect(registry.isInCooldown('model-a'), isFalse);
    });

    test('earliestAvailable επιστρέφει μικρότερο χρόνο', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.markUnavailable('slow', const Duration(seconds: 60));
      registry.markUnavailable('fast', const Duration(seconds: 20));

      final earliest = registry.earliestAvailable(['slow', 'fast', 'free']);
      expect(earliest, isNotNull);
      expect(earliest!.model, 'fast');
      expect(earliest.availableAt, DateTime(2026, 1, 1, 12, 0, 20));
    });

    test('earliestAvailable αγνοεί μοντέλα εκτός cooldown', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      expect(registry.earliestAvailable(['a', 'b']), isNull);
    });
  });

  group('Πόσες αποτυχίες χρειάζονται', () {
    test('τρεις διαδοχικές προσωρινές υποβαθμίζουν το μοντέλο', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.recordFailure('kyrio', reason: AiModelDownReason.unavailable);
      expect(registry.downtime('kyrio'), isNull);

      now = DateTime(2026, 1, 1, 12, 0, 40);
      registry.recordFailure('kyrio', reason: AiModelDownReason.unavailable);
      expect(registry.downtime('kyrio'), isNull);

      now = DateTime(2026, 1, 1, 12, 1, 20);
      registry.recordFailure('kyrio', reason: AiModelDownReason.unavailable);

      final down = registry.downtime('kyrio');
      expect(down, isNotNull);
      expect(down!.reason, AiModelDownReason.unavailable);
      expect(down.blocking, isFalse, reason: 'δική μας εκτίμηση, όχι εντολή');
      expect(down.until, DateTime(2026, 1, 1, 12, 11, 20));
    });

    test('μια επιτυχία στο ενδιάμεσο μηδενίζει τη σειρά', () {
      // Μοντέλο που πετυχαίνει τις μισές φορές δεν είναι πεσμένο.
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.recordFailure('kyrio', reason: AiModelDownReason.unavailable);
      registry.recordFailure('kyrio', reason: AiModelDownReason.unavailable);
      registry.recordSuccess('kyrio');
      registry.recordFailure('kyrio', reason: AiModelDownReason.unavailable);
      registry.recordFailure('kyrio', reason: AiModelDownReason.unavailable);

      expect(registry.downtime('kyrio'), isNull);
    });

    test('αποτυχίες πέρα από το δεκάλεπτο δεν αθροίζονται', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.recordFailure('kyrio', reason: AiModelDownReason.unavailable);
      registry.recordFailure('kyrio', reason: AiModelDownReason.unavailable);

      now = DateTime(2026, 1, 1, 12, 11, 0);
      registry.recordFailure('kyrio', reason: AiModelDownReason.unavailable);

      expect(registry.downtime('kyrio'), isNull, reason: 'νέο παράθυρο');
    });

    test('εξαντλημένη ποσόστωση: μία αποτυχία αρκεί', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.recordFailure('kyrio', reason: AiModelDownReason.quotaExhausted);

      final down = registry.downtime('kyrio');
      expect(down, isNotNull);
      expect(down!.reason, AiModelDownReason.quotaExhausted);
    });

    test('ανύπαρκτο μοντέλο: μία αποτυχία αρκεί', () {
      // Η ρύθμιση επιτρέπει χειροκίνητο όνομα — το τυπογραφικό δεν αξίζει
      // τρεις μισάλεπτες αναμονές.
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.recordFailure('lathos', reason: AiModelDownReason.modelNotFound);

      expect(
        registry.downtime('lathos')?.reason,
        AiModelDownReason.modelNotFound,
      );
    });
  });

  group('Ο χρόνος του διακομιστή', () {
    test('νικά τη δική μας δεκάλεπτη εκτίμηση', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.recordFailure(
        'kyrio',
        reason: AiModelDownReason.quotaExhausted,
        serverRetryAfter: const Duration(minutes: 34),
      );

      final down = registry.downtime('kyrio');
      expect(down!.until, DateTime(2026, 1, 1, 12, 34, 0));
      expect(
        down.blocking,
        isTrue,
        reason: 'μας ζήτησαν ρητά να μη χτυπήσουμε',
      );
      expect(registry.isInCooldown('kyrio'), isTrue);
    });

    test('δεν συντομεύεται από επόμενη δική μας εκτίμηση', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.recordFailure(
        'kyrio',
        reason: AiModelDownReason.quotaExhausted,
        serverRetryAfter: const Duration(minutes: 34),
      );

      now = DateTime(2026, 1, 1, 12, 5, 0);
      registry.recordFailure('kyrio', reason: AiModelDownReason.quotaExhausted);

      expect(
        registry.downtime('kyrio')!.until,
        DateTime(2026, 1, 1, 12, 34, 0),
      );
    });
  });

  group('Η σειρά δοκιμής', () {
    test('πεσμένο κύριο πάει τελευταίο', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.recordFailure('kyrio', reason: AiModelDownReason.quotaExhausted);

      expect(registry.orderedForAttempt(['kyrio', 'efedriko']), [
        'efedriko',
        'kyrio',
      ]);
    });

    test('υγιή μοντέλα κρατούν τη σειρά τους', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      expect(registry.orderedForAttempt(['kyrio', 'efedriko']), [
        'kyrio',
        'efedriko',
      ]);
    });

    test('όταν πέφτουν και τα δύο, επιστρέφει η φυσιολογική σειρά', () {
      // Αλλιώς θα μέναμε κολλημένοι στο εφεδρικό ενώ δεν δουλεύει ούτε αυτό.
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.recordFailure('kyrio', reason: AiModelDownReason.quotaExhausted);
      registry.recordFailure(
        'efedriko',
        reason: AiModelDownReason.quotaExhausted,
      );

      expect(registry.orderedForAttempt(['kyrio', 'efedriko']), [
        'kyrio',
        'efedriko',
      ]);
    });

    test('η επιτυχία ξαναφέρνει το μοντέλο μπροστά', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.recordFailure('kyrio', reason: AiModelDownReason.quotaExhausted);
      registry.recordSuccess('kyrio');

      expect(registry.orderedForAttempt(['kyrio', 'efedriko']).first, 'kyrio');
    });
  });

  group('Η γνώση κρέμεται από το όνομα του μοντέλου', () {
    test('η αλλαγή ρύθμισης ξεκινά καθαρή, χωρίς ρητό μηδενισμό', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.recordFailure(
        'palio-montelo',
        reason: AiModelDownReason.quotaExhausted,
      );

      expect(registry.downtime('neo-montelo'), isNull);
      expect(
        registry.orderedForAttempt(['neo-montelo', 'efedriko']).first,
        'neo-montelo',
      );
    });
  });

  group('Επιβίωση της επανεκκίνησης', () {
    test('η επαναφορά κρατά μόνο ό,τι δεν έχει λήξει', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = AiModelCooldownRegistry(now: () => now);

      registry.restore([
        AiModelDowntime(
          model: 'zwntano',
          until: DateTime(2026, 1, 1, 12, 5, 0),
          reason: AiModelDownReason.quotaExhausted,
          blocking: true,
        ),
        AiModelDowntime(
          model: 'lixmeno',
          until: DateTime(2026, 1, 1, 11, 59, 0),
          reason: AiModelDownReason.unavailable,
          blocking: false,
        ),
      ]);

      expect(registry.downtime('zwntano'), isNotNull);
      expect(registry.downtime('lixmeno'), isNull);
    });

    test('κάθε μεταβολή ειδοποιεί για αποθήκευση', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      var saves = 0;
      final registry = AiModelCooldownRegistry(
        now: () => now,
        onChanged: () => saves++,
      );

      registry.recordFailure('kyrio', reason: AiModelDownReason.quotaExhausted);
      registry.recordSuccess('kyrio');

      expect(saves, 2);
    });
  });
}
