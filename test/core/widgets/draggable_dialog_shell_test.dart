// Widget tests: κινητό κέλυφος διαλόγου (σύρσιμο από τίτλο).
//
//   flutter test test/core/widgets/draggable_dialog_shell_test.dart

import 'package:call_logger/core/widgets/draggable_dialog_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

const _titleText = 'Τίτλος δοκιμής';
const _bodyText = 'Σώμα διαλόγου';

Widget _shellUnderTest() {
  return DraggableDialogShell(
    title: const Text(_titleText),
    builder: (titleHandle) => AlertDialog(
      title: titleHandle,
      content: const SizedBox(
        width: 240,
        height: 120,
        child: Text(_bodyText),
      ),
      actions: const [TextButton(onPressed: null, child: Text('OK'))],
    ),
  );
}

Future<void> _pumpCenteredDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: _shellUnderTest()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Offset _translateOffset(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(DraggableDialogShell),
      matching: find.byType(Transform),
    ),
  );
  final m4 = transform.transform;
  return Offset(m4.storage[12], m4.storage[13]);
}

void main() {
  group('DraggableDialogShell', () {
    testWidgets('δ) ανοίγει κεντραρισμένος με μηδενική αρχική μετατόπιση', (
      tester,
    ) async {
      await _pumpCenteredDialog(tester);

      final offset = _translateOffset(tester);
      expect(
        offset,
        Offset.zero,
        reason: greekExpectMsg(
          'Η αρχική μετατόπιση πρέπει να είναι μηδενική (κεντραρισμένος διάλογος)',
        ),
      );
    });

    testWidgets('α) σύρσιμο από τον τίτλο μετακινεί τον διάλογο', (
      tester,
    ) async {
      await _pumpCenteredDialog(tester);

      const delta = Offset(48, 36);
      await tester.drag(find.text(_titleText), delta);
      await tester.pump();

      final offset = _translateOffset(tester);
      expect(
        offset.dx,
        closeTo(delta.dx, 0.5),
        reason: greekExpectMsg(
          'Το σύρσιμο από τον τίτλο πρέπει να μετακινεί οριζόντια κατά το delta',
        ),
      );
      expect(
        offset.dy,
        closeTo(delta.dy, 0.5),
        reason: greekExpectMsg(
          'Το σύρσιμο από τον τίτλο πρέπει να μετακινεί κάθετα κατά το delta',
        ),
      );
    });

    testWidgets('β) σύρσιμο από το σώμα ΔΕΝ μετακινεί τον διάλογο', (
      tester,
    ) async {
      await _pumpCenteredDialog(tester);

      await tester.drag(find.text(_bodyText), const Offset(60, 40));
      await tester.pump();

      final offset = _translateOffset(tester);
      expect(
        offset,
        Offset.zero,
        reason: greekExpectMsg(
          'Το σύρσιμο από το σώμα δεν πρέπει να μετακινεί τον διάλογο',
        ),
      );
    });

    testWidgets(
      'γ) η μετατόπιση σταματά στα όρια — ο τίτλος δεν βγαίνει εκτός',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await _pumpCenteredDialog(tester);

        // Μεγάλη μετατόπιση προς πάνω-αριστερά — πρέπει να κοπεί στα όρια.
        await tester.drag(find.text(_titleText), const Offset(-5000, -5000));
        await tester.pumpAndSettle();

        final titleTopLeft = tester.getTopLeft(find.text(_titleText));
        expect(
          titleTopLeft.dx,
          greaterThanOrEqualTo(-0.5),
          reason: greekExpectMsg(
            'Ο τίτλος δεν πρέπει να βγαίνει αριστερά από το παράθυρο',
          ),
        );
        expect(
          titleTopLeft.dy,
          greaterThanOrEqualTo(-0.5),
          reason: greekExpectMsg(
            'Ο τίτλος δεν πρέπει να βγαίνει πάνω από το παράθυρο',
          ),
        );

        // Μεγάλη μετατόπιση προς κάτω-δεξιά.
        await tester.drag(find.text(_titleText), const Offset(5000, 5000));
        await tester.pumpAndSettle();

        final titleBottomRight = tester.getBottomRight(find.text(_titleText));
        final mediaSize = tester.getSize(find.byType(MaterialApp));
        expect(
          titleBottomRight.dx,
          lessThanOrEqualTo(mediaSize.width + 0.5),
          reason: greekExpectMsg(
            'Ο τίτλος δεν πρέπει να βγαίνει δεξιά από το παράθυρο',
          ),
        );
        expect(
          titleBottomRight.dy,
          lessThanOrEqualTo(mediaSize.height + 0.5),
          reason: greekExpectMsg(
            'Ο τίτλος δεν πρέπει να βγαίνει κάτω από το παράθυρο',
          ),
        );
      },
    );

    testWidgets(
      'MouseRegion με SystemMouseCursors.move πάνω από τον τίτλο',
      (tester) async {
        await _pumpCenteredDialog(tester);

        final regions = tester.widgetList<MouseRegion>(find.byType(MouseRegion));
        final moveRegion = regions.where(
          (r) => r.cursor == SystemMouseCursors.move,
        );
        expect(
          moveRegion,
          isNotEmpty,
          reason: greekExpectMsg(
            'Πρέπει να υπάρχει MouseRegion με SystemMouseCursors.move στον τίτλο',
          ),
        );
      },
    );
  });
}
