import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Κατανάλωση από [CallHeaderForm]: προσυμπλήρωση πεδίου «Τμήμα» στην οθόνη Νέα Κλήση.
class CallDepartmentPrefillIntentNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void prefill(String departmentName) {
    final trimmed = departmentName.trim();
    if (trimmed.isEmpty) return;
    state = trimmed;
  }

  void clear() {
    state = null;
  }
}

final callDepartmentPrefillIntentProvider =
    NotifierProvider<CallDepartmentPrefillIntentNotifier, String?>(
  CallDepartmentPrefillIntentNotifier.new,
);
