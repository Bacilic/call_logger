import 'package:flutter/material.dart';

import '../../../calls/models/equipment_model.dart';
import '../../models/department_kind.dart';
import '../../services/bulk_user_actions.dart';
import '../../services/phone_transfer_split.dart';
import 'bulk_user_action_pickers.dart';

/// Οι ΔΥΟ ερωτήσεις «ο υπάλληλος αλλάζει τμήμα — τι γίνεται ό,τι κουβαλά;».
///
/// Ζουν μαζί επειδή είναι μία απόφαση σε δύο σκέλη, με **αντίστροφες**
/// προεπιλογές: το τηλέφωνο μένει στο γραφείο, ο εξοπλισμός ακολουθεί τον
/// άνθρωπο. Όποιος τις δει χωριστά μπαίνει στον πειρασμό να τις κάνει ίδιες.

/// Η ερώτηση για τα τηλέφωνα.
///
/// Την κάνουν και η μαζική μεταφορά και η φόρμα ενός υπαλλήλου, με τις ίδιες
/// λέξεις και την ίδια σειρά. Ο κανόνας του πεδίου είναι σταθερός: ο άνθρωπος
/// μετακομίζει, το τηλέφωνο μένει στο γραφείο — γι' αυτό η παραμονή έρχεται
/// πρώτη. Ο εξοπλισμός κινείται αντίστροφα και ρωτιέται χωριστά.
///
/// **Ρωτά μόνο για ό,τι μπορεί όντως να ακολουθήσει.** Το [split] έχει ήδη
/// βγάλει στην άκρη τα εσωτερικά του δικού μας κέντρου όταν ο προορισμός δεν
/// τα κρατά: εκείνα μένουν πίσω ό,τι κι αν απαντηθεί, και **αναγγέλλονται**
/// μέσα στο μήνυμα αντί να φύγουν σιωπηλά. Αν δεν απομένει τίποτα
/// διαπραγματεύσιμο, η ερώτηση δεν ανοίγει καθόλου.
Future<BulkTransferAssetFate?> askPhoneFateOnDepartmentChange(
  BuildContext context, {

  /// Ποια τηλέφωνα ρωτιούνται και ποια μένουν αναγκαστικά.
  required PhoneTransferSplit split,

  /// Το Είδος του τμήματος-προορισμού — γράφεται στην αναγγελία.
  required DepartmentKind targetKind,

  /// Κενό για τη μαζική ροή· το όνομα του υπαλλήλου στη φόρμα ενός.
  String? userDisplayName,

  /// Το τμήμα που αφήνει· κενό στη μαζική, όπου δεν είναι ένα.
  String? sourceDepartmentName,

  /// Ό,τι **δεν μπορεί να μείνει πίσω** και γιατί — π.χ. «το χρησιμοποιεί και
  /// ο Χ». Λέγεται **πριν** την ερώτηση: αλλιώς ο χρήστης απαντά «μένουν» και
  /// η απάντηση αγνοείται σιωπηλά για εκείνον τον αριθμό.
  List<String> stayBlockedReasons = const [],
}) async {
  final forcedNote = forcedPhoneStayMessage(
    split: split,
    targetKind: targetKind,
    sourceDepartmentName: sourceDepartmentName,
  );
  final blockedNote = _stayBlockedNote(stayBlockedReasons);

  // Τίποτα να ρωτηθεί: ό,τι υπήρχε μένει πίσω. Η αναγγελία γίνεται ούτως ή
  // άλλως — σιωπηλή αλλαγή δεδομένων δεν επιτρέπεται επειδή δεν υπήρχε
  // ερώτηση να τη συνοδεύσει.
  if (!split.asksAnything) {
    final note = [?forcedNote, ?blockedNote].join('\n\n');
    if (note.isNotEmpty && context.mounted) {
      final approved = await showBulkConfirmDialog(
        context,
        title: 'Τηλέφωνα του νοσοκομείου',
        message: note,
        confirmLabel: 'Συνέχεια',
      );
      if (!approved) return null;
    }
    return BulkTransferAssetFate.stayInOldDepartment;
  }

  final who = userDisplayName?.trim() ?? '';
  final forOneUser = who.isNotEmpty;
  // **Ο αριθμός ακολουθεί ΟΣΑ ΡΩΤΙΟΥΝΤΑΙ, όχι όσα κρατά ο υπάλληλος.** Όταν
  // ένα εσωτερικό έχει ήδη βγει στην άκρη, ένα «Μένουν» στον πληθυντικό θα
  // υποσχόταν απόφαση για δύο αριθμούς ενώ αφορά έναν — και ο χρήστης βλέπει
  // δύο στο πεδίο από πάνω.
  final one = split.negotiable.length == 1;

  return showBulkOptionDialog<BulkTransferAssetFate>(
    context,
    title: forOneUser ? 'Τηλέφωνα του υπαλλήλου' : 'Τηλέφωνα των υπαλλήλων',
    // Πρώτα τι είναι ήδη αποφασισμένο, μετά τι ρωτιέται: η αναγγελία εξηγεί
    // γιατί η ερώτηση αφορά λιγότερα από όσα φαίνονται στην καρτέλα.
    message: [
      ?forcedNote,
      ?blockedNote,
      _questionLine(
        split: split,
        userDisplayName: who,
        namesTheNumbers: split.hasForced,
      ),
    ].join('\n\n'),
    options: [
      (
        _stayingOptionLabel(sourceDepartmentName, one: one),
        one
            ? 'Αποδεσμεύεται από τον υπάλληλο και γίνεται κοινόχρηστο '
                  'του τμήματος που αφήνει.'
            : 'Αποδεσμεύονται από τον υπάλληλο και γίνονται κοινόχρηστα '
                  'του τμήματος που αφήνει.',
        BulkTransferAssetFate.stayInOldDepartment,
      ),
      (
        _followOptionLabel(forOneUser: forOneUser, one: one),
        _followOptionHint(forOneUser: forOneUser, one: one),
        BulkTransferAssetFate.follow,
      ),
    ],
  );
}

/// Οι λόγοι όσων δεν μπορούν να μείνουν πίσω, σε ένα μπλοκ.
///
/// Μπαίνει **πάνω** από την ερώτηση, δίπλα στην αναγγελία των εσωτερικών: ο
/// χρήστης πρέπει να ξέρει τι δεν πρόκειται να γίνει **πριν** διαλέξει, αντί
/// να το ανακαλύψει αργότερα — ή ποτέ.
String? _stayBlockedNote(List<String> reasons) {
  if (reasons.isEmpty) return null;
  return reasons.join('\n');
}

/// Η γραμμή που ρωτά — **ονομάζει τους αριθμούς όταν δεν τους ρωτά όλους**.
///
/// Χωρίς τα ονόματα, ο χρήστης με δύο τηλέφωνα στην καρτέλα διαβάζει «τα
/// τηλέφωνα» και νομίζει ότι απαντά και για τα δύο.
String _questionLine({
  required PhoneTransferSplit split,
  required String userDisplayName,
  required bool namesTheNumbers,
}) {
  final forOneUser = userDisplayName.isNotEmpty;
  if (!namesTheNumbers) {
    return forOneUser
        ? 'Τι θα γίνουν τα τηλέφωνα του υπαλλήλου «$userDisplayName»;'
        : 'Τι θα γίνουν τα προσωπικά τηλέφωνα των μεταφερόμενων;';
  }

  final listed = _listNumbers(split.negotiable);
  if (listed == null) {
    return 'Τι θα γίνουν τα υπόλοιπα προσωπικά τηλέφωνα;';
  }
  return split.negotiable.length == 1
      ? 'Τι θα γίνει το $listed;'
      : 'Τι θα γίνουν τα $listed;';
}

/// «2503, 2741022667» — ή `null` όταν είναι τόσα που η λίστα παύει να βοηθά.
///
/// Πάνω από τέσσερα, η απαρίθμηση γίνεται σεντόνι και κρύβει ακριβώς την
/// πληροφορία που υποτίθεται ότι δίνει.
String? _listNumbers(List<String> numbers) {
  if (numbers.isEmpty || numbers.length > 4) return null;
  return numbers.join(', ');
}

String _followOptionLabel({required bool forOneUser, required bool one}) {
  if (!forOneUser) return 'Ακολουθούν τους υπαλλήλους';
  return one ? 'Ακολουθεί τον υπάλληλο' : 'Ακολουθούν τον υπάλληλο';
}

String _followOptionHint({required bool forOneUser, required bool one}) {
  if (!forOneUser) {
    return 'Παραμένουν προσωπικά τηλέφωνα των υπαλλήλων στο νέο τμήμα.';
  }
  return one
      ? 'Παραμένει προσωπικό τηλέφωνό του στο νέο τμήμα.'
      : 'Παραμένουν προσωπικά τηλέφωνά του στο νέο τμήμα.';
}

/// «Μένει στο τμήμα «Γραφείο Κίνησης»» — ή «στο παλιό τους τμήμα» χωρίς όνομα.
///
/// Στη μαζική μεταφορά οι υπάλληλοι μπορεί να προέρχονται από διαφορετικά
/// τμήματα, οπότε ένα όνομα θα ήταν ψέμα για τους μισούς.
String _stayingOptionLabel(String? sourceDepartmentName, {required bool one}) {
  final verb = one ? 'Μένει' : 'Μένουν';
  final name = sourceDepartmentName?.trim() ?? '';
  return name.isEmpty
      ? '$verb στο παλιό τους τμήμα'
      : '$verb στο τμήμα «$name»';
}

/// Η ερώτηση για τον εξοπλισμό — αντίστροφη σειρά επιλογών από τα τηλέφωνα.
///
/// Ο εξοπλισμός είναι εργαλείο του ανθρώπου και τον ακολουθεί· γι' αυτό το
/// «Ακολουθεί» έρχεται πρώτο. Το τηλέφωνο είναι θέση στο γραφείο και μένει.
///
/// **Η ερώτηση γίνεται ΜΟΝΟ όταν ο προορισμός μπορεί να κρατά μηχανήματα.**
/// Στην εταιρεία δεν μπορεί, και το «Ακολουθεί» θα ήταν υπόσχεση που δεν
/// τηρείται: το μηχάνημα θα έμενε χρεωμένο σε άνθρωπο που δεν δικαιούται να το
/// κρατά. Τότε η απάντηση είναι μία και δίνεται χωρίς ερώτηση — μένει πίσω.
///
/// Η πύλη ζει **εδώ** και όχι στους καλούντες: τρεις ροές κάνουν αυτή την
/// ερώτηση (μαζική μεταφορά, καρτέλα υπαλλήλου, γρήγορη συσχέτιση από την
/// κλήση), και όσο ο κανόνας ζούσε σε έναν από αυτούς, οι άλλοι δύο τον
/// παραβίαζαν σιωπηλά. Το [targetKind] είναι **υποχρεωτικό** ώστε μια τέταρτη
/// ροή να μην μπορεί να τον ξεχάσει.
Future<BulkTransferAssetFate?> askEquipmentFateOnDepartmentChange(
  BuildContext context, {

  /// Το Είδος του τμήματος-προορισμού. Για τμήμα που δημιουργείται εκείνη τη
  /// στιγμή είναι πάντα νοσοκομείο.
  required DepartmentKind targetKind,

  /// Κενό για τη μαζική ροή· το όνομα του υπαλλήλου στη φόρμα ενός.
  String? userDisplayName,

  /// Ό,τι **δεν μπορεί να μείνει πίσω** και γιατί — ίδιος λόγος ύπαρξης με το
  /// αντίστοιχο των τηλεφώνων: η εξαίρεση λέγεται πριν, όχι ποτέ.
  List<String> stayBlockedReasons = const [],
}) async {
  final blockedNote = _stayBlockedNote(stayBlockedReasons);

  if (!targetKind.canOwnEquipment) {
    // Δεν υπάρχει τι να ρωτηθεί, αλλά υπάρχει τι να ειπωθεί: ο προορισμός δεν
    // κρατά μηχανήματα ΚΑΙ κάποια από αυτά δεν μπορούν ούτε να μείνουν πίσω.
    if (blockedNote != null && context.mounted) {
      final approved = await showBulkConfirmDialog(
        context,
        title: 'Εξοπλισμός του νοσοκομείου',
        message: blockedNote,
        confirmLabel: 'Συνέχεια',
      );
      if (!approved) return null;
    }
    return BulkTransferAssetFate.stayInOldDepartment;
  }

  final who = userDisplayName?.trim() ?? '';
  final singular = who.isNotEmpty;

  if (!context.mounted) return null;
  return showBulkOptionDialog<BulkTransferAssetFate>(
    context,
    title: singular ? 'Εξοπλισμός του υπαλλήλου' : 'Εξοπλισμός των υπαλλήλων',
    // Πρώτα τι δεν γίνεται, μετά τι ρωτιέται — όπως στα τηλέφωνα.
    // Το άρθρο δένει με τη λέξη «υπαλλήλου», ποτέ με το όνομα.
    message: [
      ?blockedNote,
      singular
          ? 'Τι θα γίνει ο εξοπλισμός του υπαλλήλου «$who»;'
          : 'Τι θα γίνει ο εξοπλισμός των μεταφερόμενων;',
    ].join('\n\n'),
    options: [
      (
        'Ακολουθεί στο νέο τμήμα',
        'Ο εξοπλισμός αλλάζει τμήμα μαζί με τον κάτοχό του.',
        BulkTransferAssetFate.follow,
      ),
      (
        'Μένει στο παλιό τμήμα',
        'Αποδεσμεύεται από τον υπάλληλο και παραμένει στο τμήμα που αφήνει.',
        BulkTransferAssetFate.stayInOldDepartment,
      ),
    ],
  );
}

/// «Κοινός εξοπλισμός» — ένας από τους κατόχους του αλλάζει τμήμα.
///
/// Η ερώτηση αφορά την τύχη του **μηχανήματος**, όχι του υπαλλήλου (απόφαση
/// Διευθυντή 03/10): συνήθως το κοινό μηχάνημα μένει στο τμήμα του, γι' αυτό
/// η παραμονή έρχεται πρώτη. `null` = «Ακύρωση».
///
/// Τα ονόματα μπαίνουν σε εισαγωγικά ή μετά από άνω-κάτω τελεία: η εφαρμογή
/// δεν ξέρει το φύλο των υπαλλήλων, οπότε δεν γράφει «η Νακαστσή».
Future<SharedAssetFate?> askSharedEquipmentFate(
  BuildContext context, {
  required SharedEquipment shared,
  required String userDisplayName,
  required String? sourceDepartmentName,
  required String targetDepartmentName,
}) {
  final code = (shared.equipment.code ?? '').trim();
  final others = shared.otherOwnerNames.join(', ');
  final source = sourceDepartmentName?.trim() ?? '';
  return showBulkOptionDialog<SharedAssetFate>(
    context,
    title: 'Κοινός εξοπλισμός',
    message: [
      'Ο υπάλληλος «$userDisplayName» μεταφέρεται στο τμήμα '
          '«$targetDepartmentName».',
      'Ο εξοπλισμός $code μοιράζεται με: $others.',
      'Τι γίνεται ο εξοπλισμός $code;',
    ].join('\n\n'),
    options: [
      (
        source.isEmpty
            ? 'Παραμένει στο τμήμα του'
            : 'Παραμένει στο τμήμα «$source»',
        'Φεύγει από: $userDisplayName· το κρατούν: $others.',
        SharedAssetFate.staysInDepartment,
      ),
      (
        'Μεταφέρεται στο τμήμα «$targetDepartmentName»',
        'Ακολουθεί: $userDisplayName· φεύγει από: $others.',
        SharedAssetFate.movesWithOwner,
      ),
    ],
  );
}

/// Η ίδια ερώτηση στη μαζική μεταφορά: **μία** για όλα τα κοινά μηχανήματα
/// (απόφαση Διευθυντή 03/10). `null` = «Ακύρωση».
Future<SharedAssetFate?> askSharedEquipmentFateForMany(
  BuildContext context, {
  required List<SharedEquipment> shared,
}) {
  final codes = sharedEquipmentCodesText(shared);
  return showBulkOptionDialog<SharedAssetFate>(
    context,
    title: 'Κοινός εξοπλισμός',
    message:
        'Ο κοινός εξοπλισμός ($codes) παραμένει στο τμήμα του ή '
        'μεταφέρεται;',
    options: const [
      (
        'Παραμένει στο τμήμα του',
        'Φεύγει μόνο από τους μεταφερόμενους· τον κρατούν οι υπόλοιποι '
            'κάτοχοι.',
        SharedAssetFate.staysInDepartment,
      ),
      (
        'Μεταφέρεται',
        'Ακολουθεί τους μεταφερόμενους· φεύγει από τους υπόλοιπους '
            'κατόχους.',
        SharedAssetFate.movesWithOwner,
      ),
    ],
  );
}

/// Τι γίνεται ο εξοπλισμός ενός υπαλλήλου που αλλάζει τμήμα.
///
/// [staying]: φεύγουν από τον υπάλληλο και μένουν στο παλιό τμήμα.
/// [takenFromCoOwners]: κοινά μηχανήματα που τον ακολουθούν — φεύγουν από
/// τους υπόλοιπους κατόχους. Ό,τι δεν είναι σε καμία λίστα ακολουθεί.
typedef EquipmentDepartmentChangeAnswer = ({
  List<EquipmentModel> staying,
  List<EquipmentModel> takenFromCoOwners,
});

/// Όλες οι ερωτήσεις εξοπλισμού ενός υπαλλήλου που αλλάζει τμήμα, με σειρά:
/// πρώτα η γενική («ακολουθεί ή μένει;») για τα **δικά του** μηχανήματα,
/// μετά μία ερώτηση για κάθε **κοινό** μηχάνημα. `null` = «Ακύρωση» σε
/// κάποια από αυτές.
///
/// Την καλούν η καρτέλα υπαλλήλου και το «+» της φόρμας κλήσης — ίδιες
/// ερωτήσεις, ίδια σειρά.
Future<EquipmentDepartmentChangeAnswer?> askEquipmentOnDepartmentChange(
  BuildContext context, {
  required EquipmentStayBehindPlan plan,
  required DepartmentKind targetKind,
  required String userDisplayName,
  required String? sourceDepartmentName,
  required String targetDepartmentName,
}) async {
  final staying = <EquipmentModel>[];
  final taken = <EquipmentModel>[];

  final hasOwnEquipment =
      plan.staying.isNotEmpty || plan.blockedReasons.isNotEmpty;
  if (hasOwnEquipment) {
    if (!context.mounted) return null;
    final fate = await askEquipmentFateOnDepartmentChange(
      context,
      targetKind: targetKind,
      userDisplayName: userDisplayName,
      stayBlockedReasons: plan.blockedReasons,
    );
    if (fate == null) return null;
    if (fate == BulkTransferAssetFate.stayInOldDepartment) {
      staying.addAll(plan.staying);
    }
  }

  for (final shared in plan.shared) {
    // Προορισμός που δεν κρατά εξοπλισμό: το μηχάνημα δεν μπορεί να πάει
    // εκεί — μένει στο τμήμα του, χωρίς ερώτηση.
    if (!targetKind.canOwnEquipment) {
      staying.add(shared.equipment);
      continue;
    }
    if (!context.mounted) return null;
    final fate = await askSharedEquipmentFate(
      context,
      shared: shared,
      userDisplayName: userDisplayName,
      sourceDepartmentName: sourceDepartmentName,
      targetDepartmentName: targetDepartmentName,
    );
    if (fate == null) return null;
    if (fate == SharedAssetFate.staysInDepartment) {
      staying.add(shared.equipment);
    } else {
      taken.add(shared.equipment);
    }
  }
  return (staying: staying, takenFromCoOwners: taken);
}

/// «Κοινό τηλέφωνο» — ένας από τους κατόχους του αλλάζει τμήμα.
///
/// Δίδυμο του [askSharedEquipmentFate] (απόφαση Διευθυντή 04/10): η ερώτηση
/// αφορά την τύχη του **αριθμού**, γιατί ένας αριθμός ανήκει σε ένα τμήμα.
/// `null` = «Ακύρωση».
Future<SharedAssetFate?> askSharedPhoneFate(
  BuildContext context, {
  required SharedPhone shared,
  required String userDisplayName,
  required String? sourceDepartmentName,
  required String targetDepartmentName,
}) {
  final phone = shared.phone;
  final others = shared.otherOwnerNames.join(', ');
  final source = sourceDepartmentName?.trim() ?? '';
  return showBulkOptionDialog<SharedAssetFate>(
    context,
    title: 'Κοινό τηλέφωνο',
    message: [
      'Ο υπάλληλος «$userDisplayName» μεταφέρεται στο τμήμα '
          '«$targetDepartmentName».',
      'Το τηλέφωνο $phone μοιράζεται με: $others.',
      'Τι γίνεται το τηλέφωνο $phone;',
    ].join('\n\n'),
    options: [
      (
        source.isEmpty
            ? 'Παραμένει στο τμήμα του'
            : 'Παραμένει στο τμήμα «$source»',
        'Φεύγει από: $userDisplayName· το κρατούν: $others.',
        SharedAssetFate.staysInDepartment,
      ),
      (
        'Μεταφέρεται στο τμήμα «$targetDepartmentName»',
        'Ακολουθεί: $userDisplayName· φεύγει από: $others.',
        SharedAssetFate.movesWithOwner,
      ),
    ],
  );
}

/// Η ίδια ερώτηση στη μαζική μεταφορά: **μία** για όλα τα κοινά τηλέφωνα
/// (απόφαση Διευθυντή 04/10). `null` = «Ακύρωση».
Future<SharedAssetFate?> askSharedPhoneFateForMany(
  BuildContext context, {
  required List<SharedPhone> shared,
}) {
  final numbers = sharedPhoneNumbersText(shared);
  final one = shared.length == 1;
  return showBulkOptionDialog<SharedAssetFate>(
    context,
    title: 'Κοινό τηλέφωνο',
    message: one
        ? 'Το κοινό τηλέφωνο ($numbers) παραμένει στο τμήμα του ή '
              'μεταφέρεται;'
        : 'Τα κοινά τηλέφωνα ($numbers) παραμένουν στο τμήμα τους ή '
              'μεταφέρονται;',
    options: [
      (
        one ? 'Παραμένει στο τμήμα του' : 'Παραμένουν στο τμήμα τους',
        one
            ? 'Φεύγει μόνο από τους μεταφερόμενους· το κρατούν οι υπόλοιποι '
                  'κάτοχοι.'
            : 'Φεύγουν μόνο από τους μεταφερόμενους· τα κρατούν οι υπόλοιποι '
                  'κάτοχοι.',
        SharedAssetFate.staysInDepartment,
      ),
      (
        one ? 'Μεταφέρεται' : 'Μεταφέρονται',
        one
            ? 'Ακολουθεί τους μεταφερόμενους· φεύγει από τους υπόλοιπους '
                  'κατόχους.'
            : 'Ακολουθούν τους μεταφερόμενους· φεύγουν από τους υπόλοιπους '
                  'κατόχους.',
        SharedAssetFate.movesWithOwner,
      ),
    ],
  );
}

/// Τι γίνονται τα τηλέφωνα ενός υπαλλήλου που αλλάζει τμήμα.
///
/// [staying]: φεύγουν από τον υπάλληλο και γίνονται κοινόχρηστα του παλιού
/// τμήματος. [leftWithCoOwners]: κοινά τηλέφωνα που φεύγουν από τον υπάλληλο
/// και μένουν στους συναδέλφους. [takenFromCoOwners]: κοινά τηλέφωνα που τον
/// ακολουθούν — φεύγουν από τους συναδέλφους. Ό,τι δεν είναι σε καμία λίστα
/// ακολουθεί.
typedef PhoneDepartmentChangeAnswer = ({
  Set<String> staying,
  Set<String> leftWithCoOwners,
  Set<String> takenFromCoOwners,
});

/// Όλες οι ερωτήσεις τηλεφώνων ενός υπαλλήλου που αλλάζει τμήμα, με σειρά:
/// πρώτα η γενική («μένουν ή ακολουθούν;») για τα **δικά του** τηλέφωνα, μετά
/// μία ερώτηση για κάθε **κοινό** τηλέφωνο. Κάθε αριθμός ρωτιέται μία φορά.
/// `null` = «Ακύρωση» σε κάποια από αυτές.
///
/// Την καλούν η καρτέλα υπαλλήλου και το «+» της φόρμας κλήσης — ίδιες
/// ερωτήσεις, ίδια σειρά, όπως και ο δίδυμος [askEquipmentOnDepartmentChange].
Future<PhoneDepartmentChangeAnswer?> askPhonesOnDepartmentChange(
  BuildContext context, {

  /// Ποια τηλέφωνα μπορούν να ακολουθήσουν και ποια μένουν αναγκαστικά.
  required PhoneTransferSplit split,

  /// Ο κανόνας για τα διαπραγματεύσιμα του [split] — ξεχωρίζει τα κοινά.
  required PhoneStayBehindPlan plan,
  required DepartmentKind targetKind,
  required String userDisplayName,
  required String? sourceDepartmentName,
  required String targetDepartmentName,
}) async {
  final sharedNumbers = {for (final s in plan.shared) s.phone.trim()};
  final ownSplit = PhoneTransferSplit(
    forcedToStay: split.forcedToStay,
    negotiable: [
      for (final p in split.negotiable)
        if (!sharedNumbers.contains(p.trim())) p,
    ],
  );
  final staying = {for (final p in split.forcedToStay) p.trim()};
  final left = <String>{};
  final taken = <String>{};

  if (ownSplit.asksAnything || ownSplit.hasForced) {
    if (!context.mounted) return null;
    final fate = await askPhoneFateOnDepartmentChange(
      context,
      split: ownSplit,
      targetKind: targetKind,
      userDisplayName: userDisplayName,
      sourceDepartmentName: sourceDepartmentName,
      stayBlockedReasons: plan.blockedReasons,
    );
    if (fate == null) return null;
    if (fate == BulkTransferAssetFate.stayInOldDepartment) {
      staying.addAll(plan.staying);
    }
  }

  for (final shared in plan.shared) {
    if (!context.mounted) return null;
    final fate = await askSharedPhoneFate(
      context,
      shared: shared,
      userDisplayName: userDisplayName,
      sourceDepartmentName: sourceDepartmentName,
      targetDepartmentName: targetDepartmentName,
    );
    if (fate == null) return null;
    if (fate == SharedAssetFate.staysInDepartment) {
      left.add(shared.phone.trim());
    } else {
      taken.add(shared.phone.trim());
    }
  }
  return (staying: staying, leftWithCoOwners: left, takenFromCoOwners: taken);
}
