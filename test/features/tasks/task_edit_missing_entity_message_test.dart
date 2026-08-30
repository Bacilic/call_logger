// Κανένα κουμπί δεν μένει σιωπηλό όταν η οντότητα λείπει από τον κατάλογο.
//
// Ο εξοπλισμός έλεγε «δεν βρέθηκε». Ο υπάλληλος και το τμήμα δεν έλεγαν
// τίποτα: το πάτημα έμοιαζε με χαλασμένη εφαρμογή.
//
//   flutter test test/features/tasks/task_edit_missing_entity_message_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/screens/tasks_screen_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Κατάλογος τμημάτων που δεν αγγίζει βάση και δεν περιέχει το ζητούμενο.
class _EmptyDepartments extends DepartmentDirectoryNotifier {
  @override
  DepartmentDirectoryState build() => DepartmentDirectoryState();

  @override
  Future<void> loadDepartments() async {}
}

void main() {
  final task = Task(
    id: 1,
    title: 'Προς δοκιμή',
    dueDate: '2026-09-01T10:00:00.000',
    status: 'open',
    callerId: 7,
    departmentId: 8,
    userText: 'Βαρβάρα',
    departmentText: 'Αιματολογικό',
  );

  /// Στήνει μια οθόνη με μεσσατζέρη και τρέχει την ενέργεια πάνω της.
  Future<bool> runAction(
    WidgetTester tester,
    Future<bool> Function(BuildContext, WidgetRef, Task) action,
  ) async {
    late Future<bool> result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lookupServiceProvider.overrideWith(
            (ref) async => LookupLoadResult(service: LookupService.instance),
          ),
          departmentDirectoryProvider.overrideWith(_EmptyDepartments.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => result = action(context, ref, task),
                child: const Text('τρέξε'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('τρέξε'));
    await tester.pumpAndSettle();
    return result;
  }

  group('Επεξεργασία οντότητας που λείπει από τον κατάλογο', () {
    testWidgets('ο άγνωστος υπάλληλος το λέει αντί να σωπαίνει', (
      tester,
    ) async {
      final opened = await runAction(tester, editTaskCaller);

      expect(opened, isFalse);
      expect(find.text(kCatalogUserMissingMessage), findsOneWidget);
    });

    testWidgets('το άγνωστο τμήμα το λέει αντί να σωπαίνει', (tester) async {
      final opened = await runAction(tester, editTaskDepartment);

      expect(opened, isFalse);
      expect(find.text(kCatalogDepartmentMissingMessage), findsOneWidget);
    });
  });
}
