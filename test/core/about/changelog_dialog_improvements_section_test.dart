// ChangelogDialog — ενότητα «Μικροβελτιώσεις».
//
//   flutter test test/core/about/changelog_dialog_improvements_section_test.dart

import 'package:call_logger/core/about/models/changelog_entry.dart';
import 'package:call_logger/core/about/providers/app_version_provider.dart';
import 'package:call_logger/core/about/providers/changelog_provider.dart';
import 'package:call_logger/core/about/widgets/changelog_dialog.dart';
import 'package:call_logger/core/updates/update_check_result.dart';
import 'package:call_logger/core/updates/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<ChangelogEntry> entries,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '0.21.1'),
          changelogProvider.overrideWith((ref) async => entries),
          updateCheckProvider.overrideWith(
            (ref) async => const UpdateCheckResult.none(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChangelogDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'εμφανίζει Μικροβελτιώσεις ανάμεσα σε Προστέθηκε και Άλλαξε',
    (tester) async {
      await pumpDialog(
        tester,
        entries: [
          ChangelogEntry.fromJson({
            'version': '0.21.1',
            'date': '2026-07-22',
            'added': ['Νέο Α'],
            'improvements': ['Μικρό Β'],
            'changed': ['Αλλαγή Γ'],
            'fixed': ['Διόρθωση Δ'],
          }),
        ],
      );

      expect(find.text('Προστέθηκε'), findsOneWidget);
      expect(find.text('Μικροβελτιώσεις'), findsOneWidget);
      expect(find.text('Άλλαξε'), findsOneWidget);
      expect(find.text('Διορθώθηκε'), findsOneWidget);
      expect(find.text('Μικρό Β'), findsOneWidget);

      final improvementsY = tester.getTopLeft(find.text('Μικροβελτιώσεις')).dy;
      expect(
        improvementsY,
        greaterThan(tester.getTopLeft(find.text('Προστέθηκε')).dy),
      );
      expect(
        improvementsY,
        lessThan(tester.getTopLeft(find.text('Άλλαξε')).dy),
      );
    },
  );

  testWidgets(
    'κρύβει Μικροβελτιώσεις όταν η λίστα είναι κενή',
    (tester) async {
      await pumpDialog(
        tester,
        entries: [
          ChangelogEntry.fromJson({
            'version': '0.21.1',
            'date': '2026-07-22',
            'added': ['Νέο Α'],
            'improvements': <String>[],
            'changed': ['Αλλαγή Γ'],
            'fixed': <String>[],
          }),
        ],
      );

      expect(find.text('Μικροβελτιώσεις'), findsNothing);
      expect(find.text('Προστέθηκε'), findsOneWidget);
      expect(find.text('Άλλαξε'), findsOneWidget);
    },
  );
}
