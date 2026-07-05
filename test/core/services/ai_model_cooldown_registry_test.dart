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
      expect(
        registry.availableAt('model-a'),
        DateTime(2026, 1, 1, 12, 0, 10),
      );

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
}
