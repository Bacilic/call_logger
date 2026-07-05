import 'package:call_logger/core/widgets/reorder_grab_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/// ΣΗΜΑΝΤΙΚΟ / ΟΡΙΟ ΤΟΥ ΤΕΣΤ:
/// Ένα widget test τρέχει σε headless περιβάλλον· βλέπει μόνο το δέντρο των
/// widget, ΟΧΙ τον πραγματικό δείκτη του λειτουργικού. Το native «χέρι» στα
/// Windows (μέσω custom_mouse_cursor) φορτώνεται από plugin που ΔΕΝ υπάρχει στα
/// τεστ, άρα εδώ ο δείκτης πέφτει στο fallback. Επομένως ΔΕΝ ελέγχουμε το σχήμα
/// του δείκτη — αυτό επαληθεύεται ΜΟΝΟ οπτικά, με το ποντίκι πάνω στη λαβή.
/// Εδώ ελέγχουμε αποκλειστικά τη σωστή σύνδεση: MouseRegion + λαβή + εικονίδιο.
Widget _reorderHost(Widget handle) {
  return MaterialApp(
    home: Scaffold(
      body: ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (_, _) {},
        children: [
          KeyedSubtree(
            key: const ValueKey('row'),
            child: Row(
              children: [
                handle,
                const Text('στοιχείο'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  // Εξαίρεση leak-tracking: το custom_mouse_cursor δημιουργεί εσωτερικά έναν
  // TextPainter που δεν απελευθερώνει μέσα στο περιβάλλον τεστ (διαρροή πακέτου).
  testWidgets(
    'ReorderGrabHandle συνδέει MouseRegion + λαβή σύρσισης + εικονίδιο '
    '(το σχήμα του δείκτη ελέγχεται οπτικά, όχι εδώ)',
    experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    (tester) async {
      await tester.pumpWidget(
        _reorderHost(const ReorderGrabHandle(index: 0)),
      );
      await tester.pump();

      expect(find.byIcon(Icons.drag_handle), findsOneWidget);
      expect(find.byType(ReorderableDragStartListener), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(ReorderGrabHandle),
          matching: find.byType(MouseRegion),
        ),
        findsWidgets,
      );
    },
  );
}
