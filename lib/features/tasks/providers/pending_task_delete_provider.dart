import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Κατάσταση εκκρεμούς διαγραφής με αντίστροφη μέτρηση (ένα ενεργό SnackBar τη φορά).
/// Μη null = id εκκρεμότητας για την οποία τρέχει η χρονομέτρηση.
class PendingTaskDeleteNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void begin(int taskId) => state = taskId;

  void clear() => state = null;
}

final pendingTaskDeleteProvider =
    NotifierProvider<PendingTaskDeleteNotifier, int?>(
  PendingTaskDeleteNotifier.new,
);
