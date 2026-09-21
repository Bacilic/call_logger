import 'ai_model_cooldown_registry.dart';

/// Πώς διαβάζεται μια αποτυχία κλήσης ΤΝ, χωρίς να ξέρει το `core` ποιος είναι
/// ο πάροχος.
///
/// Ο καλών μεταφράζει τη δική του εξαίρεση σε αυτή την περιγραφή· ο εκτελεστής
/// της αλυσίδας αποφασίζει με βάση αυτήν αν αξίζει να δοκιμάσει το επόμενο
/// μοντέλο και τι θα θυμάται ο υπολογιστής.
class AiModelAttemptFailure {
  const AiModelAttemptFailure({
    required this.message,
    required this.reason,
    this.serverRetryAfter,
    this.fatal = false,
  });

  /// Το μήνυμα προς τον χρήστη, στα ελληνικά.
  final String message;

  final AiModelDownReason reason;

  /// Ορίστηκε από τον ίδιο τον διακομιστή («ξαναδοκίμασε σε 34 λεπτά»).
  final Duration? serverRetryAfter;

  /// True όταν φταίει η ρύθμιση ή το δίκτυο, όχι το μοντέλο.
  ///
  /// Τότε η αλυσίδα σταματά αμέσως: ένα λάθος κλειδί ή μια κομμένη σύνδεση θα
  /// αποτύχει το ίδιο και στο εφεδρικό — η δεύτερη δοκιμή είναι μόνο αναμονή.
  final bool fatal;
}

/// Η κλήση ΤΝ απέτυχε και δεν έμεινε μοντέλο να δοκιμαστεί.
class AiModelChainException implements Exception {
  const AiModelChainException(this.message, {this.retryAvailableAt});

  final String message;

  /// Πότε ξαναγίνεται διαθέσιμο το κοντινότερο μοντέλο, όταν το ξέρουμε.
  final DateTime? retryAvailableAt;

  @override
  String toString() => message;
}

/// Εκτελεί μια κλήση ΤΝ δοκιμάζοντας τα μοντέλα με τη σειρά που υπαγορεύει η
/// μνήμη υγείας αυτού του υπολογιστή.
///
/// **Το συμβόλαιο:** κάθε κλήση προς την ΤΝ ξεκινά από το πρώτο μοντέλο που ο
/// υπολογιστής δεν ξέρει ήδη πεσμένο, και δοκιμάζει το επόμενο πριν τα
/// παρατήσει. Ζει σε ένα σημείο ώστε καμία μελλοντική χρήση της ΤΝ να μην
/// μπορεί να το ξεχάσει.
class AiModelChainRunner {
  const AiModelChainRunner({required this.registry});

  final AiModelCooldownRegistry registry;

  /// [models] η προτίμηση του χρήστη (κύριο, μετά εφεδρικό)· η σειρά δοκιμής
  /// βγαίνει από τη μνήμη υγείας. [taskLabel] μπαίνει στο μήνυμα αποτυχίας.
  Future<T> run<T>({
    required List<String> models,
    required Future<T> Function(String model) attempt,
    required AiModelAttemptFailure Function(Object error) classify,
    required String taskLabel,
  }) async {
    final candidates = <String>[];
    for (final raw in models) {
      final id = raw.trim();
      if (id.isNotEmpty && !candidates.contains(id)) candidates.add(id);
    }
    if (candidates.isEmpty) {
      throw AiModelChainException(
        'Δεν έχει οριστεί μοντέλο ΤΝ για $taskLabel.',
      );
    }

    // Η μνήμη αλλάζει τη **σειρά**, όχι το περιεχόμενο: ό,τι ξέρουμε
    // προβληματικό πάει τελευταίο, ώστε να μη χαθεί ο χρόνος της αναμονής σε
    // μοντέλο που ήδη ξέρουμε πεσμένο.
    final ordered = registry.orderedForAttempt(candidates);

    Object? lastError;
    for (var i = 0; i < ordered.length; i++) {
      final model = ordered[i];
      final isLast = i == ordered.length - 1;

      // Ο διακομιστής ζήτησε ρητά να μην το χτυπήσουμε τώρα — το σεβόμαστε.
      if (registry.isInCooldown(model)) continue;

      try {
        final result = await attempt(model);
        registry.recordSuccess(model);
        return result;
      } catch (error) {
        lastError = error;
        final failure = classify(error);
        registry.recordFailure(
          model,
          reason: failure.reason,
          serverRetryAfter: failure.serverRetryAfter,
        );
        if (failure.fatal) {
          throw AiModelChainException(failure.message);
        }
        if (isLast) {
          throw AiModelChainException(
            failure.message,
            retryAvailableAt: registry.availableAt(model),
          );
        }
      }
    }

    // Εδώ φτάνουμε μόνο όταν κάθε μοντέλο ήταν σε ρητή αναμονή — καμία δοκιμή
    // δεν έγινε, άρα δεν υπάρχει σφάλμα να αναφέρουμε, μόνο χρόνος.
    if (lastError == null) {
      throw _waitingException(ordered, taskLabel);
    }
    throw AiModelChainException(classify(lastError).message);
  }

  AiModelChainException _waitingException(
    List<String> models,
    String taskLabel,
  ) {
    final earliest = registry.earliestAvailable(models);
    if (earliest == null) {
      return AiModelChainException(
        'Η ΤΝ δεν είναι διαθέσιμη αυτή τη στιγμή για $taskLabel.',
      );
    }
    final reasonText = aiModelWaitReasonText(
      registry.downtime(earliest.model)?.reason,
    );
    final at = earliest.availableAt;
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return AiModelChainException(
      'Τα μοντέλα ΤΝ είναι σε αναμονή ($reasonText). '
      'Δοκιμάστε ξανά μετά τις $hh:$mm.',
      retryAvailableAt: at,
    );
  }
}
