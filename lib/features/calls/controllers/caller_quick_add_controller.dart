import '../../../core/services/lookup_service.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../../core/utils/user_similarity_finder.dart';
import '../../directory/models/department_model.dart';
import '../../directory/screens/widgets/similar_department_suggestion_dialog.dart';
import '../../directory/screens/widgets/similar_users_dialog.dart';
import '../models/user_model.dart';
import '../provider/call_header_provider.dart';
import '../provider/smart_entity_selector_state.dart' show OrphanQuickAddResult;

/// Ερωτήσεις προς τον χρήστη κατά τη γρήγορη καταχώρηση.
///
/// Το UI τις υλοποιεί με διαλόγους· τα τεστ με προκαθορισμένες απαντήσεις.
/// Καμία μέθοδος δεν επιστρέφει `BuildContext` — ο controller δεν γνωρίζει Flutter.
abstract class CallerQuickAddPrompts {
  /// Σύγκρουση δεδομένων στη γρήγορη προσθήκη σε τμήμα: να προχωρήσει ως κοινόχρηστο;
  Future<bool> confirmSharedAssetOnConflict(String message);

  /// Να γίνει το νέο τμήμα κύριο τμήμα του υπάρχοντος χρήστη;
  Future<bool> confirmPrimaryDepartmentChange({
    required String currentDepartmentName,
    required String newDepartmentName,
  });

  /// Υπάρχουν ίδιες ή παρόμοιες εγγραφές καταλόγου· τι κάνουμε;
  ///
  /// Το [typedDisplayName] είναι το όνομα όπως το πληκτρολόγησε ο χρήστης και
  /// το [typedDepartmentName] το τμήμα της νέας εγγραφής (κενό = χωρίς τμήμα) —
  /// ο διάλογος τα δείχνει δίπλα στα υπάρχοντα για σύγκριση.
  ///
  /// `null` σημαίνει «δεν ρωτήθηκε» και η ροή συνεχίζει ανενόχλητη.
  Future<SimilarUsersDialogResult?> resolveSimilarCallers(
    List<UserSimilarityMatch> matches, {
    required String typedDisplayName,
    required String typedDepartmentName,
  });

  /// Το τμήμα θα δημιουργηθεί ως νέο ενώ υπάρχουν παρόμοια· τι κάνουμε;
  ///
  /// `null` σημαίνει «δεν βρέθηκαν προτάσεις» και η ροή συνεχίζει ανενόχλητη.
  Future<SimilarDepartmentDialogResult?> resolveSimilarDepartments({
    required Iterable<DepartmentModel> departments,
    required String typedName,
  });

  /// Μήνυμα αποτελέσματος προς τον χρήστη (snackbar στο UI).
  void announce(String message);
}

/// Ενέργειες πάνω στην κατάσταση της κεφαλίδας κλήσης.
///
/// Λεπτή αφαίρεση του notifier ώστε ο controller να τεστάρεται χωρίς Riverpod,
/// χωρίς `testWidgets` και χωρίς πραγματική βάση.
abstract class CallerQuickAddActions {
  /// Η ΤΡΕΧΟΥΣΑ κατάσταση — διαβάζεται ξανά μετά από κάθε διάλογο, ποτέ cached.
  CallHeaderState get header;

  Future<OrphanQuickAddResult?> quickAddOrphan({bool forceShared = false});

  /// Ο χρήστης διάλεξε υπάρχουσα εγγραφή αντί για νέα.
  void selectExistingCaller(UserModel user);

  /// Ο χρήστης διάλεξε υπάρχον τμήμα αντί για νέο.
  void useExistingDepartment(String departmentName);

  /// Η καθαυτή καταχώρηση· επιστρέφει μήνυμα προς εμφάνιση ή `null`.
  Future<String?> associate({required bool updatePrimaryDepartment});
}

/// Ενορχηστρώνει τη γρήγορη καταχώρηση καλούντα (κουμπί «Προσθήκη»).
///
/// Σειρά βημάτων: orphan quick-add → κύριο τμήμα → παρόμοιοι χρήστες →
/// παρόμοια τμήματα → καταχώρηση. Κάθε βήμα μπορεί να τερματίσει τη ροή.
class CallerQuickAddController {
  const CallerQuickAddController({
    required this.actions,
    required this.prompts,
  });

  final CallerQuickAddActions actions;
  final CallerQuickAddPrompts prompts;

  /// True όταν η αλλαγή τμήματος αφορά υπάρχοντα χρήστη και άρα μπορεί να
  /// μεταβάλει το κύριο τμήμα του.
  ///
  /// Καθαρή συνάρτηση με ρητές παραμέτρους: η συνθήκη είναι δυσνόητη και
  /// αξίζει δικό της τεστ χωρίς κατασκευή ολόκληρου μοντέλου.
  static bool wantsPrimaryDepartmentChange({
    required int? callerId,
    required int? callerDepartmentId,
    required String callerDepartmentName,
    required String departmentText,
    required DepartmentModel? selectedDepartment,
  }) {
    if (callerId == null) return false;
    final next = departmentText.trim();
    if (next.isEmpty) return false;

    final nextNorm = SearchTextNormalizer.normalizeForSearch(next);
    if (nextNorm.isEmpty) return false;

    final oldNorm = SearchTextNormalizer.normalizeForSearch(
      callerDepartmentName.trim(),
    );
    if (nextNorm == oldNorm) return false;

    return selectedDepartment?.id != callerDepartmentId ||
        (callerDepartmentId == null && selectedDepartment == null);
  }

  Future<void> run(LookupService? lookup) async {
    if (actions.header.needsOrphanDepartmentQuickAddResolved(lookup)) {
      await _runOrphanQuickAdd();
      return;
    }

    final updatePrimaryDepartment = await _resolvePrimaryDepartment(lookup);
    if (!await _resolveSimilarCallers(lookup)) return;
    if (!await _resolveSimilarDepartments(lookup)) return;

    final message = await actions.associate(
      updatePrimaryDepartment: updatePrimaryDepartment,
    );
    if (message != null) prompts.announce(message);
  }

  /// Γρήγορη προσθήκη τηλεφώνου/εξοπλισμού σε τμήμα χωρίς καλούντα.
  Future<void> _runOrphanQuickAdd() async {
    final preview = await actions.quickAddOrphan();
    if (preview == null) return;

    if (!preview.requiresConfirmation) {
      final message = preview.successMessage;
      if (message != null) prompts.announce(message);
      return;
    }

    final approved = await prompts.confirmSharedAssetOnConflict(
      preview.message,
    );
    if (!approved) return;

    final applied = await actions.quickAddOrphan(forceShared: true);
    final message = applied?.successMessage;
    if (message != null) prompts.announce(message);
  }

  /// Επιστρέφει αν το τμήμα της κλήσης θα γίνει κύριο τμήμα του καλούντα.
  ///
  /// Άγνωστη απάντηση (κλείσιμο διαλόγου) σημαίνει «όχι» — η ροή δεν διακόπτεται.
  Future<bool> _resolvePrimaryDepartment(LookupService? lookup) async {
    final header = actions.header;
    final caller = header.selectedCaller;
    final departmentText = header.departmentText.trim();
    final selectedDepartment = departmentText.isEmpty
        ? null
        : lookup?.findDepartmentByName(departmentText);

    final currentDepartment = (caller?.departmentName ?? '').trim();
    final wantsChange = wantsPrimaryDepartmentChange(
      callerId: caller?.id,
      callerDepartmentId: caller?.departmentId,
      callerDepartmentName: currentDepartment,
      departmentText: departmentText,
      selectedDepartment: selectedDepartment,
    );
    if (!wantsChange) return false;

    // Χρήστης χωρίς τμήμα: η ανάθεση είναι αυτονόητη, δεν ρωτάμε.
    if (currentDepartment.isEmpty) return true;

    return prompts.confirmPrimaryDepartmentChange(
      currentDepartmentName: currentDepartment,
      newDepartmentName: selectedDepartment?.name ?? departmentText,
    );
  }

  /// `false` όταν η ροή πρέπει να σταματήσει (ακύρωση ή επιλογή υπάρχοντος).
  Future<bool> _resolveSimilarCallers(LookupService? lookup) async {
    if (lookup == null) return true;
    if (!actions.header.needsNewCallerCreation) return true;

    final matches = UserSimilarityFinder.findSimilarUsersFromCallerText(
      users: lookup.users,
      callerDisplayText: actions.header.normalizedCallerDisplayText,
    );
    if (matches.isEmpty) return true;

    final result = await prompts.resolveSimilarCallers(
      matches,
      typedDisplayName: actions.header.normalizedCallerDisplayText,
      typedDepartmentName: actions.header.departmentText.trim(),
    );
    if (result == null) return true;
    if (result.isCancelled) return false;

    final picked = result.selectedUser;
    if (picked == null) return true;

    // Ο καλών υπάρχει ήδη: κουμπώνει στη φόρμα και δεν δημιουργείται νέα εγγραφή.
    actions.selectExistingCaller(picked);
    return false;
  }

  /// `false` όταν η ροή πρέπει να σταματήσει (ακύρωση).
  Future<bool> _resolveSimilarDepartments(LookupService? lookup) async {
    if (lookup == null) return true;

    // Ξαναδιαβάζεται: το προηγούμενο βήμα μπορεί να έχει αλλάξει το τμήμα.
    final typedName = actions.header.departmentText.trim();
    if (typedName.isEmpty) return true;
    if (lookup.findDepartmentByName(typedName) != null) return true;

    final result = await prompts.resolveSimilarDepartments(
      departments: lookup.departments,
      typedName: typedName,
    );
    if (result == null) return true;
    if (result.isCancelled) return false;

    final picked = result.selectedDepartment;
    if (picked != null) actions.useExistingDepartment(picked.name);
    return true;
  }
}
