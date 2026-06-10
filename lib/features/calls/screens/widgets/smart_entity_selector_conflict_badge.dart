import 'package:flutter/material.dart';

import '../../provider/smart_entity_selector_provider.dart';

/// Δείκτης σύγκρουσης (v2 §Α): κόκκινος όταν η βάση γνωρίζει διαφορετική τιμή
/// ([ConflictSeverity.mismatch]), κίτρινος όταν το πεδίο δεν αντιστοιχεί σε
/// γνωστή οντότητα ([ConflictSeverity.unknown]). Το tooltip παραθέτει όλους
/// τους λόγους σύγκρουσης.
class ConflictBadge extends StatelessWidget {
  const ConflictBadge({
    super.key,
    required this.severity,
    required this.message,
  });

  final ConflictSeverity? severity;
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (severity == null) return const SizedBox.shrink();
    final color = severity == ConflictSeverity.mismatch
        ? const Color(0xFFD32F2F) // κόκκινο
        : const Color(0xFFF9A825); // κίτρινο
    return Tooltip(
      message: message ?? '',
      waitDuration: const Duration(milliseconds: 200),
      preferBelow: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Container(
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const Icon(
            Icons.priority_high,
            size: 11,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
