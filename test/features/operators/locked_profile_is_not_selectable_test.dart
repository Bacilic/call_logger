// Το προφίλ που κρατά άλλος υπολογιστής φαίνεται, λέει γιατί, και ΔΕΝ
// επιλέγεται. Τα προφίλ διαχειριστή περνούν, αλλά μόνο μετά από ρητό «ναι».
//
// Συμπεριφορά, όχι εμφάνιση: κανένας έλεγχος χρωμάτων ή διαστάσεων.
//
//   flutter test test/features/operators/locked_profile_is_not_selectable_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/profile_availability.dart';
import 'package:call_logger/features/operators/services/operator_presence_summary.dart';
import 'package:call_logger/features/operators/services/selectable_profiles.dart';
import 'package:call_logger/features/operators/widgets/change_operator_dialog.dart';
import 'package:call_logger/features/operators/widgets/operator_picker_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Operator _profile(int id, String name, {bool isAdmin = false}) => Operator(
  id: id,
  displayName: name,
  isAdmin: isAdmin,
  createdAt: DateTime(2026, 1, 1),
);

Future<void> _pumpPicker(
  WidgetTester tester, {
  required List<Operator> profiles,
  required Map<int, ProfileAvailability> availability,
  required List<Operator> picked,
  Map<int, List<OperatorPresenceLine>> presence =
      const <int, List<OperatorPresenceLine>>{},
  Future<bool> Function(Operator operator, String station)? confirm,
  bool presenceUnavailable = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OperatorPickerBody(
            profiles: profiles,
            presence: presence,
            availability: availability,
            presenceUnavailable: presenceUnavailable,
            confirmAdminOverride: confirm,
            onPick: (operator) async => picked.add(operator),
            onCreate: (_, _) async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('κλειδωμένη κάρτα: το πάτημα δεν ενεργοποιεί ταυτότητα', (
    tester,
  ) async {
    final picked = <Operator>[];

    await _pumpPicker(
      tester,
      profiles: [_profile(1, 'Βασίλης')],
      availability: const {
        1: ProfileAvailability(
          ProfileLockKind.lockedElsewhere,
          station: 'POPINIO',
        ),
      },
      picked: picked,
    );

    await tester.tap(find.text('Βασίλης'));
    await tester.pumpAndSettle();

    expect(picked, isEmpty);
  });

  testWidgets('κλειδωμένη κάρτα: λέει πού είναι συνδεδεμένος', (tester) async {
    await _pumpPicker(
      tester,
      profiles: [_profile(1, 'Βασίλης')],
      availability: const {
        1: ProfileAvailability(
          ProfileLockKind.lockedElsewhere,
          station: 'POPINIO',
        ),
      },
      picked: <Operator>[],
    );

    expect(
      find.textContaining('POPINIO'),
      findsOneWidget,
      reason: 'ο άνθρωπος πρέπει να ξέρει ποιον υπολογιστή να κλείσει',
    );
  });

  testWidgets('ελεύθερη κάρτα επιλέγεται κανονικά', (tester) async {
    final picked = <Operator>[];

    await _pumpPicker(
      tester,
      profiles: [_profile(1, 'Βασίλης')],
      availability: const {1: ProfileAvailability(ProfileLockKind.free)},
      picked: picked,
    );

    await tester.tap(find.text('Βασίλης'));
    await tester.pumpAndSettle();

    expect(picked.single.id, 1);
  });

  testWidgets('προφίλ χωρίς καταχώρηση στον χάρτη επιλέγεται κανονικά', (
    tester,
  ) async {
    final picked = <Operator>[];

    await _pumpPicker(
      tester,
      profiles: [_profile(1, 'Βασίλης')],
      availability: const <int, ProfileAvailability>{},
      picked: picked,
    );

    await tester.tap(find.text('Βασίλης'));
    await tester.pumpAndSettle();

    expect(picked.single.id, 1);
  });

  group('Προφίλ διαχειριστή ανοιχτό αλλού', () {
    const availability = {
      1: ProfileAvailability(
        ProfileLockKind.adminOpenElsewhere,
        station: 'PICINIO',
      ),
    };

    testWidgets('ρωτά πρώτα, και με «ναι» η επιλογή προχωρά', (tester) async {
      final picked = <Operator>[];
      final asked = <String>[];

      await _pumpPicker(
        tester,
        profiles: [_profile(1, 'Βασίλης', isAdmin: true)],
        availability: availability,
        picked: picked,
        confirm: (operator, station) async {
          asked.add(station);
          return true;
        },
      );

      await tester.tap(find.text('Βασίλης'));
      await tester.pumpAndSettle();

      expect(asked, ['PICINIO']);
      expect(picked.single.id, 1);
    });

    testWidgets('με «άκυρο» η ταυτότητα δεν αλλάζει', (tester) async {
      final picked = <Operator>[];

      await _pumpPicker(
        tester,
        profiles: [_profile(1, 'Βασίλης', isAdmin: true)],
        availability: availability,
        picked: picked,
        confirm: (_, _) async => false,
      );

      await tester.tap(find.text('Βασίλης'));
      await tester.pumpAndSettle();

      expect(picked, isEmpty);
    });
  });

  testWidgets('όταν τα ίχνη δεν διαβάστηκαν, η οθόνη το λέει', (tester) async {
    await _pumpPicker(
      tester,
      profiles: [_profile(1, 'Βασίλης')],
      availability: const <int, ProfileAvailability>{},
      picked: <Operator>[],
      presenceUnavailable: true,
    );

    expect(find.textContaining('δεν διαβάστηκε'), findsOneWidget);
  });

  testWidgets(
    'μόλις ελευθερωθεί το προφίλ, η κάρτα ξεκλειδώνει χωρίς να κλείσει ο '
    'διάλογος',
    (tester) async {
      // Ο συνάδελφος κλείνει την εφαρμογή του: ο άνθρωπος που περιμένει δεν
      // πρέπει να χρειαστεί να κλείσει και να ξανανοίξει τον διάλογο.
      final picked = <Operator>[];
      var stillOpenElsewhere = true;

      Future<SelectableProfiles> load() async => SelectableProfiles(
        profiles: [_profile(1, 'Βασίλης')],
        presence: const {},
        availability: stillOpenElsewhere
            ? const {
                1: ProfileAvailability(
                  ProfileLockKind.lockedElsewhere,
                  station: 'POPINIO',
                ),
              }
            : const {1: ProfileAvailability(ProfileLockKind.free)},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showChangeOperatorDialog(
                  ctx,
                  loadProfiles: load,
                  createProfile: (name, _) async => _profile(99, name),
                  activateExisting: (operator) async => picked.add(operator),
                  keepOnlyCurrent: (_) async {},
                  refreshEvery: const Duration(seconds: 5),
                ),
                child: const Text('άνοιγμα'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('άνοιγμα'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Βασίλης'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty, reason: 'όσο το κρατά ο άλλος, δεν πατιέται');

      stillOpenElsewhere = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Βασίλης'));
      await tester.pumpAndSettle();

      expect(picked.single.id, 1);
    },
  );

  testWidgets('κλειδωμένη κάρτα: ο σταθμός γράφεται ΜΙΑ φορά', (tester) async {
    // Η εξήγηση του κλειδώματος αντικαθιστά τη γραμμή «Συνδεδεμένος τώρα» —
    // δύο γραμμές για τον ίδιο σταθμό κάνουν την κάρτα να φλυαρεί.
    await _pumpPicker(
      tester,
      profiles: [_profile(1, 'Βασίλης')],
      presence: const {
        1: [
          OperatorPresenceLine(
            online: true,
            text: 'Συνδεδεμένος τώρα — POPINIO',
          ),
        ],
      },
      availability: const {
        1: ProfileAvailability(
          ProfileLockKind.lockedElsewhere,
          station: 'POPINIO',
        ),
      },
      picked: <Operator>[],
    );

    expect(find.textContaining('POPINIO'), findsOneWidget);
  });

  testWidgets('ελεύθερη κάρτα: η γραμμή σύνδεσης μένει στη θέση της', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      profiles: [_profile(1, 'Βασίλης')],
      presence: const {
        1: [
          OperatorPresenceLine(
            online: false,
            text: 'Τελευταία σύνδεση 24/09/2026 16:55 — PICINIO',
          ),
        ],
      },
      availability: const {1: ProfileAvailability(ProfileLockKind.free)},
      picked: <Operator>[],
    );

    expect(find.textContaining('PICINIO'), findsOneWidget);
  });
}
