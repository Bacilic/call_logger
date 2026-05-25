import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/history_call_actions_service.dart';

/// Χωρίς autoDispose: τα dialogs κάνουν μόνο [Ref.read]· με autoDispose το [Ref]
/// διαθέεται πριν ολοκληρωθεί async αποθήκευση + [refreshAfterMutation].
final historyCallActionsServiceProvider = Provider<HistoryCallActionsService>((
  ref,
) {
  return HistoryCallActionsService(ref);
});
