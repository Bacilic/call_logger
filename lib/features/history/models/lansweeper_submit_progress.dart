/// Η πορεία μιας αποστολής ticket στο Lansweeper, βήμα προς βήμα.
///
/// Υπάρχει για έναν λόγο: η αποστολή κρατά δεκαπέντε και πλέον δευτερόλεπτα
/// και όσο έτρεχε δεν φαινόταν τίποτα — ένα γκρίζο κουμπί δεν ξεχωρίζει από
/// κολλημένη εφαρμογή. Εδώ ζει η απάντηση στο «τι κάνεις τώρα και πόση ώρα».
///
/// Είναι καθαρά δεδομένα: κανένα widget, καμία υπηρεσία. Ποιος τη γεμίζει
/// (ο συντονιστής της αποστολής) και ποιος τη ζωγραφίζει (η αναφορά) μένουν
/// έξω από εδώ.
library;

/// Σε ποια φάση βρίσκεται ένα μεμονωμένο βήμα.
enum LansweeperSubmitStepStatus { pending, running, done, failed }

/// Πώς τελείωσε — ή αν δεν έχει καν ξεκινήσει.
enum LansweeperSubmitOutcome { idle, running, success, failure }

/// Τα κλειδιά των βημάτων. Ίδια στην υπηρεσία που τα εκτελεί και στην οθόνη
/// που τα δείχνει· η μετάφραση σε ελληνικά γίνεται σε ένα σημείο, παρακάτω.
class LansweeperSubmitStepKeys {
  const LansweeperSubmitStepKeys._();

  /// Ελέγχεται στο Lansweeper αν ο αιτών υπάρχει.
  static const String requester = 'requester';

  /// Δημιουργείται το αίτημα (ή αναγνωρίζεται το υπάρχον).
  static const String ticket = 'ticket';

  /// Συνδέεται ο εξοπλισμός της κλήσης.
  static const String asset = 'asset';

  /// Γράφεται η λύση ως σημείωση.
  static const String note = 'note';

  /// Μπαίνει η τελική κατάσταση του αιτήματος.
  static const String state = 'state';

  /// Γράφονται τα αποτελέσματα στη βάση — το βήμα που δεν είναι HTTP.
  static const String save = 'save';
}

/// Η ελληνική ετικέτα ενός βήματος, όπως τη διαβάζει ο χρήστης.
///
/// Το [creating] ξεχωρίζει τη δημιουργία νέου αιτήματος από την ενημέρωση
/// αιτήματος που υπάρχει ήδη: είναι η ίδια κλήση API, αλλά για τον χρήστη δεν
/// είναι η ίδια πράξη.
String lansweeperSubmitStepLabel(String key, {bool creating = true}) {
  return switch (key) {
    LansweeperSubmitStepKeys.requester => 'Επαλήθευση αιτούντα',
    LansweeperSubmitStepKeys.ticket =>
      creating ? 'Δημιουργία αιτήματος' : 'Ενημέρωση αιτήματος',
    LansweeperSubmitStepKeys.asset => 'Σύνδεση εξοπλισμού',
    LansweeperSubmitStepKeys.note => 'Καταγραφή λύσης',
    LansweeperSubmitStepKeys.state => 'Ενημέρωση κατάστασης',
    LansweeperSubmitStepKeys.save => 'Αποθήκευση στη βάση',
    _ => key,
  };
}

/// Ο χρόνος όπως γράφεται στην οθόνη: δευτερόλεπτα με χιλιοστά.
///
/// Τα χιλιοστά δεν είναι ακρίβεια για την ακρίβεια — είναι το σημάδι ζωής.
/// Ένας αριθμός που αλλάζει δεκάδες φορές το δευτερόλεπτο λέει «δουλεύω» πιο
/// καθαρά από οποιοδήποτε κείμενο.
String formatLansweeperElapsed(int milliseconds) {
  final safe = milliseconds < 0 ? 0 : milliseconds;
  return '${(safe / 1000).toStringAsFixed(3)} δλ';
}

/// Ένα βήμα της αποστολής.
class LansweeperSubmitStep {
  const LansweeperSubmitStep({
    required this.key,
    required this.label,
    this.status = LansweeperSubmitStepStatus.pending,
    this.elapsedMilliseconds,
  });

  final String key;
  final String label;
  final LansweeperSubmitStepStatus status;

  /// Πόσο κράτησε· `null` όσο δεν έχει τελειώσει.
  final int? elapsedMilliseconds;

  bool get isFinished =>
      status == LansweeperSubmitStepStatus.done ||
      status == LansweeperSubmitStepStatus.failed;

  LansweeperSubmitStep copyWith({
    LansweeperSubmitStepStatus? status,
    int? elapsedMilliseconds,
  }) {
    return LansweeperSubmitStep(
      key: key,
      label: label,
      status: status ?? this.status,
      elapsedMilliseconds: elapsedMilliseconds ?? this.elapsedMilliseconds,
    );
  }
}

/// Η συνολική εικόνα της αποστολής σε μια δεδομένη στιγμή.
class LansweeperSubmitProgress {
  const LansweeperSubmitProgress({
    this.steps = const <LansweeperSubmitStep>[],
    this.outcome = LansweeperSubmitOutcome.idle,
    this.summary,
    this.totalMilliseconds,
    this.callIds = const <int>[],
  });

  static const LansweeperSubmitProgress idle = LansweeperSubmitProgress();

  final List<LansweeperSubmitStep> steps;
  final LansweeperSubmitOutcome outcome;

  /// Ποιων κλήσεων είναι αυτή η αποστολή.
  ///
  /// Χωρίς αυτό, το «Καταχωρήθηκε · αίτημα 17789» έμενε στην οθόνη και όταν ο
  /// χρήστης διάλεγε την ΕΠΟΜΕΝΗ κλήση — η οποία έδειχνε έτσι σαν να έχει
  /// σταλεί ήδη. Το αποτέλεσμα ανήκει σε συγκεκριμένες κλήσεις και δεν
  /// επιτρέπεται να συνοδεύει καμία άλλη.
  final List<int> callIds;

  /// Η μία γραμμή που μένει στην οθόνη όταν τελειώσει: «Καταχωρήθηκε · αίτημα
  /// 17188» ή η αιτία της αποτυχίας.
  final String? summary;

  /// Ο συνολικός χρόνος· `null` όσο τρέχει.
  final int? totalMilliseconds;

  bool get isRunning => outcome == LansweeperSubmitOutcome.running;
  bool get isIdle => outcome == LansweeperSubmitOutcome.idle;

  /// Αφορά η εικόνα αυτή την [callId];
  ///
  /// Χωρίς επιλεγμένη κλήση (`null`) η απάντηση είναι ναι: αμέσως μετά από
  /// επιτυχή καταχώρηση οι κλήσεις αποεπιλέγονται μόνες τους, και το
  /// αποτέλεσμα πρέπει να προλάβει να διαβαστεί.
  bool concernsCall(int? callId) {
    if (callId == null || callIds.isEmpty) return true;
    return callIds.contains(callId);
  }

  /// Το βήμα που εκτελείται τώρα· `null` όταν δεν τρέχει κανένα.
  LansweeperSubmitStep? get currentStep {
    for (final step in steps) {
      if (step.status == LansweeperSubmitStepStatus.running) return step;
    }
    return null;
  }

  /// Η σειρά του τρέχοντος βήματος, από το 1 — για το «βήμα 2 από 6».
  int get currentStepNumber {
    for (var i = 0; i < steps.length; i++) {
      if (steps[i].status == LansweeperSubmitStepStatus.running) return i + 1;
    }
    return 0;
  }

  int get totalSteps => steps.length;

  LansweeperSubmitProgress copyWith({
    List<LansweeperSubmitStep>? steps,
    LansweeperSubmitOutcome? outcome,
    String? summary,
    int? totalMilliseconds,
    List<int>? callIds,
  }) {
    return LansweeperSubmitProgress(
      steps: steps ?? this.steps,
      outcome: outcome ?? this.outcome,
      summary: summary ?? this.summary,
      totalMilliseconds: totalMilliseconds ?? this.totalMilliseconds,
      callIds: callIds ?? this.callIds,
    );
  }

  /// Ξεκινά το βήμα [key]: κλείνει ό,τι έτρεχε και το σημειώνει ολοκληρωμένο.
  ///
  /// Το [elapsedMilliseconds] είναι ο χρόνος **από την αρχή της αποστολής**·
  /// η αφαίρεση για τον χρόνο του κάθε βήματος γίνεται εδώ, ώστε ο καλών να
  /// κρατά ένα μόνο ρολόι.
  LansweeperSubmitProgress startStep(String key, int elapsedMilliseconds) {
    final next = <LansweeperSubmitStep>[];
    var consumed = 0;
    var found = false;
    for (final step in steps) {
      if (step.status == LansweeperSubmitStepStatus.running) {
        next.add(
          step.copyWith(
            status: LansweeperSubmitStepStatus.done,
            elapsedMilliseconds: elapsedMilliseconds - consumed,
          ),
        );
        consumed = elapsedMilliseconds;
        continue;
      }
      if (step.isFinished) {
        consumed += step.elapsedMilliseconds ?? 0;
      }
      if (step.key == key) {
        found = true;
        next.add(step.copyWith(status: LansweeperSubmitStepStatus.running));
        continue;
      }
      next.add(step);
    }
    // Βήμα εκτός πλάνου: η υπηρεσία έκανε κάτι που το πλάνο δεν πρόβλεψε.
    // Προστίθεται αντί να αγνοηθεί — η οθόνη οφείλει να λέει την αλήθεια,
    // ακόμη κι όταν οι δυο πλευρές αποκλίνουν.
    if (!found) {
      next.add(
        LansweeperSubmitStep(
          key: key,
          label: lansweeperSubmitStepLabel(key),
          status: LansweeperSubmitStepStatus.running,
        ),
      );
    }
    return copyWith(steps: next);
  }

  /// Κλείνει την πορεία. Το βήμα που έτρεχε παίρνει το αποτέλεσμα [success].
  LansweeperSubmitProgress finish({
    required bool success,
    required int totalMilliseconds,
    String? summary,
  }) {
    var consumed = 0;
    final next = <LansweeperSubmitStep>[];
    for (final step in steps) {
      if (step.isFinished) {
        consumed += step.elapsedMilliseconds ?? 0;
        next.add(step);
        continue;
      }
      if (step.status == LansweeperSubmitStepStatus.running) {
        next.add(
          step.copyWith(
            status: success
                ? LansweeperSubmitStepStatus.done
                : LansweeperSubmitStepStatus.failed,
            elapsedMilliseconds: totalMilliseconds - consumed,
          ),
        );
        continue;
      }
      next.add(step);
    }
    return LansweeperSubmitProgress(
      steps: next,
      outcome: success
          ? LansweeperSubmitOutcome.success
          : LansweeperSubmitOutcome.failure,
      summary: summary,
      totalMilliseconds: totalMilliseconds,
      callIds: callIds,
    );
  }
}
