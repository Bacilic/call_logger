import '../../../core/database/department_repository.dart';
import '../../../core/database/directory_support.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/directory/department_change_assets.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/models/user_model.dart';
import '../models/department_kind.dart';
import 'user_move_consequences.dart';
import '../screens/widgets/shared_asset_disconnect_dialog.dart';
import 'bulk_action_undo_record.dart';
import 'phone_transfer_split.dart';
import 'user_deletion_undo_record.dart';

/// Τύχη τηλεφώνων/εξοπλισμού στη μαζική μεταφορά υπαλλήλων σε τμήμα.
enum BulkTransferAssetFate {
  /// Ακολουθούν τον υπάλληλο (τηλέφωνα: καμία αλλαγή δεσμών· εξοπλισμός:
  /// αλλάζει και το τμήμα του εξοπλισμού στο νέο).
  follow,

  /// Μένουν πίσω: αποδέσμευση από τον υπάλληλο και κοινόχρηστα του ΠΑΛΙΟΥ
  /// τμήματος.
  stayInOldDepartment,
}

/// Πεδίο-στόχος του μαζικού Καθαρισμού.
enum BulkClearField { phones, equipment, notes }

/// Τύχη των στοιχείων στον μαζικό Καθαρισμό (τρίο οικογένειας διαγραφής).
enum BulkClearFate { deleteOutright, shareInOwnDepartment, transfer }

/// Τρόπος εφαρμογής μαζικών Σημειώσεων.
enum BulkNotesMode { append, replace }

/// Στοιχείο που εξαιρέθηκε από μαζική ενέργεια, με αιτιολογία για τον χρήστη.
class BulkActionExclusion {
  const BulkActionExclusion({
    required this.isPhone,
    required this.identifier,
    required this.reason,
  });

  final bool isPhone;
  final String identifier;
  final String reason;
}

/// Πληροφορίες κοινοχρησίας για τον υπολογισμό εξαιρέσεων: ποιοι ΜΗ επιλεγμένοι
/// χρησιμοποιούν κάθε στοιχείο και ποια νούμερα είναι ήδη κοινόχρηστα τμήματος.
class BulkAssetSharingInfo {
  const BulkAssetSharingInfo({
    this.phoneOtherUserNames = const {},
    this.phoneSharedDepartments = const {},
    this.equipmentOtherUserNames = const {},
  });

  /// Αριθμός → ονόματα ΜΗ επιλεγμένων υπαλλήλων που τον έχουν επίσης.
  final Map<String, List<String>> phoneOtherUserNames;

  /// Αριθμός → το τμήμα που τον έχει κοινόχρηστο, όνομα ΚΑΙ αναγνωριστικό
  /// μαζί.
  ///
  /// Τα δύο ταξιδεύουν ως ένα επίτηδες: το όνομα φτιάχνει το μήνυμα, το
  /// αναγνωριστικό κρίνει αν ο αριθμός κάθεται στο τμήμα που ο υπάλληλος
  /// αφήνει ή σε κάποιο τρίτο. Χωριστοί χάρτες θα επέτρεπαν στον καλούντα να
  /// γεμίσει τον έναν και να ξεχάσει τον άλλον.
  final Map<String, ({int id, String name})> phoneSharedDepartments;

  /// Αναγνωριστικό εξοπλισμού → ονόματα ΜΗ επιλεγμένων συν-κατόχων.
  final Map<int, List<String>> equipmentOtherUserNames;
}

/// Απόφαση για ΕΝΑ τηλέφωνο όταν ο κάτοχός του αλλάζει τμήμα και έχει
/// επιλεγεί «μένουν στο παλιό τμήμα».
///
/// [releases] true σημαίνει «αποδεσμεύεται από τον υπάλληλο». Το
/// [blockedReason] είναι γεμάτο μόνο όταν ΔΕΝ αποδεσμεύεται, και εξηγεί γιατί
/// με λόγια του χρήστη.
typedef PhoneStayBehindDecision = ({bool releases, String? blockedReason});

/// Κρίνει αν ένα τηλέφωνο μένει πίσω στο τμήμα που αφήνει ο υπάλληλος.
///
/// ΜΟΝΑΔΙΚΟ σημείο του κανόνα: τον καλούν και η μαζική μεταφορά και η φόρμα
/// ενός υπαλλήλου. Όσο ζούσε μέσα στον βρόχο της μαζικής, η φόρμα δεν τον
/// είχε καθόλου και ο προσωπικός αριθμός ακολουθούσε σιωπηλά.
///
/// Δύο περιπτώσεις εμποδίζουν την αποδέσμευση:
/// 1. Κάθεται ήδη σε ΤΡΙΤΟ τμήμα — ένας αριθμός ανήκει μόνο σε ένα τμήμα.
/// 2. Δεν υπάρχει τμήμα-αφετηρία — δεν υπάρχει πού να μείνει.
///
/// Το τηλέφωνο που είναι ήδη κοινόχρηστο ΤΟΥ ΠΑΛΙΟΥ τμήματος αποδεσμεύεται
/// κανονικά: απλώς δεν χρειάζεται να ξαναπροστεθεί εκεί.
///
/// Τηλέφωνο που το κρατούν και συνάδελφοι **δεν** περνά από εδώ: για αυτό
/// ρωτιέται η τύχη του ίδιου του αριθμού ([SharedPhone]). Ως 04/10 ο κανόνας
/// το «μπλόκαρε», και ο αριθμός κατέληγε μοιρασμένος σε δύο τμήματα.
PhoneStayBehindDecision judgePhoneStayBehind({
  required String phone,
  required String userName,
  required int? oldDepartmentId,
  ({int id, String name})? sharedDepartment,
}) {
  if (sharedDepartment != null && sharedDepartment.id != oldDepartmentId) {
    return (
      releases: false,
      blockedReason:
          'Το $phone παραμένει στον υπάλληλο $userName — '
          'είναι ήδη κοινόχρηστο του τμήματος ${sharedDepartment.name}.',
    );
  }
  if (oldDepartmentId == null) {
    return (
      releases: false,
      blockedReason:
          'Το $phone παραμένει στον υπάλληλο $userName — '
          'δεν υπάρχει τμήμα-αφετηρία για να γίνει κοινόχρηστο.',
    );
  }
  return (releases: true, blockedReason: null);
}

/// Το σχέδιο για **όλα** τα τηλέφωνα ενός υπαλλήλου που αλλάζει τμήμα.
///
/// Το [blockedReasons] είναι ο λόγος που ΔΕΝ πραγματοποιήθηκε το «μένουν
/// πίσω», σε λόγια του χρήστη — ένας ανά αριθμό που εμποδίστηκε. Τα **κοινά**
/// τηλέφωνα (τα κρατούν και συνάδελφοι) δεν κρίνονται εδώ: η τύχη τους
/// ρωτιέται χωριστά ([SharedAssetFate]).
typedef PhoneStayBehindPlan = ({
  Set<String> staying,
  List<String> blockedReasons,
  List<SharedPhone> shared,
});

/// Κοινό τηλέφωνο και τα ονόματα των **υπόλοιπων** κατόχων του.
typedef SharedPhone = ({String phone, List<String> otherOwnerNames});

/// Το ίδιο για τον εξοπλισμό. Τα **κοινά** μηχανήματα (τα κρατά και άλλος)
/// δεν κρίνονται εδώ: η τύχη τους ρωτιέται χωριστά ([SharedAssetFate]).
typedef EquipmentStayBehindPlan = ({
  List<EquipmentModel> staying,
  List<String> blockedReasons,
  List<SharedEquipment> shared,
});

/// Η τύχη ενός κοινού μηχανήματος ή τηλεφώνου όταν ένας από τους κατόχους
/// του αλλάζει τμήμα (αποφάσεις Διευθυντή 03/10 και 04/10: η ερώτηση αφορά
/// το **ίδιο το πράγμα**, όχι τον υπάλληλο).
enum SharedAssetFate {
  /// Μένει στο τμήμα του· φεύγει μόνο από όποιον μετακινείται. Η
  /// συνηθισμένη απάντηση — και η προεπιλογή όταν δεν υπάρχει οθόνη.
  staysInDepartment,

  /// Ακολουθεί όποιον μετακινείται· φεύγει από τους υπόλοιπους κατόχους,
  /// γιατί ούτε μηχάνημα ούτε αριθμός ανήκει σε δύο τμήματα.
  movesWithOwner,
}

/// Κοινό μηχάνημα και τα ονόματα των **υπόλοιπων** κατόχων του.
typedef SharedEquipment = ({
  EquipmentModel equipment,
  List<String> otherOwnerNames,
});

/// Τρέχει τον [judgePhoneStayBehind] για μια ολόκληρη λίστα και κρατά **και
/// τους λόγους** όσων εμποδίστηκαν.
///
/// **Γιατί επιστρέφει και τα δύο:** ο κανόνας παρήγαγε πάντα τον λόγο, αλλά οι
/// καλούντες τον πετούσαν — έγραφαν `if (decision.releases) …` και η εξαίρεση
/// γινόταν σιωπηλή. Ο τύπος επιστροφής δεν αφήνει πια τον λόγο να χαθεί κατά
/// λάθος: όποιος τον αγνοήσει, το κάνει βλέποντάς τον.
///
/// Η αναζήτηση συν-κατόχων και κοινόχρηστου τμήματος γίνεται **εδώ** και όχι
/// στον καλούντα: ήταν γραμμένη δύο φορές, ολόιδια, και θα απέκλινε.
PhoneStayBehindPlan planPhoneStayBehind({
  required Iterable<String> phones,
  required String userName,
  required int? oldDepartmentId,
  required int? editingUserId,
  required LookupService lookup,
}) {
  final staying = <String>{};
  final blockedReasons = <String>[];
  final shared = <SharedPhone>[];
  for (final phone in phones) {
    final others = [
      for (final other in lookup.findUsersByPhone(phone))
        if (other.id != null && other.id != editingUserId && !other.isDeleted)
          bulkUserDisplayName(other),
    ];
    if (others.isNotEmpty) {
      shared.add((phone: phone, otherOwnerNames: others));
      continue;
    }
    final dept = lookup.getDepartmentByPhone(phone);
    final deptId = dept?.id;
    final deptName = dept?.name.trim() ?? '';
    final decision = judgePhoneStayBehind(
      phone: phone,
      userName: userName,
      oldDepartmentId: oldDepartmentId,
      sharedDepartment: (deptId != null && deptName.isNotEmpty)
          ? (id: deptId, name: deptName)
          : null,
    );
    if (decision.releases) {
      staying.add(phone);
    } else {
      blockedReasons.add(decision.blockedReason!);
    }
  }
  return (staying: staying, blockedReasons: blockedReasons, shared: shared);
}

/// Δίδυμο του [planPhoneStayBehind] για τον εξοπλισμό — ίδιος λόγος ύπαρξης.
EquipmentStayBehindPlan planEquipmentStayBehind({
  required Iterable<EquipmentModel> equipment,
  required String userName,
  required int? oldDepartmentId,
  required int? editingUserId,
  required LookupService lookup,
}) {
  final staying = <EquipmentModel>[];
  final blockedReasons = <String>[];
  final shared = <SharedEquipment>[];
  for (final item in equipment) {
    final code = (item.code ?? '').trim();
    final itemId = item.id;
    if (code.isEmpty || itemId == null) continue;
    final others = [
      for (final other in lookup.findUsersForEquipment(itemId))
        if (other.id != null && other.id != editingUserId && !other.isDeleted)
          bulkUserDisplayName(other),
    ];
    if (others.isNotEmpty) {
      shared.add((equipment: item, otherOwnerNames: others));
      continue;
    }
    final decision = judgeEquipmentStayBehind(
      code: code,
      userName: userName,
      oldDepartmentId: oldDepartmentId,
      equipmentDepartmentId: item.departmentId,
    );
    if (decision.releases) {
      staying.add(item);
    } else {
      blockedReasons.add(decision.blockedReason!);
    }
  }
  return (staying: staying, blockedReasons: blockedReasons, shared: shared);
}

/// Κρίνει αν ένα μηχάνημα μένει πίσω στο τμήμα που αφήνει ο υπάλληλος.
///
/// Δίδυμο του [judgePhoneStayBehind] και ΜΟΝΑΔΙΚΟ σημείο του κανόνα: τον
/// καλούν και η μαζική μεταφορά και η φόρμα ενός υπαλλήλου.
///
/// Ο κανόνας του πεδίου είναι ο **αντίστροφος** από των τηλεφώνων — ο
/// εξοπλισμός ακολουθεί τον άνθρωπο — γι' αυτό εδώ κρίνεται μόνο η
/// λιγότερο συνηθισμένη έκβαση: το «μένει πίσω».
///
/// Την εμποδίζει μόνο ένα πράγμα: ούτε το μηχάνημα ούτε ο υπάλληλος έχουν
/// τμήμα — θα έμενε ορφανό, και ο εξοπλισμός δεν είναι ποτέ ορφανός.
///
/// Μηχάνημα που το κρατά και άλλος **δεν** περνά από εδώ: για αυτό ρωτιέται
/// η τύχη του ίδιου του μηχανήματος ([SharedAssetFate]). Ως 03/10 ο
/// κανόνας το «μπλόκαρε», και το μηχάνημα κατέληγε μοιρασμένο σε δύο τμήματα.
PhoneStayBehindDecision judgeEquipmentStayBehind({
  required String code,
  required String userName,
  required int? oldDepartmentId,
  required int? equipmentDepartmentId,
}) {
  if (equipmentDepartmentId == null && oldDepartmentId == null) {
    return (
      releases: false,
      blockedReason:
          'Ο εξοπλισμός $code παραμένει στον υπάλληλο $userName — '
          'χωρίς τμήμα-αφετηρία θα έμενε ορφανός.',
    );
  }
  return (releases: true, blockedReason: null);
}

/// Εμφανίσιμο όνομα υπαλλήλου για μηνύματα.
String bulkUserDisplayName(UserModel u) {
  final name = (u.name ?? '${u.firstName ?? ''} ${u.lastName ?? ''}').trim();
  return name.isEmpty ? '—' : name;
}

/// Λίστα ονομάτων για μηνύματα: έως 5 ονομαστικά, μετά «+Ν ακόμη».
String bulkUserNamesPreview(Iterable<UserModel> users) {
  final names = [for (final u in users) bulkUserDisplayName(u)];
  if (names.isEmpty) return '';
  if (names.length <= 5) return names.join(', ');
  final rest = names.length - 5;
  return '${names.take(5).join(', ')} +$rest ακόμη';
}

/// Ενώνει ονόματα κατόχων για τα μηνύματα εξαίρεσης.
///
/// **Γιατί η φράση από πάνω λέει «επίσης:» και όχι «και ο»:** η εφαρμογή δεν
/// ξέρει το φύλο των υπαλλήλων και δεν πρέπει να χρειαστεί να το μάθει γι'
/// αυτό. Το σταθερό αρσενικό άρθρο έγραφε «ο Γεωργία Νέζη» — μετρημένο στη
/// ζωντανή εφαρμογή 18/09/2026. Η άνω τελεία δεν έχει φύλο.
String _joinNames(List<String> names) {
  if (names.length <= 2) return names.join(' και ');
  return '${names.take(2).join(', ')} κ.ά.';
}

// ─────────────────────────── Μεταφορά σε τμήμα ───────────────────────────

/// Πλήρες σχέδιο μαζικής μεταφοράς: ποιοι μετακινούνται, τι κάνει κάθε
/// τηλέφωνο/εξοπλισμός, τι εξαιρέθηκε και γιατί.
class BulkUserTransferPlan {
  const BulkUserTransferPlan({
    required this.target,
    required this.targetDisplayName,
    required this.targetKind,
    required this.phoneFate,
    required this.equipmentFate,
    required this.usersToMove,
    required this.usersAlreadyInTarget,
    required this.phonesToRelease,
    required this.equipmentToFollow,
    required this.equipmentToRelease,
    required this.equipmentNeedingNewHome,
    required this.exclusions,
    this.equipmentRehoming = const SharedAssetDisconnectBatchResult(),
    this.sharedEquipment = const [],
    this.sharedEquipmentFate = SharedAssetFate.staysInDepartment,
    this.sharedPhones = const [],
    this.sharedPhoneFate = SharedAssetFate.staysInDepartment,
    this.phonesLeftWithCoOwners = const {},
    this.phonesKeptByRule = const [],
  });

  final SharedAssetTransferTarget target;
  final String targetDisplayName;

  /// Το Είδος του προορισμού — το κείμενο επιβεβαίωσης το χρειάζεται για να
  /// πει αν οι άνθρωποι βγαίνουν από το νοσοκομείο.
  final DepartmentKind targetKind;
  final BulkTransferAssetFate phoneFate;
  final BulkTransferAssetFate equipmentFate;
  final List<UserModel> usersToMove;
  final List<UserModel> usersAlreadyInTarget;

  /// userId → αριθμοί που αποδεσμεύονται και γίνονται κοινόχρηστοι του παλιού
  /// τμήματος (μόνο όταν phoneFate = stayInOldDepartment).
  final Map<int, List<String>> phonesToRelease;

  /// userId → εξοπλισμοί που αλλάζουν τμήμα μαζί με τον υπάλληλο.
  final Map<int, List<EquipmentModel>> equipmentToFollow;

  /// userId → εξοπλισμοί που αποδεσμεύονται από τον υπάλληλο και μένουν στο
  /// παλιό τμήμα.
  final Map<int, List<EquipmentModel>> equipmentToRelease;

  /// Μηχανήματα που **δεν χωράνε** στον προορισμό επειδή το Είδος του δεν
  /// επιτρέπει κατοχή (εταιρεία) — ούτε ακολουθούν ούτε αποδεσμεύονται σιωπηλά.
  ///
  /// Είναι η μοναδική έξοδος του κανόνα: όσο η λίστα δεν είναι κενή, η ροή
  /// οφείλει να ρωτήσει τον χρήστη πού πάει το καθένα. Χωρίς αυτό, το «ο
  /// εξοπλισμός ακολουθεί» χρέωνε την DataMed με δικά μας μηχανήματα.
  final List<EquipmentModel> equipmentNeedingNewHome;

  final List<BulkActionExclusion> exclusions;

  /// Οι απαντήσεις του χρήστη για το [equipmentNeedingNewHome]: πού πάει ή τι
  /// διαγράφεται. Μένει κενό όσο η ερώτηση δεν έχει γίνει.
  final SharedAssetDisconnectBatchResult equipmentRehoming;

  /// Κοινά μηχανήματα: τα κρατά και κάποιος που **δεν** μεταφέρεται. Η τύχη
  /// τους ρωτιέται με μία ερώτηση για όλα ([sharedEquipmentFate]).
  final List<SharedEquipment> sharedEquipment;

  /// Η απάντηση για τα [sharedEquipment] — προεπιλογή «παραμένουν».
  final SharedAssetFate sharedEquipmentFate;

  /// Κοινά τηλέφωνα: τα κρατά και κάποιος που **δεν** μεταφέρεται. Η τύχη
  /// τους ρωτιέται με μία ερώτηση για όλα ([sharedPhoneFate]), ανεξάρτητα από
  /// την απάντηση «μένουν ή ακολουθούν» για τα υπόλοιπα.
  final List<SharedPhone> sharedPhones;

  /// Η απάντηση για τα [sharedPhones] — προεπιλογή «παραμένουν».
  final SharedAssetFate sharedPhoneFate;

  /// userId → κοινά τηλέφωνα που φεύγουν από τον μεταφερόμενο και μένουν
  /// στους υπόλοιπους κατόχους. **Δεν** γίνονται κοινόχρηστα του τμήματος:
  /// ανήκουν ήδη σε ανθρώπους που μένουν εκεί.
  final Map<int, List<String>> phonesLeftWithCoOwners;

  /// Τηλέφωνα που μένουν πίσω επειδή ο προορισμός δεν μπορεί να τα κρατά
  /// (εσωτερικά του νοσοκομείου, όταν οι άνθρωποι φεύγουν από αυτό) — ό,τι
  /// κι αν απαντήθηκε. Είναι ήδη μέσα στο [phonesToRelease]· η λίστα υπάρχει
  /// για να το πει το κείμενο επιβεβαίωσης.
  final List<String> phonesKeptByRule;

  /// Τα κοινά τηλέφωνα που ακολουθούν τους μεταφερόμενους — από αυτά
  /// φεύγουν οι υπόλοιποι κάτοχοι.
  Set<String> get phonesTakenFromCoOwners =>
      sharedPhoneFate == SharedAssetFate.movesWithOwner
      ? {for (final s in sharedPhones) s.phone}
      : const <String>{};

  Set<int> get _sharedIds => {
    for (final s in sharedEquipment)
      if (s.equipment.id != null) s.equipment.id!,
  };

  /// Τα κοινά μηχανήματα που ακολουθούν τους μεταφερόμενους — από αυτά
  /// φεύγουν οι υπόλοιποι κάτοχοι.
  Set<int> get equipmentTakenFromCoOwners =>
      sharedEquipmentFate == SharedAssetFate.movesWithOwner &&
          targetKind.canOwnEquipment
      ? _sharedIds
      : const <int>{};

  /// Το ίδιο σχέδιο με τις απαντήσεις «πού πάει το κάθε μηχάνημα» δεμένες.
  BulkUserTransferPlan withEquipmentRehoming(
    SharedAssetDisconnectBatchResult batch,
  ) {
    return BulkUserTransferPlan(
      target: target,
      targetDisplayName: targetDisplayName,
      targetKind: targetKind,
      phoneFate: phoneFate,
      equipmentFate: equipmentFate,
      usersToMove: usersToMove,
      usersAlreadyInTarget: usersAlreadyInTarget,
      phonesToRelease: phonesToRelease,
      equipmentToFollow: equipmentToFollow,
      equipmentToRelease: equipmentToRelease,
      equipmentNeedingNewHome: equipmentNeedingNewHome,
      exclusions: exclusions,
      equipmentRehoming: batch,
      sharedEquipment: sharedEquipment,
      sharedEquipmentFate: sharedEquipmentFate,
      sharedPhones: sharedPhones,
      sharedPhoneFate: sharedPhoneFate,
      phonesLeftWithCoOwners: phonesLeftWithCoOwners,
      phonesKeptByRule: phonesKeptByRule,
    );
  }

  bool get hasWork => usersToMove.isNotEmpty;

  int get releasedPhoneCount => [
    for (final list in phonesToRelease.values) list.length,
  ].fold(0, (a, b) => a + b);

  /// Τα μετρητά αφορούν τα **μη κοινά** μηχανήματα· τα κοινά έχουν δική
  /// τους γραμμή στο κείμενο, με δική τους απάντηση.
  int get followingEquipmentCount =>
      _uniqueEquipmentCount(equipmentToFollow, except: _sharedIds);

  int get releasedEquipmentCount =>
      _uniqueEquipmentCount(equipmentToRelease, except: _sharedIds);

  static int _uniqueEquipmentCount(
    Map<int, List<EquipmentModel>> byUser, {
    Set<int> except = const {},
  }) {
    final seen = <int>{};
    for (final list in byUser.values) {
      for (final e in list) {
        final id = e.id;
        if (id != null && !except.contains(id)) seen.add(id);
      }
    }
    return seen.length;
  }
}

/// Υπολογίζει το σχέδιο μεταφοράς ΧΩΡΙΣ να αγγίξει τη βάση (τεσταρίσιμο).
BulkUserTransferPlan buildBulkUserTransferPlan({
  required List<UserModel> selectedUsers,
  required SharedAssetTransferTarget target,
  required String targetDisplayName,
  required BulkTransferAssetFate phoneFate,
  required BulkTransferAssetFate equipmentFate,
  required Map<int, List<EquipmentModel>> equipmentByUserId,

  /// Το Είδος του τμήματος-προορισμού — για νέο τμήμα είναι πάντα νοσοκομείο.
  ///
  /// Υποχρεωτικό επίτηδες: ο εξοπλισμός δεν επιτρέπεται να καταλήξει σε τμήμα
  /// που δεν μπορεί να τον κρατά, και ο μόνος τρόπος να μην το ξεχάσει καμία
  /// ροή είναι να μην μπορεί να χτίσει σχέδιο χωρίς να το δηλώσει.
  required DepartmentKind targetKind,
  BulkAssetSharingInfo sharing = const BulkAssetSharingInfo(),

  /// Η απάντηση για τα κοινά μηχανήματα. Η ροή χτίζει πρώτα το σχέδιο με την
  /// προεπιλογή, ρωτά αν [BulkUserTransferPlan.sharedEquipment] δεν είναι
  /// κενό, και ξαναχτίζει με την απάντηση.
  SharedAssetFate sharedEquipmentFate = SharedAssetFate.staysInDepartment,

  /// Η απάντηση για τα κοινά τηλέφωνα — ίδιος κύκλος με τα κοινά μηχανήματα.
  SharedAssetFate sharedPhoneFate = SharedAssetFate.staysInDepartment,

  /// Τηλέφωνα που ο προορισμός δεν μπορεί να κρατά (τα εσωτερικά του
  /// νοσοκομείου, όταν οι άνθρωποι φεύγουν από αυτό): μένουν πίσω ό,τι κι
  /// αν απαντήθηκε — ο διάλογος το έχει ήδη αναγγείλει.
  Set<String> phonesThatCannotFollow = const {},
}) {
  final targetId = target.departmentId;
  final usersToMove = <UserModel>[];
  final usersAlreadyInTarget = <UserModel>[];
  for (final u in selectedUsers) {
    if (u.id == null) continue;
    if (targetId != null && u.departmentId == targetId) {
      usersAlreadyInTarget.add(u);
    } else {
      usersToMove.add(u);
    }
  }

  final phonesToRelease = <int, List<String>>{};
  final equipmentToFollow = <int, List<EquipmentModel>>{};
  final equipmentToRelease = <int, List<EquipmentModel>>{};
  final equipmentNeedingNewHome = <EquipmentModel>[];
  final targetCanOwnEquipment = targetKind.canOwnEquipment;
  final exclusions = <BulkActionExclusion>[];
  final seenEquipmentIds = <int>{};
  final sharedEquipment = <SharedEquipment>[];
  final seenSharedIds = <int>{};
  final sharedPhones = <SharedPhone>[];
  final seenSharedPhones = <String>{};
  final phonesLeftWithCoOwners = <int, List<String>>{};
  final phonesKeptByRule = <String>[];

  for (final u in usersToMove) {
    final userId = u.id!;
    final userName = bulkUserDisplayName(u);

    for (final number in u.phones) {
      final n = number.trim();
      if (n.isEmpty) continue;
      // Ό,τι δεν μπορεί να ακολουθήσει μένει πίσω πριν από κάθε άλλη κρίση —
      // και πριν από την ερώτηση του κοινού τηλεφώνου: ένα «Μεταφέρεται» δεν
      // στέλνει εσωτερικό του νοσοκομείου σε εταιρεία.
      if (phonesThatCannotFollow.contains(n)) {
        phonesToRelease.putIfAbsent(userId, () => []).add(n);
        if (!phonesKeptByRule.contains(n)) phonesKeptByRule.add(n);
        continue;
      }
      final others = sharing.phoneOtherUserNames[n] ?? const <String>[];
      // Κοινό τηλέφωνο: ρωτιέται η τύχη του ίδιου του αριθμού, όποια κι αν
      // είναι η απάντηση για τα υπόλοιπα. Μένει → φεύγει από **κάθε**
      // μεταφερόμενο· ακολουθεί → φεύγει από τους υπόλοιπους κατόχους.
      if (others.isNotEmpty) {
        if (seenSharedPhones.add(n)) {
          sharedPhones.add((phone: n, otherOwnerNames: others));
        }
        if (sharedPhoneFate == SharedAssetFate.staysInDepartment) {
          phonesLeftWithCoOwners.putIfAbsent(userId, () => []).add(n);
        }
        continue;
      }
      if (phoneFate == BulkTransferAssetFate.stayInOldDepartment) {
        final decision = judgePhoneStayBehind(
          phone: n,
          userName: userName,
          oldDepartmentId: u.departmentId,
          sharedDepartment: sharing.phoneSharedDepartments[n],
        );
        if (decision.releases) {
          phonesToRelease.putIfAbsent(userId, () => []).add(n);
        } else {
          exclusions.add(
            BulkActionExclusion(
              isPhone: true,
              identifier: n,
              reason: decision.blockedReason!,
            ),
          );
        }
      }
    }

    for (final e in equipmentByUserId[userId] ?? const <EquipmentModel>[]) {
      final eqId = e.id;
      if (eqId == null) continue;
      final code = (e.code ?? '').trim();
      if (code.isEmpty) continue;
      final others = sharing.equipmentOtherUserNames[eqId] ?? const [];
      // Κοινό μηχάνημα: ρωτιέται η τύχη του ίδιου του μηχανήματος. Μένει
      // στο τμήμα του → φεύγει από **κάθε** μεταφερόμενο κάτοχο· ακολουθεί →
      // αλλάζει τμήμα μία φορά, και φεύγει από τους υπόλοιπους κατόχους.
      if (others.isNotEmpty) {
        final firstTime = seenSharedIds.add(eqId);
        if (firstTime) {
          sharedEquipment.add((equipment: e, otherOwnerNames: others));
        }
        final moves =
            targetCanOwnEquipment &&
            sharedEquipmentFate == SharedAssetFate.movesWithOwner;
        if (!moves) {
          equipmentToRelease.putIfAbsent(userId, () => []).add(e);
        } else if (firstTime) {
          equipmentToFollow.putIfAbsent(userId, () => []).add(e);
        }
        continue;
      }
      if (!seenEquipmentIds.add(eqId)) continue;
      final decision = judgeEquipmentStayBehind(
        code: code,
        userName: userName,
        oldDepartmentId: u.departmentId,
        equipmentDepartmentId: e.departmentId,
      );
      if (!targetCanOwnEquipment) {
        // Ό,τι κι αν απάντησε ο χρήστης για την «τύχη», το μηχάνημα δεν πάει
        // στον προορισμό. Ζητά δική του στέγη, μία ερώτηση ανά μηχάνημα.
        equipmentNeedingNewHome.add(e);
      } else if (equipmentFate == BulkTransferAssetFate.follow) {
        equipmentToFollow.putIfAbsent(userId, () => []).add(e);
      } else if (decision.releases) {
        equipmentToRelease.putIfAbsent(userId, () => []).add(e);
      } else {
        exclusions.add(
          BulkActionExclusion(
            isPhone: false,
            identifier: code,
            reason: decision.blockedReason!,
          ),
        );
      }
    }
  }

  return BulkUserTransferPlan(
    target: target,
    targetDisplayName: targetDisplayName,
    targetKind: targetKind,
    phoneFate: phoneFate,
    equipmentFate: equipmentFate,
    usersToMove: usersToMove,
    usersAlreadyInTarget: usersAlreadyInTarget,
    phonesToRelease: phonesToRelease,
    equipmentToFollow: equipmentToFollow,
    equipmentToRelease: equipmentToRelease,
    equipmentNeedingNewHome: equipmentNeedingNewHome,
    exclusions: exclusions,
    sharedEquipment: sharedEquipment,
    sharedEquipmentFate: sharedEquipmentFate,
    sharedPhones: sharedPhones,
    sharedPhoneFate: sharedPhoneFate,
    phonesLeftWithCoOwners: phonesLeftWithCoOwners,
    phonesKeptByRule: phonesKeptByRule,
  );
}

/// «2534, 2531» — οι αριθμοί των κοινών τηλεφώνων, για ερώτηση και κείμενο.
String sharedPhoneNumbersText(List<SharedPhone> shared) {
  final numbers = [for (final s in shared) s.phone];
  if (numbers.length <= 4) return numbers.join(', ');
  return '${numbers.take(4).join(', ')}…';
}

/// «3140, 3180» — οι κωδικοί των κοινών μηχανημάτων, για ερώτηση και κείμενο.
String sharedEquipmentCodesText(List<SharedEquipment> shared) {
  final codes = [
    for (final s in shared)
      if ((s.equipment.code ?? '').trim().isNotEmpty) s.equipment.code!.trim(),
  ];
  if (codes.length <= 4) return codes.join(', ');
  return '${codes.take(4).join(', ')}…';
}

/// Κείμενο επιβεβαίωσης ΠΡΙΝ την εκτέλεση της μεταφοράς: τι θα συμβεί σε ποιους.
String bulkTransferConfirmationText(BulkUserTransferPlan plan) {
  final buf = StringBuffer();
  final n = plan.usersToMove.length;
  buf.write(
    n == 1
        ? 'Θα μεταφερθεί 1 υπάλληλος στο «${plan.targetDisplayName}»'
        : 'Θα μεταφερθούν $n υπάλληλοι στο «${plan.targetDisplayName}»',
  );
  final names = bulkUserNamesPreview(plan.usersToMove);
  if (names.isNotEmpty) buf.write(': $names');
  buf.write('.');
  // Πρώτο απ' όλα όσα ακολουθούν: το ότι οι άνθρωποι φεύγουν από τον
  // οργανισμό βαραίνει περισσότερο από την τύχη των τηλεφώνων τους.
  final leaving = usersLeaveHospitalMessage(
    targetKind: plan.targetKind,
    targetDepartmentName: plan.targetDisplayName,
    count: plan.usersToMove.length,
  );
  if (leaving != null) buf.write('\n$leaving');
  if (plan.target.departmentId == null) {
    buf.write('\nΤο τμήμα «${plan.targetDisplayName}» θα δημιουργηθεί τώρα.');
  }
  if (plan.usersAlreadyInTarget.isNotEmpty) {
    buf.write(
      '\n${plan.usersAlreadyInTarget.length} από τους επιλεγμένους '
      'είναι ήδη εκεί και δεν αλλάζουν: '
      '${bulkUserNamesPreview(plan.usersAlreadyInTarget)}.',
    );
  }
  buf.write(
    plan.phoneFate == BulkTransferAssetFate.follow
        ? '\nΤα τηλέφωνα ακολουθούν τους υπαλλήλους.'
        : '\nΤα τηλέφωνα μένουν κοινόχρηστα στο παλιό τους τμήμα'
              ' (${plan.releasedPhoneCount} αριθμοί).',
  );
  // Η ίδια αναγγελία με την ερώτηση: το «ακολουθούν» από πάνω δεν ισχύει
  // για αυτά, και το κείμενο δεν υπόσχεται κάτι που δεν θα γίνει.
  if (plan.phoneFate == BulkTransferAssetFate.follow) {
    final kept = forcedPhoneStayMessage(
      split: PhoneTransferSplit(forcedToStay: plan.phonesKeptByRule),
      targetKind: plan.targetKind,
    );
    if (kept != null) buf.write('\n$kept.');
  }
  if (plan.equipmentNeedingNewHome.isNotEmpty) {
    // Ο προορισμός δεν κρατά μηχανήματα: η «τύχη» που απαντήθηκε δεν ισχύει
    // εδώ, και το κείμενο δεν πρέπει να υπόσχεται κάτι που δεν θα γίνει.
    final count = plan.equipmentNeedingNewHome.length;
    buf.write(
      count == 1
          ? '\nΤο «${plan.targetDisplayName}» δεν κρατά εξοπλισμό: '
                '1 μηχάνημα παίρνει τον προορισμό που ορίσατε.'
          : '\nΤο «${plan.targetDisplayName}» δεν κρατά εξοπλισμό: '
                '$count μηχανήματα παίρνουν τους προορισμούς που ορίσατε.',
    );
  } else {
    buf.write(
      plan.equipmentFate == BulkTransferAssetFate.follow
          ? '\nΟι εξοπλισμοί ακολουθούν στο νέο τμήμα'
                ' (${plan.followingEquipmentCount} εξοπλισμοί).'
          : '\nΟι εξοπλισμοί αποδεσμεύονται και μένουν στο παλιό τμήμα'
                ' (${plan.releasedEquipmentCount} εξοπλισμοί).',
    );
  }
  if (plan.sharedEquipment.isNotEmpty) {
    final codes = sharedEquipmentCodesText(plan.sharedEquipment);
    if (plan.equipmentTakenFromCoOwners.isNotEmpty) {
      final others = {
        for (final s in plan.sharedEquipment) ...s.otherOwnerNames,
      }.toList();
      buf.write(
        '\nΟ κοινός εξοπλισμός ($codes) μεταφέρεται και φεύγει από: '
        '${_joinNames(others)}.',
      );
    } else {
      buf.write(
        '\nΟ κοινός εξοπλισμός ($codes) παραμένει στο τμήμα του και '
        'φεύγει μόνο από τους μεταφερόμενους.',
      );
    }
  }
  if (plan.sharedPhones.isNotEmpty) {
    final numbers = sharedPhoneNumbersText(plan.sharedPhones);
    final one = plan.sharedPhones.length == 1;
    if (plan.phonesTakenFromCoOwners.isNotEmpty) {
      final others = {
        for (final s in plan.sharedPhones) ...s.otherOwnerNames,
      }.toList();
      buf.write(
        one
            ? '\nΤο κοινό τηλέφωνο ($numbers) μεταφέρεται και φεύγει από: '
                  '${_joinNames(others)}.'
            : '\nΤα κοινά τηλέφωνα ($numbers) μεταφέρονται και φεύγουν από: '
                  '${_joinNames(others)}.',
      );
    } else {
      buf.write(
        one
            ? '\nΤο κοινό τηλέφωνο ($numbers) παραμένει στο τμήμα του και '
                  'φεύγει μόνο από τους μεταφερόμενους.'
            : '\nΤα κοινά τηλέφωνα ($numbers) παραμένουν στο τμήμα τους και '
                  'φεύγουν μόνο από τους μεταφερόμενους.',
      );
    }
  }
  for (final ex in plan.exclusions) {
    buf.write('\n• ${ex.reason}');
  }
  return buf.toString();
}

/// Μήνυμα αποτελέσματος ΜΕΤΑ τη μεταφορά (για τη μπάρα αναίρεσης).
String bulkTransferResultMessage(BulkUserTransferPlan plan) {
  final n = plan.usersToMove.length;
  final buf = StringBuffer(
    n == 1
        ? 'Μεταφέρθηκε 1 υπάλληλος στο «${plan.targetDisplayName}»'
        : 'Μεταφέρθηκαν $n υπάλληλοι στο «${plan.targetDisplayName}»',
  );
  final phoneCount = plan.releasedPhoneCount;
  if (phoneCount > 0) {
    buf.write(
      phoneCount == 1
          ? ' · 1 τηλέφωνο έγινε κοινόχρηστο στο παλιό τμήμα'
          : ' · $phoneCount τηλέφωνα έγιναν κοινόχρηστα στο παλιό τμήμα',
    );
  }
  final followingCount = plan.followingEquipmentCount;
  if (followingCount > 0) {
    buf.write(
      followingCount == 1
          ? ' · 1 εξοπλισμός ακολούθησε'
          : ' · $followingCount εξοπλισμοί ακολούθησαν',
    );
  }
  final releasedCount = plan.releasedEquipmentCount;
  if (releasedCount > 0) {
    buf.write(
      releasedCount == 1
          ? ' · 1 εξοπλισμός έμεινε στο παλιό τμήμα'
          : ' · $releasedCount εξοπλισμοί έμειναν στο παλιό τμήμα',
    );
  }
  if (plan.exclusions.isNotEmpty) {
    buf.write(
      plan.exclusions.length == 1
          ? ' · 1 εξαίρεση'
          : ' · ${plan.exclusions.length} εξαιρέσεις',
    );
  }
  buf.write('.');
  return buf.toString();
}

// ─────────────────────────── Καθαρισμός πεδίου ───────────────────────────

/// Σχέδιο μαζικού Καθαρισμού πεδίου με ΜΙΑ απόφαση για όλους.
class BulkUserClearPlan {
  const BulkUserClearPlan({
    required this.field,
    required this.fate,
    this.transferTarget,
    this.transferTargetDisplayName,
    required this.users,
    required this.phonesByUser,
    required this.equipmentByUser,
    required this.exclusions,
  });

  final BulkClearField field;
  final BulkClearFate fate;
  final SharedAssetTransferTarget? transferTarget;
  final String? transferTargetDisplayName;
  final List<UserModel> users;
  final Map<int, List<String>> phonesByUser;
  final Map<int, List<EquipmentModel>> equipmentByUser;
  final List<BulkActionExclusion> exclusions;

  bool get hasWork {
    switch (field) {
      case BulkClearField.phones:
        return phonesByUser.values.any((l) => l.isNotEmpty);
      case BulkClearField.equipment:
        return equipmentByUser.values.any((l) => l.isNotEmpty);
      case BulkClearField.notes:
        return users.any((u) => (u.notes ?? '').trim().isNotEmpty);
    }
  }
}

/// Υπολογίζει το σχέδιο Καθαρισμού ΧΩΡΙΣ πρόσβαση στη βάση (τεσταρίσιμο).
BulkUserClearPlan buildBulkUserClearPlan({
  required List<UserModel> selectedUsers,
  required BulkClearField field,
  required BulkClearFate fate,
  SharedAssetTransferTarget? transferTarget,
  String? transferTargetDisplayName,
  Map<int, List<EquipmentModel>> equipmentByUserId = const {},
  BulkAssetSharingInfo sharing = const BulkAssetSharingInfo(),
}) {
  final users = [
    for (final u in selectedUsers)
      if (u.id != null) u,
  ];
  final phonesByUser = <int, List<String>>{};
  final equipmentByUser = <int, List<EquipmentModel>>{};
  final exclusions = <BulkActionExclusion>[];
  final seenEquipmentIds = <int>{};

  if (field == BulkClearField.phones) {
    for (final u in users) {
      final userName = bulkUserDisplayName(u);
      for (final number in u.phones) {
        final n = number.trim();
        if (n.isEmpty) continue;
        final others = sharing.phoneOtherUserNames[n] ?? const [];
        final sharedDept = sharing.phoneSharedDepartments[n]?.name;
        if (others.isNotEmpty) {
          exclusions.add(
            BulkActionExclusion(
              isPhone: true,
              identifier: n,
              reason:
                  'Το $n δεν καθαρίζεται — '
                  'το χρησιμοποιεί επίσης: ${_joinNames(others)}.',
            ),
          );
        } else if (sharedDept != null) {
          exclusions.add(
            BulkActionExclusion(
              isPhone: true,
              identifier: n,
              reason:
                  'Το $n δεν καθαρίζεται — '
                  'είναι ήδη κοινόχρηστο του τμήματος $sharedDept.',
            ),
          );
        } else if (fate == BulkClearFate.shareInOwnDepartment &&
            u.departmentId == null) {
          exclusions.add(
            BulkActionExclusion(
              isPhone: true,
              identifier: n,
              reason:
                  'Το $n παραμένει στον υπάλληλο $userName — '
                  'δεν έχει τμήμα για να γίνει κοινόχρηστο.',
            ),
          );
        } else {
          phonesByUser.putIfAbsent(u.id!, () => []).add(n);
        }
      }
    }
  }

  if (field == BulkClearField.equipment) {
    for (final u in users) {
      final userName = bulkUserDisplayName(u);
      for (final e in equipmentByUserId[u.id!] ?? const <EquipmentModel>[]) {
        final eqId = e.id;
        if (eqId == null) continue;
        final code = (e.code ?? '').trim();
        if (code.isEmpty) continue;
        final others = sharing.equipmentOtherUserNames[eqId] ?? const [];
        if (others.isNotEmpty) {
          if (seenEquipmentIds.add(eqId)) {
            exclusions.add(
              BulkActionExclusion(
                isPhone: false,
                identifier: code,
                reason:
                    'Ο εξοπλισμός $code δεν καθαρίζεται — '
                    'τον χρησιμοποιεί επίσης: ${_joinNames(others)}.',
              ),
            );
          }
          continue;
        }
        if (fate == BulkClearFate.shareInOwnDepartment &&
            e.departmentId == null &&
            u.departmentId == null) {
          if (seenEquipmentIds.add(eqId)) {
            exclusions.add(
              BulkActionExclusion(
                isPhone: false,
                identifier: code,
                reason:
                    'Ο εξοπλισμός $code παραμένει στον υπάλληλο $userName — '
                    'χωρίς τμήμα θα έμενε ορφανός.',
              ),
            );
          }
          continue;
        }
        equipmentByUser.putIfAbsent(u.id!, () => []).add(e);
      }
    }
  }

  return BulkUserClearPlan(
    field: field,
    fate: fate,
    transferTarget: transferTarget,
    transferTargetDisplayName: transferTargetDisplayName,
    users: users,
    phonesByUser: phonesByUser,
    equipmentByUser: equipmentByUser,
    exclusions: exclusions,
  );
}

String _clearFateLabel(BulkUserClearPlan plan) {
  switch (plan.fate) {
    case BulkClearFate.deleteOutright:
      return 'θα διαγραφούν';
    case BulkClearFate.shareInOwnDepartment:
      return 'θα γίνουν κοινόχρηστα στο τμήμα του κάθε υπαλλήλου';
    case BulkClearFate.transfer:
      return 'θα μεταφερθούν στο «${plan.transferTargetDisplayName ?? ''}»';
  }
}

/// Κείμενο επιβεβαίωσης ΠΡΙΝ τον Καθαρισμό.
String bulkClearConfirmationText(BulkUserClearPlan plan) {
  final buf = StringBuffer();
  switch (plan.field) {
    case BulkClearField.notes:
      final withNotes = [
        for (final u in plan.users)
          if ((u.notes ?? '').trim().isNotEmpty) u,
      ];
      buf.write(
        'Θα διαγραφούν οι σημειώσεις ${withNotes.length} υπαλλήλων: '
        '${bulkUserNamesPreview(withNotes)}.',
      );
    case BulkClearField.phones:
      final count = [
        for (final l in plan.phonesByUser.values) l.length,
      ].fold(0, (a, b) => a + b);
      buf.write(
        'Θα αποδεσμευτούν $count τηλέφωνα από '
        '${plan.phonesByUser.length} υπαλλήλους και ${_clearFateLabel(plan)}.',
      );
    case BulkClearField.equipment:
      final seen = <int>{};
      for (final l in plan.equipmentByUser.values) {
        for (final e in l) {
          if (e.id != null) seen.add(e.id!);
        }
      }
      buf.write(
        'Θα αποδεσμευτούν ${seen.length} εξοπλισμοί από '
        '${plan.equipmentByUser.length} υπαλλήλους και ${_clearFateLabel(plan)}.',
      );
  }
  for (final ex in plan.exclusions) {
    buf.write('\n• ${ex.reason}');
  }
  return buf.toString();
}

/// Μήνυμα αποτελέσματος ΜΕΤΑ τον Καθαρισμό.
String bulkClearResultMessage(BulkUserClearPlan plan) {
  final buf = StringBuffer();
  switch (plan.field) {
    case BulkClearField.notes:
      buf.write('Διαγράφηκαν οι σημειώσεις ${plan.users.length} υπαλλήλων');
    case BulkClearField.phones:
      final count = [
        for (final l in plan.phonesByUser.values) l.length,
      ].fold(0, (a, b) => a + b);
      buf.write('Αποδεσμεύτηκαν $count τηλέφωνα');
    case BulkClearField.equipment:
      final seen = <int>{};
      for (final l in plan.equipmentByUser.values) {
        for (final e in l) {
          if (e.id != null) seen.add(e.id!);
        }
      }
      buf.write('Αποδεσμεύτηκαν ${seen.length} εξοπλισμοί');
  }
  if (plan.exclusions.isNotEmpty) {
    buf.write(' · ${plan.exclusions.length} εξαιρέσεις');
  }
  buf.write('.');
  return buf.toString();
}

// ─────────────────────── Βοηθητικά ανάγνωσης σε txn ───────────────────────

Future<Map<String, dynamic>?> _userRowInTxn(
  DatabaseExecutor txn,
  int userId,
) async {
  final rows = await txn.query(
    'users',
    columns: ['id', 'department_id', 'notes'],
    where: 'id = ?',
    whereArgs: [userId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<List<String>> _userPhonesInTxn(DatabaseExecutor txn, int userId) async {
  // Χωρίς raw SQL (κανόνας «SQL μόνο στα Repositories»): ο σύνδεσμος και οι
  // αριθμοί διαβάζονται με δύο query στο ίδιο transaction.
  final links = await txn.query(
    'user_phones',
    columns: ['phone_id'],
    where: 'user_id = ?',
    whereArgs: [userId],
  );
  if (links.isEmpty) return const [];
  final phoneIds = [for (final l in links) l['phone_id'] as int];
  final placeholders = List.filled(phoneIds.length, '?').join(', ');
  final rows = await txn.query(
    'phones',
    columns: ['number'],
    where: 'id IN ($placeholders)',
    whereArgs: phoneIds,
    orderBy: 'number',
  );
  return [
    for (final r in rows)
      if ((r['number'] as String?)?.trim().isNotEmpty ?? false)
        (r['number'] as String).trim(),
  ];
}

Future<Map<String, dynamic>?> _equipmentRowByCodeInTxn(
  DatabaseExecutor txn,
  String code,
) async {
  final rows = await txn.query(
    'equipment',
    columns: ['id', 'code_equipment', 'department_id'],
    where: 'code_equipment = ? AND ${DirectorySupport.notDeletedClause}',
    whereArgs: [code],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<Map<String, dynamic>?> _equipmentRowInTxn(
  DatabaseExecutor txn,
  int equipmentId,
) async {
  final rows = await txn.query(
    'equipment',
    columns: ['id', 'code_equipment', 'department_id'],
    where: 'id = ?',
    whereArgs: [equipmentId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<int?> _activeDepartmentIdByNameInTxn(
  DatabaseExecutor txn,
  String name,
) async {
  final key = SearchTextNormalizer.normalizeForSearch(name.trim());
  if (key.isEmpty) return null;
  final rows = await txn.query(
    'departments',
    columns: ['id'],
    where: '${DirectorySupport.notDeletedClause} AND name_key = ?',
    whereArgs: [key],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first['id'] as int?;
}

/// Επιλύει τον προορισμό μεταφοράς μέσα στη συναλλαγή.
/// Επιστρέφει (id τμήματος, id ΜΟΝΟ αν δημιουργήθηκε τώρα).
Future<(int?, int?)> _resolveTransferTargetInTxn(
  DatabaseExecutor txn,
  DepartmentRepository departments,
  SharedAssetTransferTarget target,
) async {
  if (target.departmentId != null) return (target.departmentId, null);
  final name = target.newDepartmentName?.trim();
  if (name == null || name.isEmpty) return (null, null);
  final existing = await _activeDepartmentIdByNameInTxn(txn, name);
  final id = await departments.getOrCreateDepartmentIdByName(
    name,
    executor: txn,
  );
  return (id, existing == null ? id : null);
}

// ─────────────────────── Εφαρμογές σε μία συναλλαγή ───────────────────────

/// Εφαρμόζει τη μαζική μεταφορά ΜΕΣΑ στο [txn] και επιστρέφει πακέτο αναίρεσης.
Future<BulkActionUndoRecord> applyBulkUserTransferInTxn(
  DatabaseExecutor txn,
  Database db,
  BulkUserTransferPlan plan,
) async {
  if (!plan.hasWork) return const BulkActionUndoRecord();

  final users = UserRepository(db);
  final phones = PhoneRepository(db);
  final equipment = EquipmentRepository(db);
  final departments = DepartmentRepository(db);

  final (targetId, createdByTarget) = await _resolveTransferTargetInTxn(
    txn,
    departments,
    plan.target,
  );
  if (targetId == null) return const BulkActionUndoRecord();
  var createdDepartmentId = createdByTarget;

  final userDepartmentBefore = <int, int?>{};
  final userPhonesBefore = <int, List<String>>{};
  final phoneDeptAdds = <PhoneDeptAdd>[];
  final equipmentDepartmentBefore = <String, int?>{};
  final equipmentDepartmentAfter = <String, int>{};
  final unlinked = <BulkUserEquipmentUnlink>[];

  for (final u in plan.usersToMove) {
    final userId = u.id!;
    final row = await _userRowInTxn(txn, userId);
    if (row == null) continue;
    final oldDept = row['department_id'] as int?;
    userDepartmentBefore[userId] = oldDept;

    // Δύο λόγοι να φύγει ένας αριθμός από τον μεταφερόμενο: μένει πίσω ως
    // κοινόχρηστος του τμήματος, ή μένει στους συναδέλφους που τον κρατούν
    // ήδη — τότε δεν προστίθεται στο τμήμα.
    final toRelease = plan.phonesToRelease[userId] ?? const <String>[];
    final leftWithCoOwners =
        plan.phonesLeftWithCoOwners[userId] ?? const <String>[];
    if (toRelease.isNotEmpty || leftWithCoOwners.isNotEmpty) {
      final before = await _userPhonesInTxn(txn, userId);
      userPhonesBefore[userId] = before;
      final remaining = [
        for (final n in before)
          if (!toRelease.contains(n) && !leftWithCoOwners.contains(n)) n,
      ];
      await users.replaceUserPhones(userId, remaining, executor: txn);
      if (oldDept != null) {
        for (final n in toRelease) {
          await phones.addDepartmentDirectPhone(oldDept, n, executor: txn);
          phoneDeptAdds.add(
            PhoneDeptAdd(departmentId: oldDept, phoneNumber: n),
          );
        }
      }
    }

    await users.updateUser(
      userId,
      {'department_id': targetId},
      executor: txn,
      skipPhonePolicyValidation: true,
      expected: null,
    );

    for (final e in plan.equipmentToFollow[userId] ?? const []) {
      final eqRow = await _equipmentRowInTxn(txn, e.id!);
      if (eqRow == null) continue;
      final code = (eqRow['code_equipment'] as String?)?.trim() ?? '';
      if (code.isEmpty) continue;
      final before = eqRow['department_id'] as int?;
      if (before == targetId) continue;
      equipmentDepartmentBefore[code] = before;
      equipmentDepartmentAfter[code] = targetId;
      await equipment.updateEquipmentDepartment(code, targetId, executor: txn);
    }

    for (final e in plan.equipmentToRelease[userId] ?? const []) {
      final eqRow = await _equipmentRowInTxn(txn, e.id!);
      if (eqRow == null) continue;
      final code = (eqRow['code_equipment'] as String?)?.trim() ?? '';
      await equipment.unlinkUserFromEquipment(userId, e.id!, executor: txn);
      unlinked.add(BulkUserEquipmentUnlink(userId: userId, equipmentId: e.id!));
      final eqDept = eqRow['department_id'] as int?;
      if (eqDept == null && oldDept != null && code.isNotEmpty) {
        equipmentDepartmentBefore[code] = null;
        equipmentDepartmentAfter[code] = oldDept;
        await equipment.updateEquipmentDepartment(code, oldDept, executor: txn);
      }
    }
  }

  // Κοινά τηλέφωνα που ακολουθούν τους μεταφερόμενους: φεύγουν από τους
  // κατόχους που ΔΕΝ μεταφέρονται, και το κοινόχρηστο τμήματος πάει στον
  // προορισμό — ένας αριθμός δεν ανήκει σε δύο τμήματα. Κάθε αλλαγή μπαίνει
  // στο πακέτο αναίρεσης.
  final phoneDeptRemovals = <PhoneDeptAdd>[];
  final takenPhones = plan.phonesTakenFromCoOwners;
  if (takenPhones.isNotEmpty) {
    // Όσοι επιλέχθηκαν αλλά είναι ήδη στον προορισμό κρατούν κι αυτοί τον
    // αριθμό: βρίσκονται εκεί που πηγαίνει.
    final keepers = {
      for (final u in [...plan.usersToMove, ...plan.usersAlreadyInTarget])
        if (u.id != null) u.id!,
    };
    for (final n in takenPhones) {
      for (final holder in await phones.holderUserIds(n, executor: txn)) {
        if (keepers.contains(holder)) continue;
        userPhonesBefore[holder] ??= await _userPhonesInTxn(txn, holder);
      }
      final taken = await takePhoneFromCoOwners(
        executor: txn,
        phoneRepo: phones,
        phone: n,
        keepingUserIds: keepers,
        newDepartmentId: targetId,
      );
      for (final departmentId in taken.removedFromDepartmentIds) {
        phoneDeptRemovals.add(
          PhoneDeptAdd(departmentId: departmentId, phoneNumber: n),
        );
      }
      if (taken.addedToNewDepartment) {
        phoneDeptAdds.add(PhoneDeptAdd(departmentId: targetId, phoneNumber: n));
      }
    }
  }

  // Κοινά μηχανήματα που ακολουθούν τους μεταφερόμενους: φεύγουν από τους
  // κατόχους που ΔΕΝ μεταφέρονται — ένα μηχάνημα δεν ανήκει σε δύο τμήματα.
  // Κάθε αφαίρεση μπαίνει στο πακέτο αναίρεσης.
  final takenFromCoOwners = plan.equipmentTakenFromCoOwners;
  if (takenFromCoOwners.isNotEmpty) {
    final movedUserIds = {for (final u in plan.usersToMove) u.id!};
    for (final equipmentId in takenFromCoOwners) {
      final links = await txn.query(
        'user_equipment',
        columns: ['user_id'],
        where: 'equipment_id = ?',
        whereArgs: [equipmentId],
      );
      for (final link in links) {
        final ownerId = link['user_id'] as int?;
        if (ownerId == null || movedUserIds.contains(ownerId)) continue;
        await equipment.unlinkUserFromEquipment(
          ownerId,
          equipmentId,
          executor: txn,
        );
        unlinked.add(
          BulkUserEquipmentUnlink(userId: ownerId, equipmentId: equipmentId),
        );
      }
    }
  }

  // Τα μηχανήματα που δεν χωρούσαν στον προορισμό: ο χρήστης έχει ήδη πει πού
  // πάει το καθένα. Ο δεσμός με τον κάτοχο λύνεται πάντα — ο άνθρωπος φεύγει
  // σε τμήμα που δεν κρατά εξοπλισμό, οπότε δεν μπορεί να μείνει χρεωμένος.
  final softDeletedEquipmentCodes = <String>[];
  final rehoming = plan.equipmentRehoming;
  if (plan.equipmentNeedingNewHome.isNotEmpty) {
    final movedUserIds = [for (final u in plan.usersToMove) u.id!];

    Future<void> unlinkOwners(int equipmentId) async {
      for (final userId in movedUserIds) {
        final links = await txn.query(
          'user_equipment',
          columns: ['user_id'],
          where: 'user_id = ? AND equipment_id = ?',
          whereArgs: [userId, equipmentId],
          limit: 1,
        );
        if (links.isEmpty) continue;
        await equipment.unlinkUserFromEquipment(
          userId,
          equipmentId,
          executor: txn,
        );
        unlinked.add(
          BulkUserEquipmentUnlink(userId: userId, equipmentId: equipmentId),
        );
      }
    }

    for (final entry in rehoming.equipmentTransfers.entries) {
      final code = entry.key.trim();
      if (code.isEmpty) continue;
      final eqRow = await _equipmentRowByCodeInTxn(txn, code);
      if (eqRow == null) continue;
      final (toId, createdNow) = await _resolveTransferTargetInTxn(
        txn,
        departments,
        entry.value,
      );
      if (toId == null) continue;
      createdDepartmentId ??= createdNow;
      await unlinkOwners(eqRow['id'] as int);
      final before = eqRow['department_id'] as int?;
      if (before != toId) {
        equipmentDepartmentBefore[code] = before;
        equipmentDepartmentAfter[code] = toId;
        await equipment.updateEquipmentDepartment(code, toId, executor: txn);
      }
    }

    for (final raw in rehoming.equipmentToDelete) {
      final code = raw.trim();
      if (code.isEmpty) continue;
      final eqRow = await _equipmentRowByCodeInTxn(txn, code);
      if (eqRow == null) continue;
      final eqId = eqRow['id'] as int;
      await unlinkOwners(eqId);
      await equipment.deleteEquipments([eqId], executor: txn);
      softDeletedEquipmentCodes.add(code);
    }
  }

  return BulkActionUndoRecord(
    userDepartmentBefore: userDepartmentBefore,
    userPhonesBefore: userPhonesBefore,
    phoneDeptAdds: phoneDeptAdds,
    phoneDeptRemovals: phoneDeptRemovals,
    equipmentDepartmentBefore: equipmentDepartmentBefore,
    equipmentDepartmentAfter: equipmentDepartmentAfter,
    unlinkedUserEquipment: unlinked,
    softDeletedEquipmentCodes: softDeletedEquipmentCodes,
    createdDepartmentId: createdDepartmentId,
  );
}

/// Εφαρμόζει μαζικές Σημειώσεις ΜΕΣΑ στο [txn].
Future<BulkActionUndoRecord> applyBulkUserNotesInTxn(
  DatabaseExecutor txn,
  Database db, {
  required List<UserModel> users,
  required String text,
  required BulkNotesMode mode,
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty && mode == BulkNotesMode.replace) {
    return const BulkActionUndoRecord();
  }
  final repo = UserRepository(db);
  final notesBefore = <int, String?>{};
  for (final u in users) {
    final userId = u.id;
    if (userId == null) continue;
    final row = await _userRowInTxn(txn, userId);
    if (row == null) continue;
    final before = (row['notes'] as String?)?.trim();
    notesBefore[userId] = row['notes'] as String?;
    final String next;
    if (mode == BulkNotesMode.replace) {
      next = trimmed;
    } else {
      next = (before == null || before.isEmpty) ? trimmed : '$before\n$trimmed';
    }
    await repo.updateUser(
      userId,
      {'notes': next},
      executor: txn,
      skipPhonePolicyValidation: true,
      expected: null,
    );
  }
  return BulkActionUndoRecord(userNotesBefore: notesBefore);
}

/// Εφαρμόζει τον μαζικό Καθαρισμό ΜΕΣΑ στο [txn].
Future<BulkActionUndoRecord> applyBulkUserClearInTxn(
  DatabaseExecutor txn,
  Database db,
  BulkUserClearPlan plan,
) async {
  if (!plan.hasWork) return const BulkActionUndoRecord();

  final users = UserRepository(db);
  final phones = PhoneRepository(db);
  final equipment = EquipmentRepository(db);
  final departments = DepartmentRepository(db);

  final userPhonesBefore = <int, List<String>>{};
  final phoneDeptAdds = <PhoneDeptAdd>[];
  final softDeletedPhoneNumbers = <String>[];
  final softDeletedEquipmentCodes = <String>[];
  final equipmentDepartmentBefore = <String, int?>{};
  final equipmentDepartmentAfter = <String, int>{};
  final unlinked = <BulkUserEquipmentUnlink>[];
  final userNotesBefore = <int, String?>{};
  int? createdDepartmentId;

  int? transferTargetId;
  if (plan.fate == BulkClearFate.transfer && plan.transferTarget != null) {
    final (resolved, created) = await _resolveTransferTargetInTxn(
      txn,
      departments,
      plan.transferTarget!,
    );
    transferTargetId = resolved;
    createdDepartmentId = created;
    if (transferTargetId == null) return const BulkActionUndoRecord();
  }

  switch (plan.field) {
    case BulkClearField.notes:
      for (final u in plan.users) {
        final userId = u.id!;
        final row = await _userRowInTxn(txn, userId);
        if (row == null) continue;
        final before = row['notes'] as String?;
        if (before == null || before.trim().isEmpty) continue;
        userNotesBefore[userId] = before;
        await users.updateUser(
          userId,
          {'notes': null},
          executor: txn,
          skipPhonePolicyValidation: true,
          expected: null,
        );
      }

    case BulkClearField.phones:
      final handledNumbers = <String>{};
      final handledDeptAdds = <String>{};
      for (final entry in plan.phonesByUser.entries) {
        final userId = entry.key;
        final toClear = entry.value;
        if (toClear.isEmpty) continue;
        final before = await _userPhonesInTxn(txn, userId);
        userPhonesBefore[userId] = before;
        final remaining = [
          for (final n in before)
            if (!toClear.contains(n)) n,
        ];
        await users.replaceUserPhones(userId, remaining, executor: txn);

        UserModel? owner;
        for (final u in plan.users) {
          if (u.id == userId) {
            owner = u;
            break;
          }
        }
        for (final n in toClear) {
          switch (plan.fate) {
            case BulkClearFate.deleteOutright:
              if (!handledNumbers.add(n)) continue;
              final id = await phones.getPhoneIdByNumber(n, executor: txn);
              if (id == null) continue;
              await phones.softDeletePhones([id], executor: txn);
              softDeletedPhoneNumbers.add(n);
            case BulkClearFate.shareInOwnDepartment:
              final deptId = owner?.departmentId;
              if (deptId == null) continue;
              if (!handledDeptAdds.add('$deptId|$n')) continue;
              await phones.addDepartmentDirectPhone(deptId, n, executor: txn);
              phoneDeptAdds.add(
                PhoneDeptAdd(departmentId: deptId, phoneNumber: n),
              );
            case BulkClearFate.transfer:
              if (!handledDeptAdds.add('$transferTargetId|$n')) continue;
              await phones.addDepartmentDirectPhone(
                transferTargetId!,
                n,
                executor: txn,
              );
              phoneDeptAdds.add(
                PhoneDeptAdd(departmentId: transferTargetId, phoneNumber: n),
              );
          }
        }
      }

    case BulkClearField.equipment:
      final handledEquipment = <int>{};
      for (final entry in plan.equipmentByUser.entries) {
        final userId = entry.key;
        UserModel? owner;
        for (final u in plan.users) {
          if (u.id == userId) {
            owner = u;
            break;
          }
        }
        for (final e in entry.value) {
          final eqId = e.id!;
          final eqRow = await _equipmentRowInTxn(txn, eqId);
          if (eqRow == null) continue;
          final code = (eqRow['code_equipment'] as String?)?.trim() ?? '';
          await equipment.unlinkUserFromEquipment(userId, eqId, executor: txn);
          unlinked.add(
            BulkUserEquipmentUnlink(userId: userId, equipmentId: eqId),
          );
          if (!handledEquipment.add(eqId)) continue;
          final eqDept = eqRow['department_id'] as int?;
          switch (plan.fate) {
            case BulkClearFate.deleteOutright:
              await equipment.deleteEquipments([eqId], executor: txn);
              if (code.isNotEmpty) softDeletedEquipmentCodes.add(code);
            case BulkClearFate.shareInOwnDepartment:
              final deptId = owner?.departmentId;
              if (eqDept == null && deptId != null && code.isNotEmpty) {
                equipmentDepartmentBefore[code] = null;
                equipmentDepartmentAfter[code] = deptId;
                await equipment.updateEquipmentDepartment(
                  code,
                  deptId,
                  executor: txn,
                );
              }
            case BulkClearFate.transfer:
              if (code.isEmpty || eqDept == transferTargetId) continue;
              equipmentDepartmentBefore[code] = eqDept;
              equipmentDepartmentAfter[code] = transferTargetId!;
              await equipment.updateEquipmentDepartment(
                code,
                transferTargetId,
                executor: txn,
              );
          }
        }
      }
  }

  return BulkActionUndoRecord(
    userPhonesBefore: userPhonesBefore,
    phoneDeptAdds: phoneDeptAdds,
    equipmentDepartmentBefore: equipmentDepartmentBefore,
    equipmentDepartmentAfter: equipmentDepartmentAfter,
    unlinkedUserEquipment: unlinked,
    softDeletedPhoneNumbers: softDeletedPhoneNumbers,
    softDeletedEquipmentCodes: softDeletedEquipmentCodes,
    userNotesBefore: userNotesBefore,
    createdDepartmentId: createdDepartmentId,
  );
}
