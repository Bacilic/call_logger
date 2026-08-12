import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/user_similarity_finder.dart';
import 'package:call_logger/features/calls/controllers/call_submit_controller.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/similar_users_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/*
 * Ταυτοποίηση καλούντα τη στιγμή της ΚΑΤΑΓΡΑΦΗΣ της κλήσης.
 *
 *   flutter test test/features/calls/call_submit_controller_test.dart
 */

class _FakeLookup extends LookupService {
  _FakeLookup(this._users) : super.forTest();

  final List<UserModel> _users;

  @override
  List<UserModel> get users => _users;
}

class _FakePrompts implements CallSubmitPrompts {
  _FakePrompts({this.answer});

  final SimilarUsersDialogResult? answer;

  int asks = 0;
  List<UserSimilarityMatch>? askedMatches;
  String? askedTypedDisplayName;

  @override
  Future<SimilarUsersDialogResult?> resolveSimilarCallers(
    List<UserSimilarityMatch> matches, {
    required String typedDisplayName,
  }) async {
    asks++;
    askedMatches = matches;
    askedTypedDisplayName = typedDisplayName;
    return answer;
  }
}

class _FakeActions implements CallSubmitActions {
  _FakeActions({
    required CallHeaderState initialHeader,
    this.submitResult = true,
  }) : _header = initialHeader;

  CallHeaderState _header;
  final bool submitResult;

  UserModel? attachedCaller;
  bool submitted = false;

  @override
  CallHeaderState get header => _header;

  @override
  void attachExistingCaller(UserModel user) {
    attachedCaller = user;
    _header = CallHeaderState(
      selectedCaller: user,
      callerDisplayText: _header.callerDisplayText,
      departmentText: _header.departmentText,
      selectedPhone: _header.selectedPhone,
    );
  }

  @override
  Future<bool> submitCall() async {
    submitted = true;
    return submitResult;
  }
}

CallHeaderState _header({
  String caller = '',
  UserModel? selectedCaller,
  String phone = '2333',
}) {
  return CallHeaderState(
    selectedCaller: selectedCaller,
    callerDisplayText: caller,
    selectedPhone: phone,
  );
}

UserModel _u({required int id, required String first, required String last}) {
  return UserModel(id: id, firstName: first, lastName: last);
}

void main() {
  final drosos = _u(id: 7, first: 'Βασίλης', last: 'Δρόσος');

  test('επιλεγμένος καλών: καμία ερώτηση, κατευθείαν αποθήκευση', () async {
    final actions = _FakeActions(
      initialHeader: _header(caller: 'Βασίλης Δρόσος', selectedCaller: drosos),
    );
    final prompts = _FakePrompts();

    final outcome = await CallSubmitController(
      actions: actions,
      prompts: prompts,
    ).run(_FakeLookup([drosos]));

    expect(prompts.asks, 0);
    expect(outcome, CallSubmitOutcome.saved);
    expect(actions.submitted, isTrue);
  });

  test('κενός καλών: καμία ερώτηση', () async {
    final actions = _FakeActions(initialHeader: _header());
    final prompts = _FakePrompts();

    final outcome = await CallSubmitController(
      actions: actions,
      prompts: prompts,
    ).run(_FakeLookup([drosos]));

    expect(prompts.asks, 0);
    expect(outcome, CallSubmitOutcome.saved);
  });

  group('ανάστροφο ονοματεπώνυμο «Δρόσος Βασίλης»', () {
    test('ρωτά και συνδέει τον υπάρχοντα όταν ο χρήστης πει ναι', () async {
      final actions = _FakeActions(
        initialHeader: _header(caller: 'Δρόσος Βασίλης'),
      );
      final prompts = _FakePrompts(
        answer: SimilarUsersDialogResult.pickExisting(drosos),
      );

      final outcome = await CallSubmitController(
        actions: actions,
        prompts: prompts,
      ).run(_FakeLookup([drosos]));

      expect(prompts.asks, 1);
      expect(prompts.askedMatches!.single.user.id, 7);
      expect(actions.attachedCaller, same(drosos));
      expect(actions.submitted, isTrue);
      expect(outcome, CallSubmitOutcome.saved);
    });

    test('«κατέγραψε όπως το έγραψα» αποθηκεύει χωρίς σύνδεση', () async {
      final actions = _FakeActions(
        initialHeader: _header(caller: 'Δρόσος Βασίλης'),
      );
      final prompts = _FakePrompts(
        answer: const SimilarUsersDialogResult.continueAsNew(),
      );

      final outcome = await CallSubmitController(
        actions: actions,
        prompts: prompts,
      ).run(_FakeLookup([drosos]));

      expect(actions.attachedCaller, isNull);
      expect(actions.submitted, isTrue);
      expect(outcome, CallSubmitOutcome.saved);
    });

    test('ακύρωση δεν αποθηκεύει τίποτα', () async {
      final actions = _FakeActions(
        initialHeader: _header(caller: 'Δρόσος Βασίλης'),
      );
      final prompts = _FakePrompts(
        answer: const SimilarUsersDialogResult.cancelled(),
      );

      final outcome = await CallSubmitController(
        actions: actions,
        prompts: prompts,
      ).run(_FakeLookup([drosos]));

      expect(actions.submitted, isFalse);
      expect(outcome, CallSubmitOutcome.cancelled);
    });
  });

  test('ανορθογραφία «Βασιλσ Δροσος» ρωτά — η λίστα δεν την πιάνει', () async {
    final actions = _FakeActions(
      initialHeader: _header(caller: 'Βασιλσ Δροσος'),
    );
    final prompts = _FakePrompts(
      answer: const SimilarUsersDialogResult.continueAsNew(),
    );

    await CallSubmitController(
      actions: actions,
      prompts: prompts,
    ).run(_FakeLookup([drosos]));

    expect(prompts.asks, 1);
  });

  test('σκέτο μικρό όνομα «Βασίλης» περνά χωρίς ερώτηση', () async {
    final actions = _FakeActions(initialHeader: _header(caller: 'Βασίλης'));
    final prompts = _FakePrompts();

    final outcome = await CallSubmitController(
      actions: actions,
      prompts: prompts,
    ).run(_FakeLookup([drosos]));

    expect(
      prompts.asks,
      0,
      reason: 'Οι νέοι συνάδελφοι καταχωρούν μόνο μικρά ονόματα',
    );
    expect(outcome, CallSubmitOutcome.saved);
  });

  group('ταυτόσημο ονοματεπώνυμο', () {
    final befani = _u(id: 56, first: 'Σωτηρία', last: 'Μπεφάνη');

    test('συνδέεται σιωπηλά — καμία ερώτηση «Μήπως εννοείτε;»', () async {
      final actions = _FakeActions(
        initialHeader: _header(caller: 'Σωτηρία Μπεφάνη'),
      );
      final prompts = _FakePrompts();

      final outcome = await CallSubmitController(
        actions: actions,
        prompts: prompts,
      ).run(_FakeLookup([befani, drosos]));

      expect(
        prompts.asks,
        0,
        reason:
            'ίδιο όνομα με υπάρχοντα υπάλληλο δεν είναι ερώτημα — ο διάλογος '
            'υπάρχει για ΠΑΡΟΜΟΙΑ ονόματα',
      );
      expect(actions.attachedCaller, same(befani));
      expect(outcome, CallSubmitOutcome.saved);
    });

    test('ίδιο όνομα με διαφορετικά κενά/τόνους πάλι συνδέεται', () async {
      final actions = _FakeActions(
        initialHeader: _header(caller: '  σωτηρια   μπεφανη '),
      );
      final prompts = _FakePrompts();

      await CallSubmitController(
        actions: actions,
        prompts: prompts,
      ).run(_FakeLookup([befani]));

      expect(prompts.asks, 0);
      expect(actions.attachedCaller, same(befani));
    });

    test('δύο συνώνυμοι υπάλληλοι: η επιλογή είναι πραγματική, ρωτά', () async {
      final otherBefani = _u(id: 91, first: 'Σωτηρία', last: 'Μπεφάνη');
      final actions = _FakeActions(
        initialHeader: _header(caller: 'Σωτηρία Μπεφάνη'),
      );
      final prompts = _FakePrompts(
        answer: SimilarUsersDialogResult.pickExisting(otherBefani),
      );

      await CallSubmitController(
        actions: actions,
        prompts: prompts,
      ).run(_FakeLookup([befani, otherBefani]));

      expect(
        prompts.asks,
        1,
        reason: 'δύο εγγραφές με το ίδιο όνομα — μόνο ο χρήστης ξέρει ποια',
      );
      expect(actions.attachedCaller, same(otherBefani));
    });

    test('ανάστροφη σειρά είναι παρόμοια, ΟΧΙ ίδια — εξακολουθεί να ρωτά', () async {
      final actions = _FakeActions(
        initialHeader: _header(caller: 'Μπεφάνη Σωτηρία'),
      );
      final prompts = _FakePrompts(
        answer: const SimilarUsersDialogResult.continueAsNew(),
      );

      await CallSubmitController(
        actions: actions,
        prompts: prompts,
      ).run(_FakeLookup([befani]));

      expect(prompts.asks, 1);
      expect(actions.attachedCaller, isNull);
    });
  });

  test('αποτυχία αποθήκευσης επιστρέφει failed', () async {
    final actions = _FakeActions(
      initialHeader: _header(caller: 'Άσχετο Όνομα'),
      submitResult: false,
    );

    final outcome = await CallSubmitController(
      actions: actions,
      prompts: _FakePrompts(),
    ).run(_FakeLookup([drosos]));

    expect(outcome, CallSubmitOutcome.failed);
  });
}
