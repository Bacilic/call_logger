import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/task_notifications_repository.dart';
import '../../../core/services/current_operator.dart';
import '../models/task_notification.dart';

final taskNotificationsRepositoryProvider =
    Provider<TaskNotificationsRepository>(
      (ref) => TaskNotificationsRepository(),
    );

/// Τι περιμένει τον συνδεδεμένο χειριστή να δει.
///
/// **Χωρίς `autoDispose`**: ζει όσο η εφαρμογή, γιατί ο ακροατής του κάθεται
/// στο κέλυφος και πρέπει να ειδοποιεί σε όποια οθόνη κι αν βρίσκεται ο
/// χρήστης. Ξαναδιαβάζεται από το ίδιο σημείο που ανανεώνει τα πάντα όταν
/// γράψει άλλο μηχάνημα — κανένας δικός του χρονομετρητής.
///
/// Χωρίς αναγνωρισμένο χειριστή δεν υπάρχει παραλήπτης: κενή λίστα, όχι
/// σφάλμα.
final taskNotificationsProvider = FutureProvider<List<TaskNotification>>((
  ref,
) async {
  final operatorId = CurrentOperator.active?.id;
  if (operatorId == null) return const <TaskNotification>[];
  return ref.read(taskNotificationsRepositoryProvider).unseenFor(operatorId);
});
