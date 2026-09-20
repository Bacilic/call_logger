import 'package:flutter/material.dart';

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
