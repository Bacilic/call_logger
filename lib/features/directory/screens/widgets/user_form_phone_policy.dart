import '../../../../core/directory/phone_department_policy.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/phone_list_parser.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../calls/models/equipment_model.dart';
import '../../models/department_kind.dart';
import '../../services/bulk_user_actions.dart';
import '../../services/phone_transfer_split.dart';
import '../../services/user_equipment_codes.dart';
import 'asset_fate_on_department_change.dart';
import 'shared_asset_disconnect_dialog.dart';
import 'user_form_dialog.dart';
import 'user_phone_department_conflict_dialog.dart';

/// Πολιτική τηλεφώνων της φόρμας υπαλλήλου: συγκρούσεις τμήματος και
/// αποσύνδεση αποκλειστικών αριθμών που αφαιρέθηκαν.
///
/// Συνεργάτης του [UserFormDialogState] (Σύνθεση).
class UserFormPhonePolicy {
  UserFormPhonePolicy(this.host);

  final UserFormDialogState host;

  List<String> _removedPhonesFromField() {
    final before = PhoneListParser.splitPhones(host.snapPhone);
    final after = PhoneListParser.splitPhones(
      host.phoneController.text,
    ).toSet();
    return before.where((p) => !after.contains(p)).toList();
  }

  /// Τηλέφωνα που αφαιρούνται από το πεδίο και συνδέονται μόνο με τον τρέχοντα χρήστη.
  List<String> _exclusiveRemovedPhones() {
    final editingId = host.widget.initialUser?.id;
    if (!host.isEdit || editingId == null) return const [];

    final removed = _removedPhonesFromField();
    if (removed.isEmpty) return const [];

    final exclusive = <String>[];
    for (final phone in removed) {
      final owners = host.widget.notifier.allUsersForUi.where((u) {
        if (u.isDeleted) return false;
        return u.phones.any((p) => p.trim() == phone.trim());
      }).toList();
      if (owners.length == 1 && owners.first.id == editingId) {
        exclusive.add(phone);
      }
    }
    return exclusive;
  }

  ({int? id, String? name}) resolveSourceDepartmentForDisconnect() {
    final typed = host.departmentController.text.trim();
    if (typed.isEmpty) return (id: null, name: null);

    final key = SearchTextNormalizer.normalizeForSearch(typed);
    if (key.isEmpty) return (id: null, name: null);

    for (final d in LookupService.instance.departments) {
      if (d.isDeleted) continue;
      if (SearchTextNormalizer.normalizeForSearch(d.name) == key) {
        return (id: d.id, name: d.name.trim());
      }
    }
    return (id: null, name: null);
  }

  /// Άλλαξε το τμήμα σε αυτή την επεξεργασία;
  bool get departmentChanged =>
      SearchTextNormalizer.normalizeForSearch(host.departmentController.text) !=
      host.snapDepartmentNorm;

  /// Τα τηλέφωνα που ο υπάλληλος ΕΙΧΕ ήδη και παραμένουν στο πεδίο.
  ///
  /// Μόνο αυτά μπορούν να «μείνουν πίσω»: ένας αριθμός που μόλις
  /// πληκτρολογήθηκε δεν ήταν ποτέ του παλιού τμήματος.
  List<String> _phonesThatCouldStayBehind() {
    final current = PhoneListParser.splitPhones(
      host.phoneController.text,
    ).map((p) => p.trim()).toSet();
    return [
      for (final p in PhoneListParser.splitPhones(host.snapPhone))
        if (current.contains(p.trim())) p.trim(),
    ];
  }

  /// Ρωτά τι απογίνονται τα τηλέφωνα όταν αλλάζει το τμήμα, με τις ΙΔΙΕΣ
  /// ερωτήσεις που κάνει και το «+» της φόρμας κλήσης.
  ///
  /// Κενές λίστες σημαίνουν «όλα ακολουθούν». `null` σημαίνει ότι ο χρήστης
  /// ακύρωσε.
  ///
  /// Κοινό τηλέφωνο (το κρατούν και συνάδελφοι) ρωτιέται **μία** φορά, στο
  /// «Κοινό τηλέφωνο» — όχι στη γενική ερώτηση ούτε στη «Σύγκρουση τοποθεσίας
  /// τηλεφώνου» (αποφάσεις Διευθυντή 04/10).
  Future<PhoneDepartmentChangeAnswer?>
  confirmPhoneFateOnDepartmentChange() async {
    const nothing = (
      staying: <String>{},
      leftWithCoOwners: <String>{},
      takenFromCoOwners: <String>{},
    );
    if (!host.isEdit || host.widget.isClone) return nothing;
    if (!departmentChanged) return nothing;

    final candidates = _phonesThatCouldStayBehind();
    if (candidates.isEmpty) return nothing;

    if (!host.mounted) return null;
    // Τα εσωτερικά του κέντρου μας δεν ακολουθούν έξω από το νοσοκομείο.
    final split = splitPhonesForDepartmentChange(
      phones: candidates,
      targetKind: targetDepartmentKind,
      rules: host.catalogValidationRules,
    );
    // Ο κανόνας τρέχει ΠΡΙΝ την ερώτηση: ο λόγος που ένας αριθμός δεν μπορεί
    // να μείνει πίσω δεν εξαρτάται από την απάντηση, και ο χρήστης πρέπει να
    // τον ξέρει όσο ακόμη αποφασίζει.
    final plan = planPhoneStayBehind(
      phones: split.negotiable,
      userName: host.buildUserDisplayName(),
      oldDepartmentId: host.widget.initialUser?.departmentId,
      editingUserId: host.widget.initialUser?.id,
      lookup: LookupService.instance,
    );
    return askPhonesOnDepartmentChange(
      host.context,
      split: split,
      plan: plan,
      targetKind: targetDepartmentKind,
      userDisplayName: host.buildUserDisplayName(),
      sourceDepartmentName: host.widget.initialUser?.departmentName,
      targetDepartmentName: host.departmentController.text.trim(),
    );
  }

  /// Το Είδος του τμήματος στο οποίο πάει ο υπάλληλος.
  ///
  /// Διαβάζεται από το **πεδίο** της φόρμας και όχι από την αποθηκευμένη τιμή:
  /// η απόφαση αφορά εκεί που πάει, όχι εκεί που ήταν. Όνομα που δεν υπάρχει
  /// ακόμη στον κατάλογο θα γίνει νέο τμήμα του νοσοκομείου — η ίδια παραδοχή
  /// με τη μαζική μεταφορά.
  DepartmentKind get targetDepartmentKind =>
      LookupService.instance
          .findDepartmentByName(host.departmentController.text)
          ?.kind ??
      DepartmentKind.hospital;

  /// Ρωτά τι απογίνεται ο εξοπλισμός όταν αλλάζει το τμήμα, με τις ΙΔΙΕΣ
  /// ερωτήσεις που κάνει και το «+» της φόρμας κλήσης.
  ///
  /// Επιστρέφει τι μένει πίσω και ποια κοινά μηχανήματα ακολουθούν παίρνοντάς
  /// τα από τους υπόλοιπους κατόχους· κενές λίστες σημαίνουν «όλα
  /// ακολουθούν». `null` σημαίνει ότι ο χρήστης ακύρωσε.
  ///
  /// Ζει εδώ, δίπλα στην αδελφή του για τα τηλέφωνα: είναι μία απόφαση σε δύο
  /// σκέλη και χωρισμένη θα απέκλινε.
  Future<EquipmentDepartmentChangeAnswer?>
  confirmEquipmentFateOnDepartmentChange() async {
    const nothing = (
      staying: <EquipmentModel>[],
      takenFromCoOwners: <EquipmentModel>[],
    );
    if (!host.isEdit || host.widget.isClone) return nothing;
    if (!departmentChanged) return nothing;

    final editingUserId = host.widget.initialUser?.id;
    if (editingUserId == null) return nothing;

    final carried = UserEquipmentCodes.forUser(editingUserId);
    if (carried.isEmpty) return nothing;

    // Ίδια σειρά με τα τηλέφωνα: πρώτα ο κανόνας, μετά η ερώτηση — ώστε ο
    // λόγος που ένα μηχάνημα δεν μπορεί να μείνει πίσω να ειπωθεί εγκαίρως.
    final plan = planEquipmentStayBehind(
      equipment: carried,
      userName: host.buildUserDisplayName(),
      oldDepartmentId: host.widget.initialUser?.departmentId,
      editingUserId: editingUserId,
      lookup: LookupService.instance,
    );

    if (!host.mounted) return null;
    return askEquipmentOnDepartmentChange(
      host.context,
      plan: plan,
      targetKind: targetDepartmentKind,
      userDisplayName: host.buildUserDisplayName(),
      sourceDepartmentName: host.initialDepartmentText.trim(),
      targetDepartmentName: host.departmentController.text.trim(),
    );
  }

  List<String> _phonesToValidateForPolicy() {
    final current = PhoneListParser.splitPhones(host.phoneController.text);
    if (!host.isEdit || host.widget.isClone) return current;
    final deptChanged =
        SearchTextNormalizer.normalizeForSearch(
          host.departmentController.text,
        ) !=
        host.snapDepartmentNorm;
    if (deptChanged) return current;
    return PhoneDepartmentPolicy.addedPhones(
      beforePhones: PhoneListParser.splitPhones(host.snapPhone),
      afterPhones: current,
    );
  }

  Future<UserPhoneConflictBatchResult?> confirmUserPhoneAssignmentConflicts({
    required int? editingUserId,
    Set<String> phonesAlreadyDecided = const {},
  }) async {
    // Ό,τι αποφασίστηκε ήδη στην αλλαγή τμήματος (μένει πίσω, μένει στους
    // συναδέλφους, τους παίρνεται) δεν ξαναρωτιέται: δεύτερη ερώτηση για το
    // ίδιο τηλέφωνο θα ήταν σύγχυση.
    final phones = [
      for (final p in _phonesToValidateForPolicy())
        if (!phonesAlreadyDecided.contains(p.trim())) p,
    ];
    if (phones.isEmpty) return const UserPhoneConflictBatchResult();

    final target = await host.saveFlow.resolveTargetDepartmentForSave();
    final conflicts = PhoneDepartmentPolicy.findConflictsForUserAssignment(
      phones: phones,
      targetDepartmentId: target.id,
      editingUserId: editingUserId,
    );
    if (conflicts.isEmpty) return const UserPhoneConflictBatchResult();

    if (!host.mounted) return null;
    return showUserPhoneDepartmentConflictDialog(
      host.context,
      conflicts: conflicts,
      userDisplayName: host.buildUserDisplayName(),
      targetDepartmentName: target.name,
      targetDepartmentId: target.id,
    );
  }

  Future<SharedAssetDisconnectBatchResult?>
  confirmExclusiveRemovedPhonesDisconnect() async {
    final phones = _exclusiveRemovedPhones();
    if (phones.isEmpty) return const SharedAssetDisconnectBatchResult();

    final lookup = LookupService.instance;
    final source = resolveSourceDepartmentForDisconnect();
    final departments = lookup.departments
        .where((d) => !d.isDeleted && d.name.trim().isNotEmpty)
        .toList();

    if (!host.mounted) return null;
    return showSharedAssetDisconnectFlow(
      context: host.context,
      sourceDepartmentId: source.id,
      sourceDepartmentName: source.name,
      phones: phones,
      availableDepartments: departments,
      mode: SharedAssetDisconnectMode.personalPhone,
      personalPhoneUserDisplayName: host.buildUserDisplayName(),
    );
  }
}
