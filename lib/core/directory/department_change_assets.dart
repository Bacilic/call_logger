import 'package:sqflite_common/sqlite_api.dart';

import '../../features/calls/models/equipment_model.dart';
import '../database/equipment_repository.dart';
import '../database/phone_repository.dart';
import '../database/user_repository.dart';

/// Εκτελεί την απόφαση «μένει πίσω» όταν ένας υπάλληλος αλλάζει τμήμα.
///
/// **Γιατί ζει εδώ και όχι μέσα σε κάθε οθόνη:** την ίδια απόφαση την παίρνουν
/// η φόρμα υπαλλήλου και η γρήγορη προσθήκη της κλήσης. Γραμμένη δύο φορές θα
/// απέκλινε στην πρώτη αλλαγή — και η οθόνη που θα την ξεχνούσε θα γινόταν
/// σιωπηλή τρύπα στα δεδομένα.
///
/// Η μαζική μεταφορά ΔΕΝ την καλεί: εκεί οι ίδιες ενέργειες τρέχουν μέσα σε
/// μία συναλλαγή με πακέτο αναίρεσης, οπότε δεν μπορούν να βγουν έξω από
/// αυτήν. Ο **κανόνας** που κρίνει τι μένει πίσω είναι ήδη κοινός και για τις
/// τρεις (`judgePhoneStayBehind`, `judgeEquipmentStayBehind`) — και οι δύο
/// ροές ενός υπαλλήλου τον καλούν μέσω των `planPhoneStayBehind` /
/// `planEquipmentStayBehind`, που κρατούν **και τον λόγο** όσων εμποδίστηκαν
/// ώστε να ειπωθεί στον χρήστη.
///
/// Είναι ασφαλές να κληθεί πριν ή μετά την εγγραφή της καρτέλας: η αφαίρεση
/// τηλεφώνου από υπάλληλο που δεν το κρατά πια, και η προσθήκη αριθμού σε
/// τμήμα που ήδη τον έχει, δεν κάνουν τίποτα.
Future<void> applyAssetsStayingBehind({
  required Database db,
  required int userId,
  required int? oldDepartmentId,

  /// Οι αριθμοί που ο χρήστης αποφάσισε να αφήσει στο τμήμα.
  Iterable<String> phones = const [],

  /// Τα μηχανήματα που ο χρήστης αποφάσισε να αφήσει στο τμήμα.
  Iterable<EquipmentModel> equipment = const [],

  /// Τα τηλέφωνα που κρατά σήμερα ο υπάλληλος — τα δίνει ο καλών, ώστε η
  /// συνάρτηση να μη μαντεύει ποια είναι η «τρέχουσα» εικόνα του.
  Iterable<String> currentPhones = const [],

  /// Κοινά μηχανήματα που ακολουθούν τον υπάλληλο («Μεταφέρεται»): φεύγουν
  /// από τους υπόλοιπους κατόχους και παίρνουν το [newDepartmentId], γιατί
  /// ένα μηχάνημα δεν ανήκει σε δύο τμήματα.
  Iterable<EquipmentModel> equipmentTakenFromCoOwners = const [],

  /// Το τμήμα όπου πηγαίνει ο υπάλληλος.
  int? newDepartmentId,

  /// Κοινά τηλέφωνα που μένουν στους υπόλοιπους κατόχους («Παραμένει»):
  /// φεύγουν μόνο από τον υπάλληλο. Δεν γίνονται κοινόχρηστα του τμήματος
  /// — ανήκουν ήδη σε ανθρώπους που μένουν εκεί.
  Iterable<String> phonesLeftWithCoOwners = const [],

  /// Κοινά τηλέφωνα που ακολουθούν τον υπάλληλο («Μεταφέρεται»): δες
  /// [takePhoneFromCoOwners].
  Iterable<String> phonesTakenFromCoOwners = const [],
}) async {
  final released = {
    for (final p in phones)
      if (p.trim().isNotEmpty) p.trim(),
  };
  final leftWithCoOwners = {
    for (final p in phonesLeftWithCoOwners)
      if (p.trim().isNotEmpty) p.trim(),
  };
  final leaving = {...released, ...leftWithCoOwners};
  final takenPhones = {
    for (final p in phonesTakenFromCoOwners)
      if (p.trim().isNotEmpty) p.trim(),
  };
  final machines = equipment.where((e) => e.id != null).toList();
  final taken = equipmentTakenFromCoOwners.where((e) => e.id != null).toList();
  if (leaving.isEmpty &&
      takenPhones.isEmpty &&
      machines.isEmpty &&
      taken.isEmpty) {
    return;
  }

  if (leaving.isNotEmpty) {
    final remaining = [
      for (final p in currentPhones)
        if (!leaving.contains(p.trim())) p,
    ];
    if (remaining.length != currentPhones.length) {
      await UserRepository(db).replaceUserPhones(userId, remaining);
    }
    if (oldDepartmentId != null) {
      final phoneRepo = PhoneRepository(db);
      for (final number in released) {
        await phoneRepo.addDepartmentDirectPhone(oldDepartmentId, number);
      }
    }
  }

  if (takenPhones.isNotEmpty) {
    await db.transaction((txn) async {
      for (final number in takenPhones) {
        await takePhoneFromCoOwners(
          executor: txn,
          phoneRepo: PhoneRepository(db),
          phone: number,
          keepingUserIds: {userId},
          newDepartmentId: newDepartmentId,
        );
      }
    });
  }

  if (machines.isNotEmpty) {
    final equipmentRepo = EquipmentRepository(db);
    for (final item in machines) {
      await equipmentRepo.unlinkUserFromEquipment(userId, item.id!);
      // Το μηχάνημα χωρίς τμήμα παίρνει εκείνο που αφήνει ο άνθρωπος: ο
      // εξοπλισμός δεν μένει ποτέ ορφανός.
      final code = (item.code ?? '').trim();
      if (item.departmentId == null &&
          oldDepartmentId != null &&
          code.isNotEmpty) {
        await equipmentRepo.updateEquipmentDepartment(code, oldDepartmentId);
      }
    }
  }

  if (taken.isNotEmpty) {
    final equipmentRepo = EquipmentRepository(db);
    for (final item in taken) {
      for (final ownerId in await equipmentRepo.ownerIdsOf(item.id!)) {
        if (ownerId == userId) continue;
        await equipmentRepo.unlinkUserFromEquipment(ownerId, item.id!);
      }
      final code = (item.code ?? '').trim();
      if (newDepartmentId != null && code.isNotEmpty) {
        await equipmentRepo.updateEquipmentDepartment(code, newDepartmentId);
      }
    }
  }
}

/// Τι άλλαξε όταν ένα κοινό τηλέφωνο ακολούθησε όποιον μετακινείται — ώστε
/// η μαζική μεταφορά να το βάλει στο πακέτο αναίρεσης.
typedef PhoneTakenFromCoOwners = ({
  List<int> unlinkedUserIds,
  Set<int> removedFromDepartmentIds,
  bool addedToNewDepartment,
});

/// Ένα κοινό τηλέφωνο ακολουθεί όποιον μετακινείται («Μεταφέρεται»).
///
/// Φεύγει από τους υπόλοιπους κατόχους, γιατί ένας αριθμός ανήκει σε ένα
/// τμήμα. Αν ήταν και κοινόχρηστο τμήματος, γίνεται κοινόχρηστο του
/// [newDepartmentId] — ίδια έκβαση με τη «Σύγκρουση τοποθεσίας τηλεφώνου»
/// (απόφαση Διευθυντή 04/10).
///
/// Ένα σημείο για την καρτέλα υπαλλήλου, το «+» και τη μαζική μεταφορά.
Future<PhoneTakenFromCoOwners> takePhoneFromCoOwners({
  required DatabaseExecutor executor,
  required PhoneRepository phoneRepo,
  required String phone,

  /// Όσοι **κρατούν** τον αριθμό: ο υπάλληλος που μετακινείται (και όσοι
  /// πάνε μαζί του). Από όλους τους άλλους φεύγει.
  required Set<int> keepingUserIds,
  required int? newDepartmentId,
}) async {
  final unlinked = <int>[];
  for (final holder in await phoneRepo.holderUserIds(
    phone,
    executor: executor,
  )) {
    if (keepingUserIds.contains(holder)) continue;
    await phoneRepo.unlinkPhoneFromUser(holder, phone, executor: executor);
    unlinked.add(holder);
  }

  final removedFrom = <int>{};
  var added = false;
  final departments = await phoneRepo.sharedDepartmentIds(
    phone,
    executor: executor,
  );
  if (departments.isNotEmpty && newDepartmentId != null) {
    for (final departmentId in departments) {
      if (departmentId == newDepartmentId) continue;
      await phoneRepo.removeDepartmentDirectPhone(
        departmentId,
        phone,
        executor: executor,
      );
      removedFrom.add(departmentId);
    }
    if (!departments.contains(newDepartmentId)) {
      await phoneRepo.addDepartmentDirectPhone(
        newDepartmentId,
        phone,
        executor: executor,
      );
      added = true;
    }
  }
  return (
    unlinkedUserIds: unlinked,
    removedFromDepartmentIds: removedFrom,
    addedToNewDepartment: added,
  );
}
