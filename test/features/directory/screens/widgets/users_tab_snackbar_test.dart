// Widget test: snackbar διαγραφής UsersTab — κλείσιμο με Χ μετά dispose του tab.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/screens/widgets/users_tab_snackbar_test.dart

import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/users_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_setup.dart';

class _FakeDirectoryNotifier extends DirectoryNotifier {
  _FakeDirectoryNotifier(this._initialState);

  final DirectoryState _initialState;

  @override
  DirectoryState build() => _initialState;

  @override
  Future<void> loadUsers() async {}

  @override
  Future<void> deleteSelected() async {
    if (state.selectedIds.isEmpty) return;
    final toDelete = state.allUsers
        .where((u) => u.id != null && state.selectedIds.contains(u.id))
        .toList();
    final remaining = state.allUsers
        .where((u) => u.id == null || !state.selectedIds.contains(u.id))
        .toList();
    state = state.copyWith(
      allUsers: remaining,
      filteredUsers: remaining,
      selectedIds: {},
      lastDeleted: toDelete,
    );
  }

  @override
  Future<void> undoLastDelete() async {
    state = state.copyWith(lastDeleted: null);
  }
}

class _UsersTabHost extends StatefulWidget {
  const _UsersTabHost();

  @override
  State<_UsersTabHost> createState() => _UsersTabHostState();
}

class _UsersTabHostState extends State<_UsersTabHost> {
  bool _showTab = true;

  void removeTab() => setState(() => _showTab = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _showTab ? const UsersTab() : const SizedBox.shrink(),
    );
  }
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  testWidgets(
    'UsersTab: πάτημα Χ στο snackbar διαγραφής μετά dispose του tab δεν ρίχνει εξαίρεση',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const userId = 9001;
      final user = UserModel(
        id: userId,
        firstName: 'Snack',
        lastName: 'User',
      );
      final initial = DirectoryState(
        allUsers: [user],
        filteredUsers: [user],
        selectedIds: {userId},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...callLoggerTestProviderOverrides(),
            directoryProvider.overrideWith(() => _FakeDirectoryNotifier(initial)),
            catalogUsersContinuousScrollProvider.overrideWith((ref) async => true),
          ],
          child: const MaterialApp(home: _UsersTabHost()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Διαγραφή'), findsOneWidget);
      await tester.tap(find.text('Διαγραφή'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Διαγραφή'),
        ),
      );
      for (var i = 0;
          i < 60 && find.byType(SnackBar).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Διαγράφηκαν'), findsOneWidget);

      final hostState = tester.state(find.byType(_UsersTabHost)) as _UsersTabHostState;
      hostState.removeTab();
      await tester.pump();

      expect(find.byType(UsersTab), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);

      final closeIcon = find.descendant(
        of: find.byType(SnackBar),
        matching: find.byIcon(Icons.close),
      );
      expect(closeIcon, findsOneWidget);
      final closeButtonFinder = find.ancestor(
        of: closeIcon,
        matching: find.byType(IconButton),
      );
      expect(closeButtonFinder, findsOneWidget);
      final closeButton = tester.widget<IconButton>(closeButtonFinder);
      expect(closeButton.onPressed, isNotNull);
      closeButton.onPressed!();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);

      await flushCallLoggerSqfliteLockTimers(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
