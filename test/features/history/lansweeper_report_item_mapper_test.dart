// Unit test: LansweeperReportItemMapper — καθαρή λογική στοιχείων αναφοράς.
//
//   flutter test test/features/history/lansweeper_report_item_mapper_test.dart

import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/models/lansweeper_sync_state.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_report_item_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

CallModel _call({
  int? id,
  String? callerText,
  String? issue,
  String? equipmentText,
  String? departmentText,
  String? category,
  String? date,
  String? time,
  int? duration,
  String? lansweeperState,
}) {
  return CallModel(
    id: id,
    callerText: callerText,
    issue: issue,
    equipmentText: equipmentText,
    departmentText: departmentText,
    category: category,
    date: date,
    time: time,
    duration: duration,
    lansweeperState: lansweeperState,
  );
}

ReportCallItem _item({
  required String key,
  required CallModel call,
  String caller = 'Καλών',
  String notes = 'Σημείωση',
  String details = '',
  int durationSeconds = 0,
}) {
  return ReportCallItem(
    key: key,
    call: call,
    caller: caller,
    notes: notes,
    details: details,
    durationSeconds: durationSeconds,
  );
}

void main() {
  group('LansweeperReportItemMapper.callerLabel / notes / details', () {
    test('επιστρέφει παύλα όταν τα πεδία είναι κενά', () {
      final call = _call();
      expect(LansweeperReportItemMapper.callerLabel(call), '-');
      expect(LansweeperReportItemMapper.notes(call), '-');
      expect(LansweeperReportItemMapper.details(call), '');
    });

    test('επιστρέφει τιμές όταν τα πεδία είναι γεμάτα', () {
      final call = _call(
        callerText: '  Γιάννης  ',
        issue: '  Πρόβλημα δικτύου  ',
        equipmentText: 'PC-01',
        departmentText: 'IT',
        category: 'Hardware',
      );
      expect(LansweeperReportItemMapper.callerLabel(call), 'Γιάννης');
      expect(LansweeperReportItemMapper.notes(call), 'Πρόβλημα δικτύου');
      expect(
        LansweeperReportItemMapper.details(call),
        'Κωδικός εξοπλισμού: PC-01 • Τμήμα: IT • Κατηγορία προβλήματος: Hardware',
      );
    });
  });

  group('LansweeperReportItemMapper.durationLabel / totalDurationLabel', () {
    test('durationLabel χωρίς ώρες: λεπτά:δευτερόλεπτα', () {
      expect(LansweeperReportItemMapper.durationLabel(125), '02:05');
      expect(LansweeperReportItemMapper.durationLabel(-5), '00:00');
    });

    test('durationLabel με ώρες: ώρες:λεπτά', () {
      expect(LansweeperReportItemMapper.durationLabel(3661), '01:01');
    });

    test('totalDurationLabel στρογγυλοποίηση προς τα πάνω και όριο 60 λ', () {
      expect(LansweeperReportItemMapper.totalDurationLabel(59), '1 λ');
      expect(LansweeperReportItemMapper.totalDurationLabel(3600), '1 ώρ 00 λ');
      expect(LansweeperReportItemMapper.totalDurationLabel(3599), '1 ώρ 00 λ');
      expect(LansweeperReportItemMapper.totalDurationLabel(3660), '1 ώρ 01 λ');
    });
  });

  group('LansweeperReportItemMapper.toItems', () {
    test('κλειδί id_<id> όταν υπάρχει id, αλλιώς idx_<i>', () {
      final items = LansweeperReportItemMapper.toItems(<CallModel>[
        _call(id: 42, callerText: 'Α', issue: 'x'),
        _call(callerText: 'Β', issue: 'y'),
      ]);

      expect(items, hasLength(2));
      expect(items[0].key, 'id_42');
      expect(items[1].key, 'idx_1');
      expect(items[0].caller, 'Α');
      expect(items[0].notes, 'x');
    });
  });

  group('LansweeperReportItemMapper.groupByCaller', () {
    test('ομαδοποιεί ανά καλούντα', () {
      final items = <ReportCallItem>[
        _item(key: 'a', call: _call(), caller: 'Γιάννης'),
        _item(key: 'b', call: _call(), caller: 'Μαρία'),
        _item(key: 'c', call: _call(), caller: 'Γιάννης'),
      ];

      final grouped = LansweeperReportItemMapper.groupByCaller(items);

      expect(grouped.keys, containsAll(<String>['Γιάννης', 'Μαρία']));
      expect(grouped['Γιάννης'], hasLength(2));
      expect(grouped['Μαρία'], hasLength(1));
    });
  });

  group('LansweeperReportItemMapper.combinedSelectedNotes', () {
    test('μονή επιλογή: επιστρέφει τις σημειώσεις ως έχουν', () {
      final selected = <ReportCallItem>[
        _item(key: 'a', call: _call(), notes: 'Μόνη σημείωση'),
      ];
      expect(
        LansweeperReportItemMapper.combinedSelectedNotes(selected),
        'Μόνη σημείωση',
      );
    });

    test('πολλαπλή επιλογή: πρόθεμα ημερομηνίας ανά γραμμή', () {
      final selected = <ReportCallItem>[
        _item(
          key: 'a',
          call: _call(date: '2026-03-15', time: '10:30:00'),
          caller: 'Γιάννης',
          notes: 'Πρώτο',
          details: 'Λεπτομέρεια Α',
        ),
        _item(
          key: 'b',
          call: _call(date: '2026-03-16', time: '11:00:00'),
          caller: 'Μαρία',
          notes: 'Δεύτερο',
        ),
      ];

      final combined =
          LansweeperReportItemMapper.combinedSelectedNotes(selected);

      expect(combined, contains('[15/03/2026 10:30] Γιάννης: Πρώτο • Λεπτομέρεια Α'));
      expect(combined, contains('[16/03/2026 11:00] Μαρία: Δεύτερο'));
      expect(combined.split('\n'), hasLength(2));
    });
  });

  group('LansweeperReportItemMapper.combinedUniqueCallField', () {
    test('μοναδικές μη κενές τιμές, join με κόμμα', () {
      final selected = <ReportCallItem>[
        _item(
          key: 'a',
          call: _call(departmentText: ' IT '),
        ),
        _item(
          key: 'b',
          call: _call(departmentText: 'IT'),
        ),
        _item(
          key: 'c',
          call: _call(departmentText: '  '),
        ),
        _item(
          key: 'd',
          call: _call(departmentText: 'HR'),
        ),
      ];

      expect(
        LansweeperReportItemMapper.combinedUniqueCallField(
          selected,
          (call) => call.departmentText,
        ),
        'IT, HR',
      );
    });
  });

  group('LansweeperReportItemMapper normalized state helpers', () {
    test('κενή κατάσταση -> unsent', () {
      final item = _item(
        key: 'a',
        call: _call(lansweeperState: null),
      );
      expect(
        LansweeperReportItemMapper.normalizedLansweeperState(item),
        LansweeperSyncState.unsent,
      );
      expect(LansweeperReportItemMapper.isRegisteredCall(item), isFalse);
      expect(LansweeperReportItemMapper.isFailedCall(item), isFalse);
    });

    test('sent και failed αναγνωρίζονται σωστά', () {
      final sent = _item(
        key: 's',
        call: _call(lansweeperState: LansweeperSyncState.sent),
      );
      final failed = _item(
        key: 'f',
        call: _call(lansweeperState: LansweeperSyncState.failed),
      );

      expect(LansweeperReportItemMapper.isRegisteredCall(sent), isTrue);
      expect(LansweeperReportItemMapper.isRegisteredCall(failed), isFalse);
      expect(LansweeperReportItemMapper.isFailedCall(failed), isTrue);
      expect(LansweeperReportItemMapper.isFailedCall(sent), isFalse);
    });
  });
}
