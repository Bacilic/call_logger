// Ο μικρός χάρτης της κλήσης ξαναφορτώνει όταν αλλάζει η χαρτογράφηση τμήματος
// από άλλη ροή (π.χ. ο πλήρης χάρτης που ανοίγει η ίδια η κάρτα), όχι μόνο όταν
// αλλάζουν τα πεδία της φόρμας.
//
//   flutter test test/features/calls/screens/widgets/mini_map_card_refresh_test.dart

import 'dart:async';

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/mini_map_card.dart';
import 'package:call_logger/features/calls/services/mini_map_data_loader.dart';
import 'package:call_logger/features/directory/building_map/providers/building_map_providers.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _kNotOnMapMessage = 'Δεν υπάρχει το τμήμα στο χάρτη';
const int _kDeptId = 7;

DepartmentModel _department({required bool mapped}) {
  return DepartmentModel(
    id: _kDeptId,
    name: 'Γραφείο Προμηθειών',
    mapFloor: mapped ? '1' : null,
    mapX: mapped ? 0.3 : null,
    mapY: mapped ? 0.4 : null,
    mapWidth: mapped ? 0.2 : 0.0,
    mapHeight: mapped ? 0.15 : 0.0,
  );
}

MiniMapCardData _data({required bool mapped}) {
  const candidates = MiniMapCandidateDepartments(
    headerDepartmentId: _kDeptId,
    equipmentDepartmentId: null,
    phoneDepartmentId: null,
    userDepartmentId: null,
  );
  return MiniMapCardData(
    floors: const [],
    departmentsById: {_kDeptId: _department(mapped: mapped)},
    selection: resolveMiniMapSelection(candidates),
    equipmentEntity: null,
    candidates: candidates,
  );
}

/// Μιμείται τη βάση: το «τι λέει η βάση τώρα» αλλάζει ανάμεσα στις φορτώσεις.
class _FakeMapSource {
  bool mapped = false;
  int loadCount = 0;

  Future<MiniMapCardData> load(MiniMapRequest request) async {
    loadCount++;
    return _data(mapped: mapped);
  }
}

Future<void> _pumpCard(WidgetTester tester, _FakeMapSource source) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Χωρίς βάση στο τεστ· κάθε επαναφόρτωση δίνει νέο αποτέλεσμα, όπως
        // ακριβώς μετά από mutation καταλόγου στην παραγωγή.
        lookupServiceProvider.overrideWith(
          (ref) async => LookupLoadResult(service: LookupService.instance),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MiniMapCard(
            equipment: null,
            equipmentCodeText: '',
            phoneText: '',
            user: null,
            departmentId: _kDeptId,
            loadData: source.load,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _containerOf(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// Ό,τι κάνει ο πλήρης χάρτης μετά την αποθήκευση θέσης: ξαναφορτώνει τον
/// κατάλογο τμημάτων. Τα πεδία της φόρμας ΔΕΝ αλλάζουν.
void _publishDepartmentDirectoryReload(
  WidgetTester tester,
  List<DepartmentModel> departments,
) {
  final container = _containerOf(tester);
  container
      .read(departmentDirectoryProvider.notifier)
      .state = DepartmentDirectoryState(
    allDepartments: departments,
    filteredDepartments: departments,
  );
}

/// Ό,τι κάνει ο χάρτης όταν αλλάξει φύλλο κατόψης (εικόνα, περιστροφή, προσθήκη).
void _publishFloorSheetsChanged(WidgetTester tester) {
  _containerOf(tester).read(buildingMapFloorReloadSeqProvider.notifier).bump();
}

void main() {
  testWidgets(
    'χαρτογράφηση τμήματος από τον πλήρη χάρτη ανανεώνει τον μικρό χάρτη '
    'χωρίς αλλαγή στα πεδία της φόρμας',
    (tester) async {
      final source = _FakeMapSource();

      await _pumpCard(tester, source);
      expect(
        find.text(_kNotOnMapMessage),
        findsOneWidget,
        reason: 'Αφετηρία: το τμήμα δεν είναι ακόμη στον χάρτη.',
      );
      expect(source.loadCount, 1);

      source.mapped = true;
      _publishDepartmentDirectoryReload(tester, [_department(mapped: true)]);
      await tester.pumpAndSettle();

      expect(
        find.text(_kNotOnMapMessage),
        findsNothing,
        reason:
            'Μετά τη χαρτογράφηση ο μικρός χάρτης οφείλει να ξαναδιαβάσει τις '
            'πηγές του αντί να κρατά το παλιό μήνυμα.',
      );
      expect(source.loadCount, 2);
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'αφαίρεση χαρτογράφησης ανανεώνει επίσης τον μικρό χάρτη',
    (tester) async {
      final source = _FakeMapSource()..mapped = true;

      await _pumpCard(tester, source);
      expect(find.text(_kNotOnMapMessage), findsNothing);

      source.mapped = false;
      _publishDepartmentDirectoryReload(tester, [_department(mapped: false)]);
      await tester.pumpAndSettle();

      expect(find.text(_kNotOnMapMessage), findsOneWidget);
    },
    semanticsEnabled: false,
  );

  testWidgets('αλλαγή φύλλου κατόψης ανανεώνει τον μικρό χάρτη', (
    tester,
  ) async {
    final source = _FakeMapSource();
    await _pumpCard(tester, source);
    expect(source.loadCount, 1);

    // Αντικατάσταση εικόνας κατόψης: το τμήμα δεν άλλαξε, η εικόνα του ναι.
    source.mapped = true;
    _publishFloorSheetsChanged(tester);
    await tester.pumpAndSettle();

    expect(source.loadCount, 2);
    expect(find.text(_kNotOnMapMessage), findsNothing);
  }, semanticsEnabled: false);

  testWidgets(
    'αλλαγή συσχετίσεων καταλόγου ανανεώνει τον μικρό χάρτη',
    (tester) async {
      final source = _FakeMapSource();
      await _pumpCard(tester, source);
      expect(source.loadCount, 1);

      // Αλλαγή κατόχου/τμήματος εξοπλισμού από τον Κατάλογο: το τμήμα-στόχος
      // του χάρτη προκύπτει από τις συσχετίσεις, όχι από τα πεδία της φόρμας.
      source.mapped = true;
      _containerOf(tester).invalidate(lookupServiceProvider);
      await tester.pumpAndSettle();

      expect(source.loadCount, 2);
      expect(find.text(_kNotOnMapMessage), findsNothing);
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'αλλαγή ΕΝΩ ο πλήρης χάρτης σκεπάζει την κάρτα φαίνεται στην επιστροφή '
    '(χωρίς δεύτερο άνοιγμα)',
    (tester) async {
      final source = _FakeMapSource();
      await _pumpCard(tester, source);
      expect(find.text(_kNotOnMapMessage), findsOneWidget);

      // Ο πλήρης χάρτης είναι αδιαφανής fullscreen διάλογος: όσο είναι
      // ανοιχτός, η κάρτα από κάτω δεν ξαναχτίζεται.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('πλήρης χάρτης')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('πλήρης χάρτης'), findsOneWidget);

      // Αποθήκευση νέας κατόψης ΜΕΣΑ από τον χάρτη.
      source.mapped = true;
      _publishFloorSheetsChanged(tester);
      await tester.pumpAndSettle();

      navigator.pop();
      await tester.pumpAndSettle();

      expect(
        find.text(_kNotOnMapMessage),
        findsNothing,
        reason:
            'Η επιστροφή από τον χάρτη πρέπει να δείχνει ήδη τη νέα κάτοψη — '
            'όχι να περιμένει δεύτερο άνοιγμα/κλείσιμο.',
      );
      expect(source.loadCount, 2);
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'κατάλογος τμημάτων χωρίς πραγματική αλλαγή δεν προκαλεί επαναφόρτωση',
    (tester) async {
      final source = _FakeMapSource();
      await _pumpCard(tester, source);
      expect(source.loadCount, 1);

      final same = [_department(mapped: false)];
      _publishDepartmentDirectoryReload(tester, same);
      await tester.pumpAndSettle();
      expect(source.loadCount, 2);

      // Ίδια αναφορά λίστας (π.χ. φιλτράρισμα/ταξινόμηση στον Κατάλογο):
      // δεν είναι αλλαγή δεδομένων, δεν ξαναφορτώνει.
      final container = _containerOf(tester);
      final notifier = container.read(departmentDirectoryProvider.notifier);
      notifier.state = DepartmentDirectoryState(
        allDepartments: same,
        filteredDepartments: const [],
        searchQuery: 'φιλτράρισμα',
      );
      await tester.pumpAndSettle();

      expect(source.loadCount, 2);
    },
    semanticsEnabled: false,
  );
}
