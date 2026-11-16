// Το πλαίσιο στοιχείων μιας συσκευής του χάρτη: ό,τι δεν στέκει δεν
// αποθηκεύεται, και το διαχωριστικό θυρών ακολουθεί το όνομα ώσπου να το
// γράψει ο χρήστης.
//
//   flutter test test/features/directory/building_map/plan/widgets/floor_plan_object_editor_test.dart

import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_object_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const FloorPlanObjectDetails _empty = (
  name: '',
  ip: '',
  lansweeperName: '',
  notes: '',
  portGroups: [],
  portSeparator: null,
  heightU: '',
);

void main() {
  final saved = <FloorPlanObjectDetails>[];

  setUp(saved.clear);

  Future<void> pumpEditor(
    WidgetTester tester, {
    FloorPlanObjectDetails initial = _empty,
    bool network = true,
    bool portSeparator = false,
    bool portGroups = false,
    int? cabinetUnits,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloorPlanObjectEditor(
            title: 'Patch panel',
            initial: initial,
            network: network,
            portSeparator: portSeparator,
            portCount: true,
            portGroups: portGroups,
            cabinetName: 'MC.2.S',
            cabinetUnits: cabinetUnits,
            onCommit: saved.add,
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder field(String label) =>
      find.widgetWithText(TextField, label, skipOffstage: false);

  testWidgets('λάθος IP: η αποθήκευση δεν γίνεται και φαίνεται το μήνυμα', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(field('IP'), '10.10.300.1');
    await tester.pump();
    await tester.tap(find.byTooltip('Αποθήκευση (Enter)'));
    await tester.pump();

    expect(saved, isEmpty);
    expect(find.textContaining('255'), findsOneWidget);

    await tester.enterText(field('IP'), '10,10,30,1');
    await tester.pump();
    await tester.tap(find.byTooltip('Αποθήκευση (Enter)'));
    await tester.pump();

    expect(saved.single.ip, '10.10.30.1');
  });

  testWidgets('είδος χωρίς δίκτυο: δεν υπάρχουν IP και Lansweeper', (
    tester,
  ) async {
    await pumpEditor(tester, network: false);

    expect(field('IP'), findsNothing);
    expect(field('Όνομα Lansweeper'), findsNothing);
  });

  testWidgets('«+ Ομάδα θυρών»: η νέα ομάδα αποθηκεύεται με πλήθος, πρόθεμα '
      'και ταχύτητα', (tester) async {
    await pumpEditor(tester, network: false, portGroups: true);
    await tester.enterText(field('Θύρες'), '8');

    await tester.tap(find.text('Ομάδα θυρών'));
    await tester.pump();
    expect(find.text('Ομάδα 2'), findsOneWidget);
    await tester.enterText(field('Θύρες').last, '2');
    await tester.enterText(field('Πρόθεμα').last, 'SFP');
    await tester.enterText(field('Ταχύτητα').last, '10G SFP+');
    await tester.pump();
    await tester.tap(find.byTooltip('Αποθήκευση (Enter)'));
    await tester.pump();

    final groups = saved.single.portGroups;
    expect([for (final g in groups) g.count], ['8', '2']);
    expect(groups.last.source, isNull);
    expect((groups.last.prefix, groups.last.speed), ('SFP', '10G SFP+'));
  });

  testWidgets('θύρες πάνω από το όριο: η αποθήκευση δεν γίνεται', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(field('Θύρες (πλήθος)'), '480');
    await tester.pump();
    await tester.tap(find.byTooltip('Αποθήκευση (Enter)'));
    await tester.pump();

    expect(saved, isEmpty);
  });

  testWidgets('το ύψος σε U φαίνεται μόνο μέσα σε καμπίνα', (tester) async {
    await pumpEditor(tester);
    expect(field('Ύψος (U)'), findsNothing);

    await pumpEditor(
      tester,
      initial: (
        name: '',
        ip: '',
        lansweeperName: '',
        notes: '',
        portGroups: [],
        portSeparator: null,
        heightU: '1',
      ),
      cabinetUnits: 42,
    );
    await tester.enterText(field('Ύψος (U)'), '2');
    await tester.pump();
    await tester.tap(find.byTooltip('Αποθήκευση (Enter)'));
    await tester.pump();

    expect(saved.single.heightU, '2');
  });

  testWidgets('διαχωριστικό: η πρόταση ακολουθεί το όνομα και μένει '
      '«αυτόματο» όσο δεν το αγγίζει ο χρήστης', (tester) async {
    await pumpEditor(tester, portSeparator: true);

    await tester.enterText(field('Όνομα'), 'Molex 1');
    await tester.pump();
    expect(find.text('Θύρα 1 → MC.2.S.Molex 1.1'), findsOneWidget);

    await tester.tap(find.byTooltip('Αποθήκευση (Enter)'));
    await tester.pump();
    expect(saved.single.portSeparator, isNull);
  });

  testWidgets('διαχωριστικό που γράφει ο χρήστης κρατιέται — και το κενό '
      'σημαίνει «χωρίς διαχωριστικό»', (tester) async {
    await pumpEditor(tester, portSeparator: true);
    await tester.enterText(field('Όνομα'), 'Molex 1');
    await tester.pump();

    await tester.enterText(field('Διαχωριστικό θύρας'), '');
    await tester.pump();
    expect(find.text('Θύρα 1 → MC.2.S.Molex 11'), findsOneWidget);

    await tester.tap(find.byTooltip('Αποθήκευση (Enter)'));
    await tester.pump();
    expect(saved.single.portSeparator, '');
  });
}
