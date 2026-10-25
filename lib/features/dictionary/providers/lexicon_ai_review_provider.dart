import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/ai_model_health_provider.dart';
import '../services/lexicon_ai_review_service.dart';

/// Ο «Έλεγχος με ΤΝ» για μια λίστα λέξεων. Πίσω από provider, ώστε τα τεστ
/// να δίνουν ετυμηγορίες χωρίς δίκτυο.
typedef LexiconAiReviewRunner =
    Future<LexiconAiReviewOutcome> Function(List<String> words);

final lexiconAiReviewRunnerProvider = Provider<LexiconAiReviewRunner>(
  (ref) =>
      (words) => LexiconAiReviewService.review(
        words,
        registry: ref.read(aiModelCooldownRegistryProvider),
      ),
);
