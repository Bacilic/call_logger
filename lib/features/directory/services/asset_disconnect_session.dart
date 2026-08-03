// Συνεδρία αποδέσμευσης: μετρητής βημάτων και καθολικές («γρήγορες») αποφάσεις.
//
// Η συνεδρία γεννιέται ΜΙΑ φορά από τον καλούντα, πριν από τους βρόχους, και
// ταξιδεύει μαζί τους. Χωρίς αυτήν ο διάλογος βλέπει μόνο ένα στοιχείο τη φορά
// και δεν μπορεί να δηλώσει «Βήμα 6 από 24» ούτε να εφαρμόσει μία απάντηση σε
// όλα τα υπόλοιπα.

import 'asset_disconnect_models.dart';

/// Είδος στοιχείου που αποδεσμεύεται.
enum AssetDisconnectItemKind { phone, equipment }

/// Ένα στοιχείο προς απόφαση: αριθμός τηλεφώνου ή κωδικός εξοπλισμού.
///
/// [ownerName] και [departmentName] υπάρχουν για να μη βλέπει ο χρήστης ξερούς
/// αριθμούς: μια λίστα «2216, 2101, 462» δεν του λέει τίποτα.
class AssetDisconnectItem {
  const AssetDisconnectItem({
    required this.kind,
    required this.value,
    this.ownerName,
    this.departmentId,
    this.departmentName,
  });

  const AssetDisconnectItem.phone(
    this.value, {
    this.ownerName,
    this.departmentId,
    this.departmentName,
  }) : kind = AssetDisconnectItemKind.phone;

  const AssetDisconnectItem.equipment(
    this.value, {
    this.ownerName,
    this.departmentId,
    this.departmentName,
  }) : kind = AssetDisconnectItemKind.equipment;

  final AssetDisconnectItemKind kind;
  final String value;

  /// Ο υπάλληλος που το κατέχει· κενό για κοινόχρηστα στοιχεία τμήματος.
  final String? ownerName;

  final int? departmentId;
  final String? departmentName;

  bool get isPhone => kind == AssetDisconnectItemKind.phone;
}

/// Πόσες ιστορικές εγγραφές κρατούν ένα στοιχείο (εκκρεμότητες + κλήσεις).
class AssetHistoryLinks {
  const AssetHistoryLinks({this.tasks = 0, this.calls = 0});

  final int tasks;
  final int calls;

  bool get isEmpty => tasks <= 0 && calls <= 0;
}

/// Σε ποια στοιχεία εφαρμόζεται μια καθολική απόφαση.
enum AssetDisconnectStandingScope { phonesOnly, equipmentOnly, everything }

/// Απόφαση που εφαρμόζεται στα υπόλοιπα στοιχεία χωρίς νέα ερώτηση.
class AssetDisconnectStandingDecision {
  const AssetDisconnectStandingDecision({
    required this.choice,
    required this.scope,
    this.transferTarget,
  });

  const AssetDisconnectStandingDecision.deleteEverything()
    : choice = SharedAssetDisconnectChoice.delete,
      scope = AssetDisconnectStandingScope.everything,
      transferTarget = null;

  const AssetDisconnectStandingDecision.deletePhones()
    : choice = SharedAssetDisconnectChoice.delete,
      scope = AssetDisconnectStandingScope.phonesOnly,
      transferTarget = null;

  const AssetDisconnectStandingDecision.deleteEquipment()
    : choice = SharedAssetDisconnectChoice.delete,
      scope = AssetDisconnectStandingScope.equipmentOnly,
      transferTarget = null;

  const AssetDisconnectStandingDecision.keepEverything()
    : choice = SharedAssetDisconnectChoice.keepInDepartment,
      scope = AssetDisconnectStandingScope.everything,
      transferTarget = null;

  const AssetDisconnectStandingDecision.transferEverything(this.transferTarget)
    : choice = SharedAssetDisconnectChoice.transfer,
      scope = AssetDisconnectStandingScope.everything;

  final SharedAssetDisconnectChoice choice;
  final AssetDisconnectStandingScope scope;
  final SharedAssetTransferTarget? transferTarget;

  bool appliesTo(AssetDisconnectItemKind kind) {
    switch (scope) {
      case AssetDisconnectStandingScope.everything:
        return true;
      case AssetDisconnectStandingScope.phonesOnly:
        return kind == AssetDisconnectItemKind.phone;
      case AssetDisconnectStandingScope.equipmentOnly:
        return kind == AssetDisconnectItemKind.equipment;
    }
  }

  /// Το αποτέλεσμα που παίρνει ένα στοιχείο όταν ισχύει αυτή η απόφαση.
  SharedAssetDisconnectItemResult toItemResult() {
    switch (choice) {
      case SharedAssetDisconnectChoice.keepInDepartment:
        return const SharedAssetDisconnectItemResult.keep();
      case SharedAssetDisconnectChoice.transfer:
        return SharedAssetDisconnectItemResult.transfer(transferTarget);
      case SharedAssetDisconnectChoice.delete:
        return const SharedAssetDisconnectItemResult.delete();
    }
  }
}

/// Δουλειά που έχει ήδη ολοκληρωθεί έξω από αυτή τη ροή, όταν η διακοπή
/// μπορεί να την κρατήσει.
///
/// [summary] λέει τι ολοκληρώθηκε («Ολοκληρώσατε 4 υπαλλήλους από τους 9.»)
/// και [applyHint] τι ακριβώς θα συμβεί αν ο χρήστης το κρατήσει.
typedef AssetDisconnectCompletedWork = ({String summary, String applyHint});

/// Πώς τελείωσε μια ροή που διακόπηκε.
enum AssetDisconnectStopKind {
  /// Τίποτα δεν κρατιέται — η προεπιλογή για κάθε διακοπή.
  cancelAll,

  /// Σταματά εδώ, αλλά ό,τι έχει ήδη ολοκληρωθεί εφαρμόζεται.
  applyCompleted,
}

/// Κρατά τον λογαριασμό μιας ολόκληρης ροής αποδέσμευσης.
///
/// [cancelScopeDescription] περιγράφει τι ακυρώνεται συνολικά (π.χ. «η
/// διαγραφή 10 υπαλλήλων»), ώστε η Ακύρωση να μη μοιάζει αδιαφανής.
///
/// [contextLabel] μπαίνει μπροστά από τον μετρητή όταν η ενέργεια έχει
/// περισσότερες από μία συνεδρίες (π.χ. «Τμήμα 2 από 3»). Χωρίς αυτό, ο
/// μετρητής θα φαινόταν να μηδενίζεται ανεξήγητα στο επόμενο τμήμα.
///
/// [completedWork] δίνεται **μόνο** από ροές που έχουν διέξοδο (μαζική
/// διαγραφή). Επιστρέφει `null` όταν εκείνη τη στιγμή δεν υπάρχει τίποτα
/// ολοκληρωμένο, οπότε η επιβεβαίωση διακοπής μένει με δύο επιλογές.
class AssetDisconnectSession {
  AssetDisconnectSession({
    Iterable<AssetDisconnectItem> items = const [],
    this.cancelScopeDescription,
    this.contextLabel,
    this.completedWork,
  }) {
    registerItems(items);
  }

  final String? cancelScopeDescription;
  final String? contextLabel;
  final AssetDisconnectCompletedWork? Function()? completedWork;

  AssetDisconnectStopKind _stopKind = AssetDisconnectStopKind.cancelAll;

  /// Τι ζήτησε ο χρήστης στη διακοπή. Έχει νόημα μόνο αφού η ροή επιστρέψει
  /// `null`· κάθε άλλη έξοδος (π.χ. αποσυναρμολόγηση οθόνης) μένει στο
  /// ασφαλές `cancelAll`.
  AssetDisconnectStopKind get stopKind => _stopKind;

  void markStop(AssetDisconnectStopKind kind) => _stopKind = kind;

  final List<AssetDisconnectItem> _pending = <AssetDisconnectItem>[];
  int _totalSteps = 0;
  int _resolvedSteps = 0;
  AssetDisconnectStandingDecision? _standingDecision;

  /// Συνολικά βήματα της ροής (όλα τα δηλωμένα στοιχεία).
  int get totalSteps => _totalSteps;

  /// Πόσα στοιχεία έχουν ήδη απαντηθεί.
  int get resolvedSteps => _resolvedSteps;

  /// Ο αριθμός του βήματος που ρωτιέται τώρα (1-based).
  int get currentStep => _resolvedSteps + 1;

  /// Πόσα στοιχεία απομένουν, μαζί με αυτό που ρωτιέται τώρα.
  int get remainingSteps => _pending.length;

  /// Ο μετρητής κρύβεται όταν υπάρχει ένα μόνο βήμα — «1 από 1» είναι θόρυβος.
  bool get showsStepCounter => _totalSteps >= 2;

  List<AssetDisconnectItem> get remainingItems =>
      List<AssetDisconnectItem>.unmodifiable(_pending);

  int get remainingPhoneCount => _pending.where((i) => i.isPhone).length;

  int get remainingEquipmentCount => _pending.where((i) => !i.isPhone).length;

  /// Κανένα βήμα δεν έχει απαντηθεί ακόμα — τα «υπόλοιπα» είναι «όλα».
  bool get isAtFirstStep => _resolvedSteps == 0;

  /// Το τμήμα που μοιράζονται ΟΛΑ τα υπόλοιπα στοιχεία, αν υπάρχει τέτοιο.
  ///
  /// Στα ελληνικά «παραμονή» σημαίνει «μένω εκεί που είμαι»: ένα τηλέφωνο των
  /// Αδειών δεν μπορεί να «παραμείνει» στην Ψυχιατρική. Όταν τα υπόλοιπα
  /// ανήκουν σε διαφορετικά τμήματα, η καθολική «παραμονή» δεν έχει νόημα και
  /// η θέση της την παίρνει η μεταφορά.
  int? get commonRemainingDepartmentId {
    if (_pending.isEmpty) return null;
    final first = _pending.first.departmentId;
    if (first == null) return null;
    for (final item in _pending) {
      if (item.departmentId != first) return null;
    }
    return first;
  }

  String? get commonRemainingDepartmentName {
    if (commonRemainingDepartmentId == null) return null;
    final name = _pending.first.departmentName?.trim() ?? '';
    return name.isEmpty ? null : name;
  }

  /// Πόσα διαφορετικά τμήματα καλύπτουν τα υπόλοιπα στοιχεία.
  int get remainingDepartmentCount =>
      _pending.map((i) => i.departmentId).whereType<int>().toSet().length;

  AssetDisconnectStandingDecision? get standingDecision => _standingDecision;

  /// Δηλώνει επιπλέον στοιχεία (για ροές που τα ανακαλύπτουν σταδιακά).
  void registerItems(Iterable<AssetDisconnectItem> items) {
    for (final item in items) {
      if (item.value.trim().isEmpty) continue;
      _pending.add(item);
      _totalSteps++;
    }
  }

  /// Καταγράφει ότι ένα στοιχείο απαντήθηκε (με διάλογο ή με καθολική απόφαση).
  void markResolved(AssetDisconnectItem item) {
    final index = _pending.indexWhere(
      (p) => p.kind == item.kind && p.value == item.value,
    );
    if (index >= 0) {
      _pending.removeAt(index);
    } else {
      // Αδήλωτο στοιχείο: μεγαλώνει και το σύνολο, ώστε ο μετρητής να μη
      // δείξει ποτέ «Βήμα 5 από 4».
      _totalSteps++;
    }
    _resolvedSteps++;
  }

  /// Η καθολική απόφαση που ισχύει για αυτό το είδος στοιχείου, αν υπάρχει.
  AssetDisconnectStandingDecision? standingDecisionFor(
    AssetDisconnectItemKind kind,
  ) {
    final decision = _standingDecision;
    if (decision == null) return null;
    return decision.appliesTo(kind) ? decision : null;
  }

  void applyStandingDecision(AssetDisconnectStandingDecision decision) {
    _standingDecision = decision;
  }

  /// Η επιβεβαίωση ακύρωσης παραλείπεται μόνο όταν δεν υπάρχει τίποτα να χαθεί:
  /// ένα μοναδικό στοιχείο, καμία απάντηση δοσμένη, κανένα ευρύτερο πλαίσιο.
  bool get needsCancelConfirmation =>
      (cancelScopeDescription?.trim().isNotEmpty ?? false) ||
      _resolvedSteps >= 1 ||
      remainingSteps >= 2;
}

/// Ένδειξη θέσης στη ροή: «Βήμα 6 από 24», ή «Τμήμα 2 από 3 · Βήμα 3 από 8»
/// όταν η ενέργεια σπάει σε περισσότερες από μία συνεδρίες.
String assetDisconnectStepLabel({
  required int currentStep,
  required int totalSteps,
  String? contextLabel,
}) {
  final step = 'Βήμα $currentStep από $totalSteps';
  final context = contextLabel?.trim() ?? '';
  return context.isEmpty ? step : '$context · $step';
}

/// Πλήθος σε ανθρώπινη μορφή: «12 τηλέφωνα και 6 εξοπλισμοί».
String assetDisconnectCountPhrase({
  required int phoneCount,
  required int equipmentCount,
}) {
  final parts = <String>[];
  if (phoneCount > 0) {
    parts.add(phoneCount == 1 ? '1 τηλέφωνο' : '$phoneCount τηλέφωνα');
  }
  if (equipmentCount > 0) {
    parts.add(
      equipmentCount == 1 ? '1 εξοπλισμός' : '$equipmentCount εξοπλισμοί',
    );
  }
  if (parts.isEmpty) return 'κανένα στοιχείο';
  return parts.join(' και ');
}

/// Ποιανού είναι και από πού: «Καλλιρρόη Βλαχάκη (Ψυχιατρική)».
///
/// Χωρίς κάτοχο (κοινόχρηστο στοιχείο τμήματος) γράφεται «κοινόχρηστο (Τμήμα)».
String assetDisconnectItemOwnerLabel(AssetDisconnectItem item) {
  final owner = item.ownerName?.trim() ?? '';
  final dept = item.departmentName?.trim() ?? '';
  final who = owner.isEmpty ? 'κοινόχρηστο' : owner;
  return dept.isEmpty ? who : '$who ($dept)';
}

/// Οι ιστορικές εγγραφές σε μία φράση: «3 κλήσεις · 1 εκκρεμότητα».
///
/// Κενό όταν δεν υπάρχει ιστορικό — ο κάτοχος δεν μετράει ως «σύνδεση».
String assetDisconnectHistoryLabel(AssetHistoryLinks? links) {
  if (links == null || links.isEmpty) return '';
  final parts = <String>[];
  if (links.calls > 0) {
    parts.add(links.calls == 1 ? '1 κλήση' : '${links.calls} κλήσεις');
  }
  if (links.tasks > 0) {
    parts.add(
      links.tasks == 1 ? '1 εκκρεμότητα' : '${links.tasks} εκκρεμότητες',
    );
  }
  return parts.join(' · ');
}

/// Πλήρης γραμμή στοιχείου για την επιβεβαίωση γρήγορης επιλογής.
String assetDisconnectItemLine(
  AssetDisconnectItem item, {
  AssetHistoryLinks? history,
}) {
  final buf = StringBuffer(
    '${item.value} · ${assetDisconnectItemOwnerLabel(item)}',
  );
  final historyLabel = assetDisconnectHistoryLabel(history);
  if (historyLabel.isNotEmpty) buf.write(' · $historyLabel');
  return buf.toString();
}

/// Τίτλος διαλόγου επιβεβαίωσης γρήγορης επιλογής.
String assetDisconnectBulkTitle({
  required SharedAssetDisconnectChoice choice,
  required int itemCount,
}) {
  final countPart = itemCount == 1 ? '1 στοιχείου' : '$itemCount στοιχείων';
  switch (choice) {
    case SharedAssetDisconnectChoice.delete:
      return 'Διαγραφή $countPart χωρίς άλλη ερώτηση';
    case SharedAssetDisconnectChoice.keepInDepartment:
      return 'Παραμονή $countPart χωρίς άλλη ερώτηση';
    case SharedAssetDisconnectChoice.transfer:
      return 'Μεταφορά $countPart χωρίς άλλη ερώτηση';
  }
}

/// Η πρώτη γραμμή της επιβεβαίωσης: τι ακριβώς πρόκειται να συμβεί.
///
/// Η ονομαστική απαρίθμηση δεν είναι εδώ — κάθε στοιχείο παρουσιάζεται σε δική
/// του γραμμή με τον κάτοχο, το τμήμα και το ιστορικό του.
///
/// [transferDepartmentName] δίνεται μόνο στη μεταφορά, όπου ο στόχος είναι
/// ένας και κοινός. Η «παραμονή» ΔΕΝ ονομάζει ποτέ τμήμα: η απόφαση συνεχίζει
/// και στους επόμενους υπαλλήλους, που ανήκουν σε άλλα τμήματα.
String assetDisconnectBulkPreviewHeadline({
  required SharedAssetDisconnectChoice choice,
  required List<AssetDisconnectItem> items,
  String? transferDepartmentName,
}) {
  final phoneCount = items.where((i) => i.isPhone).length;
  final equipmentCount = items.length - phoneCount;
  final counts = assetDisconnectCountPhrase(
    phoneCount: phoneCount,
    equipmentCount: equipmentCount,
  );

  switch (choice) {
    case SharedAssetDisconnectChoice.delete:
      return 'Θα διαγραφούν $counts:';
    case SharedAssetDisconnectChoice.keepInDepartment:
      return 'Θα παραμείνουν στο τμήμα τους $counts:';
    case SharedAssetDisconnectChoice.transfer:
      final dept = transferDepartmentName?.trim() ?? '';
      return dept.isEmpty
          ? 'Θα μεταφερθούν $counts:'
          : 'Θα μεταφερθούν στο «$dept» $counts:';
  }
}

/// Υπενθύμιση ότι η διαγραφή δεν είναι οριστική.
const String assetDisconnectUndoReminder =
    'Η διαγραφή αναιρείται: μπορείτε να τα επαναφέρετε όλα με το κουμπί '
    '«Αναίρεση» αμέσως μετά.';

/// Επικεφαλίδα της ενότητας ατομικών ενεργειών.
String assetDisconnectSingleActionsHeader({required bool isPhone}) => isPhone
    ? 'Επιλέξτε ενέργεια για αυτό το τηλέφωνο'
    : 'Επιλέξτε ενέργεια για αυτόν τον εξοπλισμό';

/// Επικεφαλίδα της ενότητας καθολικών ενεργειών.
///
/// Στο πρώτο βήμα δεν υπάρχουν «υπόλοιπα» — είναι όλα.
String assetDisconnectQuickActionsHeader({
  required int remainingSteps,
  required bool isAtFirstStep,
}) {
  if (remainingSteps <= 1) return '…ή μία απάντηση για όλα';
  return isAtFirstStep
      ? '…ή μία απάντηση για όλα τα $remainingSteps στοιχεία'
      : '…ή μία απάντηση για τα υπόλοιπα $remainingSteps στοιχεία';
}

/// Μήνυμα επιβεβαίωσης ακύρωσης — τι ακριβώς χάνεται.
String assetDisconnectCancelMessage({
  required int resolvedSteps,
  String? cancelScopeDescription,
}) {
  final scope = cancelScopeDescription?.trim() ?? '';
  final buf = StringBuffer(
    scope.isEmpty ? 'Θα ακυρωθεί η ενέργεια.' : 'Θα ακυρωθεί $scope.',
  );
  if (resolvedSteps == 1) {
    buf.write('\n\nΗ 1 απάντηση που δώσατε θα χαθεί.');
  } else if (resolvedSteps > 1) {
    buf.write('\n\nΟι $resolvedSteps απαντήσεις που δώσατε θα χαθούν.');
  }
  buf.write('\n\nΤίποτα δεν έχει γραφτεί ακόμα στη βάση.');
  return buf.toString();
}

/// Υποδείξεις των κουμπιών διακοπής, όταν υπάρχει δουλειά που κρατιέται.
///
/// Το τι κάνει ένα κουμπί ανήκει στην **υπόδειξή** του, όχι στο σώμα του
/// διαλόγου: μια λίστα επεξηγήσεων μέσα στο κείμενο φούσκωνε τον διάλογο σε
/// όλο το πλάτος της οθόνης και επαναλάμβανε τις ετικέτες.
const String assetDisconnectContinueHint =
    'Επιστροφή στο βήμα που ρωτούσε, για να συνεχίσετε τις απαντήσεις.';

const String assetDisconnectCancelAllHint =
    'Τίποτα δεν γράφεται στη βάση. Όλες οι απαντήσεις που δώσατε πετιούνται.';
