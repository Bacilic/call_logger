import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/user_similarity_finder.dart';
import 'package:call_logger/features/calls/controllers/caller_quick_add_controller.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_state.dart'
    show OrphanQuickAddResult;
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/screens/widgets/similar_department_suggestion_dialog.dart';
import 'package:call_logger/features/directory/screens/widgets/similar_users_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Κατάλογος με προκαθορισμένο περιεχόμενο, χωρίς βάση.
class _FakeLookup extends LookupService {
  _FakeLookup({List<UserModel>? users, List<DepartmentModel>? depts})
    : _users = users ?? const [],
      super.forTest() {
    departments = depts ?? [];
  }

  final List<UserModel> _users;

  @override
  List<UserModel> get users => _users;

  @override
  DepartmentModel? findDepartmentByName(String name) {
    final q = name.trim();
    for (final d in departments) {
      if (d.name.trim() == q) return d;
    }
    return null;
  }
}

/// Καταγράφει τι ζητήθηκε από τον χρήστη και δίνει προκαθορισμένες απαντήσεις.
class _FakePrompts implements CallerQuickAddPrompts {
  _FakePrompts({
    this.sharedAssetAnswer = false,
    this.primaryDepartmentAnswer = false,
    this.usersAnswer,
    this.departmentsAnswer,
  });

  final bool sharedAssetAnswer;
  final bool primaryDepartmentAnswer;
  final SimilarUsersDialogResult? usersAnswer;
  final SimilarDepartmentDialogResult? departmentsAnswer;

  final List<String> announcements = [];
  int sharedAssetAsks = 0;
  int primaryDepartmentAsks = 0;
  List<UserSimilarityMatch>? askedUserMatches;
  String? askedDepartmentName;

  @override
  Future<bool> confirmSharedAssetOnConflict(String message) async {
    sharedAssetAsks++;
    return sharedAssetAnswer;
  }

  @override
  Future<bool> confirmPrimaryDepartmentChange({
    required String currentDepartmentName,
    required String newDepartmentName,
  }) async {
    primaryDepartmentAsks++;
    return primaryDepartmentAnswer;
  }

  @override
  Future<SimilarUsersDialogResult?> resolveSimilarCallers(
    List<UserSimilarityMatch> matches, {
    required String typedDisplayName,
    required String typedDepartmentName,
  }) async {
    askedUserMatches = matches;
    return usersAnswer;
  }

  @override
  Future<SimilarDepartmentDialogResult?> resolveSimilarDepartments({
    required Iterable<DepartmentModel> departments,
    required String typedName,
  }) async {
    askedDepartmentName = typedName;
    return departmentsAnswer;
  }

  @override
  void announce(String message) => announcements.add(message);
}

/// Καταγράφει τις ενέργειες αντί να αγγίξει provider ή βάση.
class _FakeActions implements CallerQuickAddActions {
  _FakeActions({
    required CallHeaderState initialHeader,
    this.orphanPreview,
    this.orphanApplied,
    this.associateMessage,
  }) : _header = initialHeader;

  CallHeaderState _header;
  final OrphanQuickAddResult? orphanPreview;
  final OrphanQuickAddResult? orphanApplied;
  final String? associateMessage;

  int orphanCalls = 0;
  int forcedOrphanCalls = 0;
  UserModel? pickedCaller;
  String? pickedDepartment;
  bool associateCalled = false;
  bool? associatedWithPrimaryDepartmentUpdate;

  @override
  CallHeaderState get header => _header;

  @override
  Future<OrphanQuickAddResult?> quickAddOrphan({
    bool forceShared = false,
  }) async {
    orphanCalls++;
    if (forceShared) {
      forcedOrphanCalls++;
      return orphanApplied;
    }
    return orphanPreview;
  }

  @override
  void selectExistingCaller(UserModel user) => pickedCaller = user;

  @override
  void useExistingDepartment(String departmentName) {
    pickedDepartment = departmentName;
    _header = CallHeaderState(
      selectedCaller: _header.selectedCaller,
      callerDisplayText: _header.callerDisplayText,
      departmentText: departmentName,
      selectedPhone: _header.selectedPhone,
    );
  }

  @override
  Future<String?> associate({required bool updatePrimaryDepartment}) async {
    associateCalled = true;
    associatedWithPrimaryDepartmentUpdate = updatePrimaryDepartment;
    return associateMessage;
  }
}

CallHeaderState _newCallerHeader({
  String caller = 'Αναστασία',
  String department = 'Εφημερείο ΤΕΠ',
}) {
  return CallHeaderState(callerDisplayText: caller, departmentText: department);
}

UserModel _user({
  int? id,
  String? firstName,
  String? lastName,
  int? departmentId,
  String? departmentName,
}) {
  return UserModel(
    id: id,
    firstName: firstName,
    lastName: lastName,
    departmentId: departmentId,
    departmentName: departmentName,
  );
}

void main() {
  group('wantsPrimaryDepartmentChange', () {
    test('νέος καλών (χωρίς id) δεν αλλάζει κύριο τμήμα', () {
      expect(
        CallerQuickAddController.wantsPrimaryDepartmentChange(
          callerId: null,
          callerDepartmentId: null,
          callerDepartmentName: '',
          departmentText: 'Εφημερείο ΤΕΠ',
          selectedDepartment: null,
        ),
        isFalse,
      );
    });

    test('ίδιο τμήμα με διαφορετικούς τόνους δεν μετράει ως αλλαγή', () {
      expect(
        CallerQuickAddController.wantsPrimaryDepartmentChange(
          callerId: 5,
          callerDepartmentId: 2,
          callerDepartmentName: 'Εφημερειο ΤΕΠ',
          departmentText: 'Εφημερείο ΤΕΠ',
          selectedDepartment: DepartmentModel(id: 2, name: 'Εφημερείο ΤΕΠ'),
        ),
        isFalse,
      );
    });

    test('υπάρχων χρήστης με άλλο τμήμα ζητά απόφαση', () {
      expect(
        CallerQuickAddController.wantsPrimaryDepartmentChange(
          callerId: 5,
          callerDepartmentId: 2,
          callerDepartmentName: 'Προσωπικού',
          departmentText: 'Εφημερείο ΤΕΠ',
          selectedDepartment: DepartmentModel(id: 9, name: 'Εφημερείο ΤΕΠ'),
        ),
        isTrue,
      );
    });

    test('κενό πεδίο τμήματος δεν ζητά τίποτα', () {
      expect(
        CallerQuickAddController.wantsPrimaryDepartmentChange(
          callerId: 5,
          callerDepartmentId: 2,
          callerDepartmentName: 'Προσωπικού',
          departmentText: '   ',
          selectedDepartment: null,
        ),
        isFalse,
      );
    });
  });

  group('γρήγορη προσθήκη σε τμήμα (orphan)', () {
    test('άρνηση στη σύγκρουση δεν εκτελεί τίποτα', () async {
      final actions = _FakeActions(
        initialHeader: CallHeaderState(
          departmentText: 'Εφημερείο ΤΕΠ',
          selectedPhone: '2201',
        ),
        orphanPreview: const OrphanQuickAddResult(
          requiresConfirmation: true,
          message: 'Το τηλέφωνο ανήκει σε άλλο τμήμα.',
        ),
      );
      final prompts = _FakePrompts(sharedAssetAnswer: false);

      await CallerQuickAddController(
        actions: actions,
        prompts: prompts,
      ).run(null);

      expect(prompts.sharedAssetAsks, 1);
      expect(actions.forcedOrphanCalls, 0);
      expect(actions.associateCalled, isFalse);
      expect(prompts.announcements, isEmpty);
    });

    test('αποδοχή στη σύγκρουση εκτελεί και ανακοινώνει', () async {
      final actions = _FakeActions(
        initialHeader: CallHeaderState(
          departmentText: 'Εφημερείο ΤΕΠ',
          selectedPhone: '2201',
        ),
        orphanPreview: const OrphanQuickAddResult(
          requiresConfirmation: true,
          message: 'Το τηλέφωνο ανήκει σε άλλο τμήμα.',
        ),
        orphanApplied: const OrphanQuickAddResult(
          requiresConfirmation: false,
          message: 'ok',
          successMessage: 'Προστέθηκε ως κοινόχρηστο.',
        ),
      );
      final prompts = _FakePrompts(sharedAssetAnswer: true);

      await CallerQuickAddController(
        actions: actions,
        prompts: prompts,
      ).run(null);

      expect(actions.forcedOrphanCalls, 1);
      expect(prompts.announcements, ['Προστέθηκε ως κοινόχρηστο.']);
      expect(actions.associateCalled, isFalse);
    });
  });

  group('παρόμοιοι καλούντες', () {
    test('«Αναστασία» δίπλα σε «Αναστασία Φούφα» δεν ρωτά καθόλου', () async {
      final actions = _FakeActions(
        initialHeader: _newCallerHeader(),
        associateMessage: 'Καταχωρήθηκε.',
      );
      final prompts = _FakePrompts();
      final lookup = _FakeLookup(
        users: [_user(id: 1, firstName: 'Αναστασία', lastName: 'Φούφα')],
        depts: [DepartmentModel(id: 3, name: 'Εφημερείο ΤΕΠ')],
      );

      await CallerQuickAddController(
        actions: actions,
        prompts: prompts,
      ).run(lookup);

      expect(prompts.askedUserMatches, isNull);
      expect(actions.associateCalled, isTrue);
      expect(prompts.announcements, ['Καταχωρήθηκε.']);
    });

    test('επιλογή υπάρχοντος χρήστη ακυρώνει τη δημιουργία νέου', () async {
      final existing = _user(id: 7, firstName: 'Αναστασία', lastName: 'Φούφα');
      final actions = _FakeActions(
        initialHeader: _newCallerHeader(caller: 'Φούφα Αναστασία'),
      );
      final prompts = _FakePrompts(
        usersAnswer: SimilarUsersDialogResult.pickExisting(existing),
      );
      final lookup = _FakeLookup(
        users: [existing],
        depts: [DepartmentModel(id: 3, name: 'Εφημερείο ΤΕΠ')],
      );

      await CallerQuickAddController(
        actions: actions,
        prompts: prompts,
      ).run(lookup);

      expect(prompts.askedUserMatches, isNotNull);
      expect(actions.pickedCaller, same(existing));
      expect(actions.associateCalled, isFalse);
    });

    test('ακύρωση σταματά τη ροή πριν την καταχώρηση', () async {
      final existing = _user(id: 7, firstName: 'Αναστασία', lastName: 'Φούφα');
      final actions = _FakeActions(
        initialHeader: _newCallerHeader(caller: 'Αναστασία Φούφα'),
      );
      final prompts = _FakePrompts(
        usersAnswer: const SimilarUsersDialogResult.cancelled(),
      );

      await CallerQuickAddController(
        actions: actions,
        prompts: prompts,
      ).run(_FakeLookup(users: [existing]));

      expect(actions.pickedCaller, isNull);
      expect(actions.associateCalled, isFalse);
    });

    test('«είναι νέα εγγραφή» συνεχίζει στην καταχώρηση', () async {
      final existing = _user(id: 7, firstName: 'Αναστασία', lastName: 'Φούφα');
      final actions = _FakeActions(
        initialHeader: _newCallerHeader(caller: 'Αναστασία Φούφα'),
      );
      final prompts = _FakePrompts(
        usersAnswer: const SimilarUsersDialogResult.continueAsNew(),
      );
      final lookup = _FakeLookup(
        users: [existing],
        depts: [DepartmentModel(id: 3, name: 'Εφημερείο ΤΕΠ')],
      );

      await CallerQuickAddController(
        actions: actions,
        prompts: prompts,
      ).run(lookup);

      expect(actions.associateCalled, isTrue);
    });
  });

  group('παρόμοια τμήματα', () {
    test('γνωστό τμήμα δεν παράγει ερώτηση', () async {
      final actions = _FakeActions(
        initialHeader: _newCallerHeader(department: 'Εφημερείο ΤΕΠ'),
      );
      final prompts = _FakePrompts();
      final lookup = _FakeLookup(
        depts: [DepartmentModel(id: 3, name: 'Εφημερείο ΤΕΠ')],
      );

      await CallerQuickAddController(
        actions: actions,
        prompts: prompts,
      ).run(lookup);

      expect(prompts.askedDepartmentName, isNull);
      expect(actions.associateCalled, isTrue);
    });

    test('επιλογή υπάρχοντος τμήματος το γράφει και συνεχίζει', () async {
      final actions = _FakeActions(
        initialHeader: _newCallerHeader(department: 'Προσωπικού'),
      );
      final prompts = _FakePrompts(
        departmentsAnswer: SimilarDepartmentDialogResult.pickExisting(
          DepartmentModel(id: 4, name: 'Γραφείο Προσωπικού'),
        ),
      );

      await CallerQuickAddController(actions: actions, prompts: prompts).run(
        _FakeLookup(
          depts: [DepartmentModel(id: 4, name: 'Γραφείο Προσωπικού')],
        ),
      );

      expect(prompts.askedDepartmentName, 'Προσωπικού');
      expect(actions.pickedDepartment, 'Γραφείο Προσωπικού');
      expect(actions.associateCalled, isTrue);
    });

    test('ακύρωση στην πρόταση τμήματος σταματά την καταχώρηση', () async {
      final actions = _FakeActions(
        initialHeader: _newCallerHeader(department: 'Προσωπικού'),
      );
      final prompts = _FakePrompts(
        departmentsAnswer: const SimilarDepartmentDialogResult.cancelled(),
      );

      await CallerQuickAddController(actions: actions, prompts: prompts).run(
        _FakeLookup(
          depts: [DepartmentModel(id: 4, name: 'Γραφείο Προσωπικού')],
        ),
      );

      expect(actions.associateCalled, isFalse);
    });
  });

  group('κύριο τμήμα υπάρχοντος καλούντα', () {
    // Το όνομα τμήματος είναι κανονικό πεδίο του μοντέλου — κανένα singleton.
    test('«Ναι» περνά την αλλαγή κύριου τμήματος στην καταχώρηση', () async {
      final caller = _user(
        id: 5,
        firstName: 'Βαρβάρα',
        departmentId: 2,
        departmentName: 'Προσωπικού',
      );
      final actions = _FakeActions(
        initialHeader: CallHeaderState(
          selectedCaller: caller,
          callerDisplayText: 'Βαρβάρα',
          departmentText: 'Εφημερείο ΤΕΠ',
        ),
      );
      final prompts = _FakePrompts(primaryDepartmentAnswer: true);
      final lookup = _FakeLookup(
        depts: [DepartmentModel(id: 9, name: 'Εφημερείο ΤΕΠ')],
      );

      await CallerQuickAddController(
        actions: actions,
        prompts: prompts,
      ).run(lookup);

      expect(prompts.primaryDepartmentAsks, 1);
      expect(actions.associatedWithPrimaryDepartmentUpdate, isTrue);
    });

    test('«Όχι» καταχωρεί χωρίς αλλαγή κύριου τμήματος', () async {
      final caller = _user(
        id: 5,
        firstName: 'Βαρβάρα',
        departmentId: 2,
        departmentName: 'Προσωπικού',
      );
      final actions = _FakeActions(
        initialHeader: CallHeaderState(
          selectedCaller: caller,
          callerDisplayText: 'Βαρβάρα',
          departmentText: 'Εφημερείο ΤΕΠ',
        ),
      );
      final prompts = _FakePrompts(primaryDepartmentAnswer: false);
      final lookup = _FakeLookup(
        depts: [DepartmentModel(id: 9, name: 'Εφημερείο ΤΕΠ')],
      );

      await CallerQuickAddController(
        actions: actions,
        prompts: prompts,
      ).run(lookup);

      expect(prompts.primaryDepartmentAsks, 1);
      expect(actions.associatedWithPrimaryDepartmentUpdate, isFalse);
      expect(actions.associateCalled, isTrue);
    });
  });

  test('χωρίς καμία ερώτηση η ροή φτάνει στην καταχώρηση', () async {
    final actions = _FakeActions(
      initialHeader: _newCallerHeader(caller: 'Νέος Άνθρωπος'),
      associateMessage: 'Καταχωρήθηκε.',
    );
    final prompts = _FakePrompts();
    final lookup = _FakeLookup(
      depts: [DepartmentModel(id: 3, name: 'Εφημερείο ΤΕΠ')],
    );

    await CallerQuickAddController(
      actions: actions,
      prompts: prompts,
    ).run(lookup);

    expect(prompts.primaryDepartmentAsks, 0);
    expect(actions.associatedWithPrimaryDepartmentUpdate, isFalse);
    expect(prompts.announcements, ['Καταχωρήθηκε.']);
  });
}
