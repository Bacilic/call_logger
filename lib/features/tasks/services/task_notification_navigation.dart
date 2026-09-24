import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/tasks_repository.dart';
import '../../../core/providers/main_nav_request_provider.dart';
import '../../../core/utils/run_after_next_frame.dart';
import '../../../core/widgets/main_nav_destination.dart';
import '../models/task_notification.dart';
import '../screens/tasks_screen_actions.dart';

/// Τι συμβαίνει όταν ο άνθρωπος πατήσει «Άνοιγμα εκκρεμότητας».
///
/// **Ζει έξω από το widget επίτηδες.** Είναι ενορχήστρωση — μετάβαση οθόνης,
/// ανάγνωση από τη βάση, άνοιγμα φόρμας — και όχι δήλωση διεπαφής.
///
/// **Η υπόσχεση που δεν τηρούνταν:** το κουμπί έστελνε το αναγνωριστικό της
/// εκκρεμότητας, αλλά ο παραλήπτης το χρησιμοποιούσε μόνο για να κυλήσει τη
/// λίστα ως εκεί. Όταν η εκκρεμότητα είχε κλείσει — δηλαδή ακριβώς στην
/// ειδοποίηση «κάτι δικό σου έκλεισε» — τα φίλτρα δεν την έδειχναν καθόλου,
/// οπότε δεν υπήρχε καν σημείο να κυλήσει και δεν συνέβαινε τίποτα.
Future<void> openTaskFromNotifications(
  BuildContext context,
  WidgetRef ref,
  List<TaskNotification> notifications,
) async {
  if (notifications.isEmpty) return;

  // Πρώτα η μετάβαση, πάντα: ο άνθρωπος πρέπει να βλέπει πού βρίσκεται όταν
  // κλείσει τη φόρμα, και με πολλές ειδοποιήσεις η λίστα είναι ο προορισμός.
  //
  // Η εστίαση σε μία από πέντε θα ήταν αυθαίρετη επιλογή, οπότε στέλνεται
  // μόνο όταν η ειδοποίηση είναι μία.
  final single = notifications.length == 1 ? notifications.single : null;
  ref
      .read(mainNavRequestProvider.notifier)
      .request(
        MainNavRequest(
          destination: MainNavDestination.tasks,
          taskFocusEntityId: single?.taskId,
        ),
      );

  if (single == null) return;

  // Από τη βάση και όχι από τη λίστα της οθόνης: η κλεισμένη εκκρεμότητα δεν
  // περνά τα φίλτρα, και αυτή ακριβώς είναι η περίπτωση που φέρνει εδώ τον
  // άνθρωπο. `null` σημαίνει ότι διαγράφηκε στο μεταξύ — τότε μένει η λίστα,
  // που έχει ήδη ανοίξει.
  final task = await TasksRepository().getTaskById(single.taskId);
  if (task == null || !context.mounted) return;

  // Μετά το καρέ της μετάβασης: η φόρμα ανοίγει πάνω στην οθόνη Εκκρεμοτήτων
  // και όχι πάνω σε εκείνη που άφησε ο άνθρωπος πίσω του.
  await runAfterNextFrame(() {});
  if (!context.mounted) return;
  await editTask(context, ref, task);
}
