// Unit test: LansweeperAiPresenter — καθαρή λογική AI (χωρίς widget).
//
//   flutter test test/features/history/lansweeper_ai_presenter_test.dart

import 'package:call_logger/core/services/ai_ticket_suggestion_service.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_ai_presenter.dart';
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
  );
}

ReportCallItem _item({
  required String key,
  required CallModel call,
  String caller = 'Καλών',
}) {
  return ReportCallItem(
    key: key,
    call: call,
    caller: caller,
    notes: 'Σημείωση',
    details: '',
    durationSeconds: 0,
  );
}

void main() {
  group('LansweeperAiPresenter.fallbackMessage', () {
    const fromModel = 'gemini-primary';
    const toModel = 'gemini-fallback';

    test('rateLimited', () {
      final message = LansweeperAiPresenter.fallbackMessage(
        fromModel: fromModel,
        toModel: toModel,
        reason: AiFallbackReason.rateLimited,
      );
      expect(message, contains('ποσόστωση (429)'));
      expect(
        message,
        'Το μοντέλο «$fromModel» (ποσόστωση (429)). '
        'Καλούμε το εφεδρικό μοντέλο: «$toModel».',
      );
    });

    test('overloaded', () {
      final message = LansweeperAiPresenter.fallbackMessage(
        fromModel: fromModel,
        toModel: toModel,
        reason: AiFallbackReason.overloaded,
      );
      expect(message, contains('υπερφόρτωση (503)'));
      expect(
        message,
        'Το μοντέλο «$fromModel» (υπερφόρτωση (503)). '
        'Καλούμε το εφεδρικό μοντέλο: «$toModel».',
      );
    });

    test('cooldown', () {
      final message = LansweeperAiPresenter.fallbackMessage(
        fromModel: fromModel,
        toModel: toModel,
        reason: AiFallbackReason.cooldown,
      );
      expect(message, contains('αναμονή ποσόστωσης (cooldown)'));
      expect(
        message,
        'Το μοντέλο «$fromModel» (αναμονή ποσόστωσης (cooldown)). '
        'Καλούμε το εφεδρικό μοντέλο: «$toModel».',
      );
    });

    test('modelFailure', () {
      final message = LansweeperAiPresenter.fallbackMessage(
        fromModel: fromModel,
        toModel: toModel,
        reason: AiFallbackReason.modelFailure,
      );
      expect(message, contains('σφάλμα μοντέλου'));
      expect(
        message,
        'Το μοντέλο «$fromModel» (σφάλμα μοντέλου). '
        'Καλούμε το εφεδρικό μοντέλο: «$toModel».',
      );
    });
  });

  group('LansweeperAiPresenter.isCooldownActive', () {
    final now = DateTime(2026, 7, 5, 12, 0, 0);

    test('null until -> false', () {
      expect(LansweeperAiPresenter.isCooldownActive(null, now), isFalse);
    });

    test('μελλοντικό until -> true', () {
      final until = now.add(const Duration(seconds: 30));
      expect(LansweeperAiPresenter.isCooldownActive(until, now), isTrue);
    });

    test('παρελθοντικό until -> false', () {
      final until = now.subtract(const Duration(seconds: 1));
      expect(LansweeperAiPresenter.isCooldownActive(until, now), isFalse);
    });
  });

  group('LansweeperAiPresenter.cooldownRemainingSeconds', () {
    final now = DateTime(2026, 7, 5, 12, 0, 0);

    test('null until -> null', () {
      expect(
        LansweeperAiPresenter.cooldownRemainingSeconds(null, now),
        isNull,
      );
    });

    test('παρελθόν until -> null', () {
      final until = now.subtract(const Duration(seconds: 5));
      expect(
        LansweeperAiPresenter.cooldownRemainingSeconds(until, now),
        isNull,
      );
    });

    test('μέλλον until -> σωστά δευτερόλεπτα', () {
      final until = now.add(const Duration(seconds: 42));
      expect(
        LansweeperAiPresenter.cooldownRemainingSeconds(until, now),
        42,
      );
    });
  });

  group('LansweeperAiPresenter.buildRequest', () {
    test('μοναδικοποίηση πεδίων, combined issue, pass-through title/notes/solution', () {
      final selected = <ReportCallItem>[
        _item(
          key: 'a',
          caller: 'Γιάννης',
          call: _call(
            callerText: 'Γιάννης',
            equipmentText: 'PC-01',
            departmentText: ' IT ',
            category: 'Hardware',
            issue: 'Πρόβλημα Α',
            date: '2026-03-15',
            time: '10:30:00',
          ),
        ),
        _item(
          key: 'b',
          caller: 'Μαρία',
          call: _call(
            callerText: 'Μαρία',
            equipmentText: 'PC-01',
            departmentText: 'IT',
            category: 'Software',
            issue: 'Πρόβλημα Β',
            date: '2026-03-16',
            time: '11:00:00',
          ),
        ),
      ];

      const titleText = 'Τίτλος δοκιμής';
      const notesText = 'Σημειώσεις δοκιμής';
      const solutionText = 'Λύση δοκιμής';

      final request = LansweeperAiPresenter.buildRequest(
        selected: selected,
        titleText: titleText,
        notesText: notesText,
        solutionText: solutionText,
      );

      expect(request.callerText, 'Γιάννης, Μαρία');
      expect(request.equipmentText, 'PC-01');
      expect(request.departmentText, 'IT');
      expect(request.category, 'Hardware, Software');
      expect(
        request.issue,
        LansweeperReportItemMapper.combinedAiIssue(selected),
      );
      expect(request.titleText, titleText);
      expect(request.notesText, notesText);
      expect(request.solutionText, solutionText);
    });
  });

  group('LansweeperAiPresenter.prefillTitle', () {
    test('κενή κατηγορία + id -> Κλήση #<id>', () {
      expect(
        LansweeperAiPresenter.prefillTitle(category: '', id: 42),
        'Κλήση #42',
      );
    });

    test('κατηγορία + id -> [<cat>] #<id>', () {
      expect(
        LansweeperAiPresenter.prefillTitle(category: 'Hardware', id: 7),
        '[Hardware] #7',
      );
    });

    test('κενή κατηγορία χωρίς id -> Κλήση', () {
      expect(
        LansweeperAiPresenter.prefillTitle(category: '', id: null),
        'Κλήση',
      );
    });
  });
}
