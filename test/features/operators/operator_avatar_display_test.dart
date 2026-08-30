// Το εικονίδιο φτάνει σε κάθε θέση όπου φαίνεται ο χρήστης.
//
//   flutter test test/features/operators/operator_avatar_display_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/features/operators/avatars/operator_avatar_image.dart';
import 'package:call_logger/features/operators/avatars/operator_avatar_picker.dart';
import 'package:call_logger/features/operators/widgets/operator_identity_card.dart';
import 'package:call_logger/features/tasks/widgets/task_person_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Operator profile({String? avatar, bool active = true}) => Operator(
    id: 7,
    displayName: 'Βασίλης',
    isActive: active,
    avatarKey: avatar,
    createdAt: DateTime(2026, 8, 30),
  );

  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  /// Το κλειδί που ζήτησε η οθόνη — ό,τι κι αν κατάφερε να φορτώσει.
  ///
  /// Τα αρχεία των εικονιδίων δεν υπάρχουν στο πακέτο των ελέγχων, οπότε η
  /// εικόνα πέφτει πάντα στο κλασικό ανθρωπάκι. Αυτό που ελέγχεται εδώ είναι η
  /// **σύνδεση**: ότι η κάθε οθόνη ζητά το εικονίδιο του σωστού προσώπου.
  String? requestedKey(WidgetTester tester) => tester
      .widget<OperatorAvatarImage>(find.byType(OperatorAvatarImage).first)
      .avatarKey;

  group('κάρτα ταυτότητας', () {
    testWidgets('δείχνει το εικονίδιο του προφίλ', (tester) async {
      await pump(
        tester,
        OperatorIdentityCard(operator: profile(avatar: 'gorilla')),
      );

      expect(requestedKey(tester), 'gorilla');
    });

    testWidgets('χωρίς εικονίδιο δεν σπάει — μένει το κλασικό', (tester) async {
      await pump(tester, OperatorIdentityCard(operator: profile()));

      expect(find.byType(OperatorAvatarImage), findsOneWidget);
      expect(requestedKey(tester), isNull);
      expect(find.text('Βασίλης'), findsOneWidget);
    });

    testWidgets('το απενεργοποιημένο προφίλ ξεθωριάζει', (tester) async {
      await pump(
        tester,
        OperatorIdentityCard(operator: profile(avatar: 'angel', active: false)),
      );

      final image = tester.widget<OperatorAvatarImage>(
        find.byType(OperatorAvatarImage).first,
      );
      expect(image.muted, isTrue);
    });
  });

  group('σήματα εκκρεμότητας', () {
    testWidgets('ο υπεύθυνος κουβαλά το πρόσωπό του', (tester) async {
      await pump(
        tester,
        TaskPersonChip.assignee(
          name: 'Βασίλης',
          onAssign: () {},
          avatarKey: 'ninja',
        ),
      );

      expect(requestedKey(tester), 'ninja');
    });

    testWidgets('και ο δημιουργός, που παλιά έμενε χωρίς', (tester) async {
      await pump(
        tester,
        const TaskPersonChip.creator(name: 'Μαρία', avatarKey: 'chef'),
      );

      expect(requestedKey(tester), 'chef');
      expect(find.text('Άνοιξε: Μαρία'), findsOneWidget);
    });
  });

  group('επιλογέας εικονιδίου', () {
    testWidgets('το πιασμένο εικονίδιο δεν επιλέγεται', (tester) async {
      String? chosen;
      await pump(
        tester,
        OperatorAvatarPicker(
          selected: null,
          takenBy: const {'gorilla': 'Μαρία'},
          onChanged: (key) => chosen = key,
        ),
      );

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is OperatorAvatarImage && widget.avatarKey == 'gorilla',
        ),
      );
      await tester.pump();

      expect(chosen, isNull);
    });

    testWidgets('το ελεύθερο εικονίδιο επιλέγεται', (tester) async {
      String? chosen;
      await pump(
        tester,
        OperatorAvatarPicker(
          selected: null,
          takenBy: const {'gorilla': 'Μαρία'},
          onChanged: (key) => chosen = key,
        ),
      );

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is OperatorAvatarImage && widget.avatarKey == 'angel',
        ),
      );
      await tester.pump();

      expect(chosen, 'angel');
    });

    testWidgets('η επιστροφή στο κλασικό είναι κανονική επιλογή', (
      tester,
    ) async {
      String? chosen = 'gorilla';
      await pump(
        tester,
        OperatorAvatarPicker(
          selected: 'gorilla',
          takenBy: const {},
          onChanged: (key) => chosen = key,
        ),
      );

      // Το «Κλασικό» ζει μόνο στην υπόδειξη — στην οθόνη είναι το κελί χωρίς
      // κλειδί, όπως όλα τα υπόλοιπα.
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is OperatorAvatarImage && widget.avatarKey == null,
        ),
      );
      await tester.pump();

      expect(chosen, isNull);
    });

    testWidgets('σε προβολή μόνο-ανάγνωσης δεν αλλάζει τίποτα', (tester) async {
      String? chosen = 'unchanged';
      await pump(
        tester,
        OperatorAvatarPicker(
          selected: null,
          takenBy: const {},
          readOnly: true,
          onChanged: (key) => chosen = key,
        ),
      );

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is OperatorAvatarImage && widget.avatarKey == 'angel',
        ),
      );
      await tester.pump();

      expect(chosen, 'unchanged');
    });
  });
}
