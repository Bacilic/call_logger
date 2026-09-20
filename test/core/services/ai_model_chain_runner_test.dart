import 'package:call_logger/core/services/ai_model_chain_runner.dart';
import 'package:call_logger/core/services/ai_model_cooldown_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Μια αποτυχία μοντέλου (όχι υποδομής) — η αλυσίδα οφείλει να προχωρήσει.
class _ModelDown implements Exception {
  const _ModelDown(this.reason, {this.retryAfter});
  final AiModelDownReason reason;
  final Duration? retryAfter;
}

/// Αποτυχία ρύθμισης/δικτύου — η αλυσίδα οφείλει να σταματήσει.
class _Fatal implements Exception {
  const _Fatal();
}

AiModelAttemptFailure _classify(Object error) {
  if (error is _ModelDown) {
    return AiModelAttemptFailure(
      message: 'έπεσε',
      reason: error.reason,
      serverRetryAfter: error.retryAfter,
    );
  }
  return const AiModelAttemptFailure(
    message: 'λάθος ρύθμιση',
    reason: AiModelDownReason.unavailable,
    fatal: true,
  );
}

void main() {
  late DateTime now;
  late AiModelCooldownRegistry registry;
  late List<String> attempted;

  setUp(() {
    now = DateTime(2026, 9, 20, 14, 0);
    registry = AiModelCooldownRegistry(now: () => now);
    attempted = <String>[];
  });

  Future<String> run({
    List<String> models = const ['κύριο', 'εφεδρικό'],
    required Future<String> Function(String model) attempt,
  }) {
    return AiModelChainRunner(registry: registry).run<String>(
      models: models,
      taskLabel: 'τη δοκιμή',
      classify: _classify,
      attempt: (model) {
        attempted.add(model);
        return attempt(model);
      },
    );
  }

  test('με όλα υγιή ξεκινά από το κύριο και δεν αγγίζει το εφεδρικό', () async {
    final result = await run(attempt: (m) async => 'από $m');

    expect(result, 'από κύριο');
    expect(attempted, ['κύριο']);
  });

  test('όταν το κύριο είναι γνωστό πεσμένο, ξεκινά από το εφεδρικό', () async {
    registry.recordFailure('κύριο', reason: AiModelDownReason.quotaExhausted);

    final result = await run(attempt: (m) async => 'από $m');

    expect(result, 'από εφεδρικό');
    expect(attempted, ['εφεδρικό']);
  });

  test('αποτυχία του πρώτου μοντέλου δοκιμάζει το επόμενο', () async {
    final result = await run(
      attempt: (m) async {
        if (m == 'κύριο') {
          throw const _ModelDown(AiModelDownReason.quotaExhausted);
        }
        return 'από $m';
      },
    );

    expect(result, 'από εφεδρικό');
    expect(attempted, ['κύριο', 'εφεδρικό']);
  });

  test('σφάλμα ρύθμισης σταματά την αλυσίδα χωρίς δεύτερη δοκιμή', () async {
    await expectLater(
      run(attempt: (m) async => throw const _Fatal()),
      throwsA(
        isA<AiModelChainException>().having(
          (e) => e.message,
          'μήνυμα',
          'λάθος ρύθμιση',
        ),
      ),
    );

    expect(attempted, ['κύριο']);
  });

  test('ρητή αναμονή του διακομιστή παραλείπει το μοντέλο', () async {
    registry.markUnavailable('κύριο', const Duration(minutes: 20));

    final result = await run(attempt: (m) async => 'από $m');

    expect(attempted, ['εφεδρικό']);
    expect(result, 'από εφεδρικό');
  });

  test('με όλα σε ρητή αναμονή λέει ως πότε, χωρίς καμία δοκιμή', () async {
    registry.markUnavailable(
      'κύριο',
      const Duration(minutes: 40),
      reason: AiModelDownReason.quotaExhausted,
    );
    registry.markUnavailable(
      'εφεδρικό',
      const Duration(minutes: 25),
      reason: AiModelDownReason.quotaExhausted,
    );

    await expectLater(
      run(attempt: (m) async => 'δεν πρέπει να κληθεί'),
      throwsA(
        isA<AiModelChainException>()
            .having(
              (e) => e.message,
              'μήνυμα',
              allOf(contains('εξαντλημένη ποσόστωση'), contains('14:25')),
            )
            .having(
              (e) => e.retryAvailableAt,
              'πότε ξανά',
              DateTime(2026, 9, 20, 14, 25),
            ),
      ),
    );

    expect(attempted, isEmpty);
  });

  test('η επιτυχία σβήνει ό,τι ξέραμε εναντίον του μοντέλου', () async {
    registry.recordFailure('κύριο', reason: AiModelDownReason.quotaExhausted);
    expect(registry.downtime('κύριο'), isNotNull);

    await run(models: const ['κύριο'], attempt: (m) async => 'εντάξει');

    expect(registry.downtime('κύριο'), isNull);
  });

  test('η αποτυχία του τελευταίου μοντέλου γράφεται στη μνήμη', () async {
    await expectLater(
      run(
        models: const ['κύριο'],
        attempt: (m) async =>
            throw const _ModelDown(AiModelDownReason.modelNotFound),
      ),
      throwsA(isA<AiModelChainException>()),
    );

    expect(registry.downtime('κύριο')?.reason, AiModelDownReason.modelNotFound);
  });

  test('ο χρόνος που όρισε ο διακομιστής γίνεται ρητή αναμονή', () async {
    await expectLater(
      run(
        models: const ['κύριο'],
        attempt: (m) async => throw const _ModelDown(
          AiModelDownReason.quotaExhausted,
          retryAfter: Duration(minutes: 34),
        ),
      ),
      throwsA(
        isA<AiModelChainException>().having(
          (e) => e.retryAvailableAt,
          'πότε ξανά',
          DateTime(2026, 9, 20, 14, 34),
        ),
      ),
    );

    // Ρητή αναμονή: η επόμενη κλήση δεν ξαναχτυπά το μοντέλο.
    expect(registry.isInCooldown('κύριο'), isTrue);
  });

  test('χωρίς κανένα μοντέλο το λέει αντί να δοκιμάσει', () async {
    await expectLater(
      run(models: const ['', '  '], attempt: (m) async => 'ποτέ'),
      throwsA(
        isA<AiModelChainException>().having(
          (e) => e.message,
          'μήνυμα',
          contains('Δεν έχει οριστεί μοντέλο ΤΝ'),
        ),
      ),
    );

    expect(attempted, isEmpty);
  });
}
