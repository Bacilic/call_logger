/// Πόσο κρατά η δική μας εκτίμηση ότι ένα μοντέλο δεν πάει καλά — και μέσα σε
/// πόσο μετρούν οι διαδοχικές αποτυχίες.
const Duration kAiModelFailureWindow = Duration(minutes: 10);

/// Πόσες **διαδοχικές** προσωρινές αποτυχίες πριν το μοντέλο υποβαθμιστεί.
///
/// Διαδοχικές, όχι σκόρπιες: μία επιτυχία στο ενδιάμεσο μηδενίζει τη σειρά.
/// Αλλιώς ένα μοντέλο που πετυχαίνει τις μισές φορές θα υποβαθμιζόταν παρότι
/// δουλεύει.
const int kAiModelFailuresBeforeDowngrade = 3;

/// Γιατί ένα μοντέλο ΤΝ δεν χρησιμοποιείται αυτή τη στιγμή.
///
/// Η αιτία **φυλάσσεται μαζί με τον χρόνο**, ώστε η επόμενη «Πρόταση ΤΝ» να
/// μπορεί να πει στον χρήστη τι ακριβώς συνέβη — και όχι ένα γενικό «απέτυχε».
enum AiModelDownReason {
  /// 429 — η ποσόστωση εξαντλήθηκε. Κρατά ώρες, όχι λεπτά.
  quotaExhausted,

  /// 404 — το μοντέλο δεν υπάρχει, ή δεν είναι διαθέσιμο με αυτό το κλειδί.
  /// Συνήθως τυπογραφικό στη ρύθμιση: η οθόνη επιτρέπει χειροκίνητο όνομα.
  modelNotFound,

  /// 503, λήξη χρόνου, κενή απάντηση — προσωρινή αδυναμία που περνά.
  unavailable,
}

extension AiModelDownReasonRules on AiModelDownReason {
  /// True όταν η επανάληψη θα βρει το ίδιο, άρα **μία αποτυχία αρκεί**.
  ///
  /// Τρεις προσπάθειες σε μοντέλο που δεν υπάρχει είναι ενάμισι λεπτό
  /// αναμονής για κάτι που δεν πρόκειται να αλλάξει μόνο του.
  bool get isConclusive => this != AiModelDownReason.unavailable;
}

/// Τι ξέρουμε για ένα μοντέλο που δεν πάει καλά.
class AiModelDowntime {
  const AiModelDowntime({
    required this.model,
    required this.until,
    required this.reason,
    required this.blocking,
  });

  final String model;

  /// Ως πότε ισχύει.
  final DateTime until;

  final AiModelDownReason reason;

  /// **True μόνο όταν τον χρόνο τον όρισε ο ίδιος ο διακομιστής** («ξαναδοκίμασε
  /// σε 34 λεπτά»). Τότε το μοντέλο **παραλείπεται** εντελώς: μας ζήτησαν ρητά
  /// να μην το χτυπήσουμε.
  ///
  /// False όταν είναι δική μας εκτίμηση από την εμπειρία. Τότε το μοντέλο απλώς
  /// **υποβαθμίζεται στη σειρά** — μια εικασία μας δεν επιτρέπεται να
  /// αποκλείσει το μόνο μοντέλο που ίσως δουλεύει.
  final bool blocking;

  AiModelDowntime copyWith({DateTime? until, bool? blocking}) =>
      AiModelDowntime(
        model: model,
        until: until ?? this.until,
        reason: reason,
        blocking: blocking ?? this.blocking,
      );
}

/// Η υγεία των μοντέλων ΤΝ όπως τη γνωρίζει **αυτός ο υπολογιστής**.
///
/// Δύο πηγές γνώσης, με διαφορετικό βάρος:
/// 1. **Ο διακομιστής** — όταν απαντά «ξαναδοκίμασε σε X», τον πιστεύουμε και
///    παραλείπουμε το μοντέλο ως τότε.
/// 2. **Η εμπειρία μας** — διαδοχικές αποτυχίες, ή ένα σφάλμα που δεν πρόκειται
///    να αλλάξει (404/429 χωρίς χρόνο). Τότε το μοντέλο υποβαθμίζεται στη σειρά
///    δοκιμών, δεν αποκλείεται.
///
/// **Το κλειδί είναι το όνομα του μοντέλου, όχι ο ρόλος του.** Αυτό λύνει μόνο
/// του τρία πράγματα: η αλλαγή ρύθμισης ξεκινά καθαρή (άλλο όνομα, καμία
/// ιστορία), η επιστροφή στο παλιό θυμάται σωστά, και ένα μοντέλο που σήμερα
/// είναι εφεδρικό και αύριο κύριο κουβαλά τη δική του ιστορία.
class AiModelCooldownRegistry {
  AiModelCooldownRegistry({DateTime Function()? now, this.onChanged})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Ειδοποιείται σε κάθε μεταβολή, ώστε η γνώση να επιβιώνει της επανεκκίνησης.
  final void Function()? onChanged;

  final Map<String, AiModelDowntime> _downByModel = {};
  final Map<String, ({int count, DateTime windowUntil})> _streakByModel = {};

  /// Ο διακομιστής ζήτησε ρητά να μην ξαναχτυπήσουμε ως τότε.
  void markUnavailable(
    String model,
    Duration retryAfter, {
    AiModelDownReason reason = AiModelDownReason.unavailable,
  }) {
    final id = model.trim();
    if (id.isEmpty || retryAfter <= Duration.zero) return;
    _extend(
      AiModelDowntime(
        model: id,
        until: _now().add(retryAfter),
        reason: reason,
        blocking: true,
      ),
    );
  }

  /// Μια αποτυχία του μοντέλου, όπως τη ζήσαμε.
  ///
  /// Το [serverRetryAfter] δίνεται μόνο όταν ο διακομιστής όρισε ρητά χρόνο.
  void recordFailure(
    String model, {
    required AiModelDownReason reason,
    Duration? serverRetryAfter,
  }) {
    final id = model.trim();
    if (id.isEmpty) return;

    if (serverRetryAfter != null && serverRetryAfter > Duration.zero) {
      _streakByModel.remove(id);
      _extend(
        AiModelDowntime(
          model: id,
          until: _now().add(serverRetryAfter),
          reason: reason,
          blocking: true,
        ),
      );
      return;
    }

    if (reason.isConclusive) {
      _streakByModel.remove(id);
      _extend(
        AiModelDowntime(
          model: id,
          until: _now().add(kAiModelFailureWindow),
          reason: reason,
          blocking: false,
        ),
      );
      return;
    }

    final now = _now();
    final streak = _streakByModel[id];
    final continuing = streak != null && now.isBefore(streak.windowUntil);
    final count = continuing ? streak.count + 1 : 1;

    if (count >= kAiModelFailuresBeforeDowngrade) {
      _streakByModel.remove(id);
      _extend(
        AiModelDowntime(
          model: id,
          until: now.add(kAiModelFailureWindow),
          reason: reason,
          blocking: false,
        ),
      );
      return;
    }

    _streakByModel[id] = (
      count: count,
      windowUntil: now.add(kAiModelFailureWindow),
    );
    onChanged?.call();
  }

  /// Το μοντέλο απάντησε κανονικά — ό,τι ξέραμε εναντίον του παύει να ισχύει.
  void recordSuccess(String model) {
    final id = model.trim();
    if (id.isEmpty) return;
    final hadDowntime = _downByModel.remove(id) != null;
    final hadStreak = _streakByModel.remove(id) != null;
    if (hadDowntime || hadStreak) onChanged?.call();
  }

  /// Ξεχνά ό,τι ξέρουμε για το μοντέλο — «δοκίμασέ το τώρα», με το χέρι.
  void clear(String model) => recordSuccess(model);

  /// Τι ξέρουμε εναντίον του μοντέλου· `null` όταν είναι υγιές ή έληξε.
  AiModelDowntime? downtime(String model) {
    final id = model.trim();
    if (id.isEmpty) return null;
    final entry = _downByModel[id];
    if (entry == null) return null;
    if (!_now().isBefore(entry.until)) {
      _downByModel.remove(id);
      onChanged?.call();
      return null;
    }
    return entry;
  }

  /// True όταν ο διακομιστής ζήτησε ρητά να μην το χτυπήσουμε τώρα.
  bool isInCooldown(String model) => downtime(model)?.blocking == true;

  /// True όταν η **δική μας** εμπειρία λέει να το αφήσουμε για μετά.
  bool isDemoted(String model) => downtime(model)?.blocking == false;

  DateTime? availableAt(String model) {
    final entry = downtime(model);
    return entry != null && entry.blocking ? entry.until : null;
  }

  ({String model, DateTime availableAt})? earliestAvailable(
    Iterable<String> models,
  ) {
    ({String model, DateTime availableAt})? best;
    for (final raw in models) {
      final at = availableAt(raw);
      if (at == null) continue;
      if (best == null || at.isBefore(best.availableAt)) {
        best = (model: raw.trim(), availableAt: at);
      }
    }
    return best;
  }

  /// Η σειρά δοκιμής των μοντέλων: πρώτα όσα δεν ξέρουμε προβληματικά.
  ///
  /// **Η σχετική σειρά διατηρείται** μέσα σε κάθε ομάδα, ώστε το κύριο να μένει
  /// πριν από το εφεδρικό όταν είναι και τα δύο υγιή — ή και τα δύο πεσμένα.
  /// Στη δεύτερη περίπτωση επιστρέφουμε φυσικά στη φυσιολογική σειρά: όταν δεν
  /// υπάρχει καλύτερη επιλογή, δεν έχει νόημα να μένουμε κολλημένοι στο
  /// εφεδρικό.
  List<String> orderedForAttempt(Iterable<String> models) {
    final healthy = <String>[];
    final demoted = <String>[];
    for (final raw in models) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      (downtime(id) == null ? healthy : demoted).add(id);
    }
    return [...healthy, ...demoted];
  }

  /// Ό,τι ισχύει αυτή τη στιγμή — για αποθήκευση στον υπολογιστή.
  List<AiModelDowntime> get activeDowntimes {
    final now = _now();
    final expired = <String>[];
    final active = <AiModelDowntime>[];
    for (final entry in _downByModel.entries) {
      if (now.isBefore(entry.value.until)) {
        active.add(entry.value);
      } else {
        expired.add(entry.key);
      }
    }
    _downByModel.removeWhere((key, _) => expired.contains(key));
    return active;
  }

  /// Επαναφορά από τον δίσκο. Ό,τι έχει ήδη λήξει αγνοείται.
  ///
  /// Δεν ειδοποιεί: η επαναφορά δεν είναι νέα γνώση, είναι η ίδια γνώση που
  /// μόλις διαβάστηκε.
  void restore(Iterable<AiModelDowntime> entries) {
    final now = _now();
    for (final entry in entries) {
      final id = entry.model.trim();
      if (id.isEmpty || !now.isBefore(entry.until)) continue;
      _downByModel[id] = entry;
    }
  }

  void _extend(AiModelDowntime next) {
    final existing = _downByModel[next.model];
    if (existing != null && !next.until.isAfter(existing.until)) {
      // Ο μακρύτερος χρόνος κερδίζει: ένα «σε 34 λεπτά» από τον διακομιστή δεν
      // επιτρέπεται να συντομευτεί από τη δική μας δεκάλεπτη εκτίμηση.
      if (existing.blocking || !next.blocking) return;
      _downByModel[next.model] = existing.copyWith(blocking: true);
      onChanged?.call();
      return;
    }
    _downByModel[next.model] = next;
    onChanged?.call();
  }
}
