import 'dart:async';

/// Περιοδικός φρουρός: μαθαίνει ότι **άλλο μηχάνημα** έγραψε στην κοινόχρηστη
/// βάση, και ζητά ανανέωση των οθονών.
///
/// Ο φρουρός **δεν ξέρει** πώς διαβάζεται ο μετρητής ούτε τι σημαίνει
/// «ανανέωση» — παίρνει και τα δύο από έξω. Έτσι ελέγχεται χωρίς βάση, χωρίς
/// αρχεία και χωρίς δέντρο widget: του δίνεις μια ψεύτικη ακολουθία αριθμών και
/// μετράς πότε φώναξε.
///
/// Πέντε κανόνες που κρατούν την κοινόχρηστη λειτουργία ήσυχη:
///
/// 1. **Η πρώτη ανάγνωση δεν είναι αλλαγή.** Ορίζει την αφετηρία· χωρίς αυτό
///    κάθε εκκίνηση θα ξεκινούσε με μια περιττή ανανέωση.
/// 2. **Ποτέ δύο έλεγχοι μαζί.** Σε αργό δικτυακό φάκελο ένας έλεγχος μπορεί να
///    διαρκέσει περισσότερο από το διάστημα· ο επόμενος παραλείπεται αντί να
///    στοιβαχτεί.
/// 3. **Η άγνοια δεν είναι αλλαγή.** `null` μετρητής (κλειστή σύνδεση, σφάλμα
///    ανάγνωσης) αφήνει την αφετηρία ανέπαφη και δεν πυροδοτεί τίποτα.
/// 4. **Ποτέ ανανέωση κάτω από τα δάχτυλα του χρήστη.** Όσο το [isBusy] λέει
///    «δουλεύει», η αλλαγή **κρατιέται** και εκτελείται μόλις ελευθερωθεί — δεν
///    χάνεται, αλλά ούτε τραβά τη λίστα ενώ κάποιος τη διαβάζει.
/// 5. **Η αποτυχία είναι σιωπή.** Ό,τι πετάξει η ανανέωση αγνοείται — ένας
///    φρουρός που κρασάρει την εφαρμογή είναι χειρότερος από κανέναν φρουρό.
class SharedDatabaseChangeWatcher {
  SharedDatabaseChangeWatcher({
    required this.readVersion,
    required this.onChanged,
    this.isBusy,
    this.interval = const Duration(seconds: 12),
  });

  /// Διαβάζει τον μετρητή αλλαγών. `null` σημαίνει «δεν ξέρω».
  final Future<int?> Function() readVersion;

  /// Καλείται όταν ο μετρητής δείξει ξένη εγγραφή.
  final Future<void> Function() onChanged;

  /// «Δουλεύει τώρα ο χρήστης;» — ανοιχτός διάλογος, φόρμα υπό συμπλήρωση.
  /// Χωρίς αυτό ο φρουρός θεωρεί ότι η οθόνη είναι ελεύθερη.
  final bool Function()? isBusy;

  /// Πόσο συχνά ρωτάει. Το ερώτημα δεν διαβάζει δεδομένα, αλλά ταξιδεύει στο
  /// δίκτυο — αραιό αρκετά ώστε να μη βαραίνει, πυκνό αρκετά ώστε η εικόνα να
  /// μη γερνά αισθητά.
  final Duration interval;

  Timer? _timer;
  bool _checking = false;
  int? _lastSeenVersion;
  bool _pendingRefresh = false;

  bool get isRunning => _timer != null;

  /// True όταν εντοπίστηκε αλλαγή που περιμένει να ελευθερωθεί η οθόνη.
  bool get hasPendingRefresh => _pendingRefresh;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(checkNow()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
  }

  /// Ένας έλεγχος τώρα, εκτός σειράς.
  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    try {
      final version = await readVersion();
      if (version != null) {
        final baseline = _lastSeenVersion;
        _lastSeenVersion = version;
        if (baseline != null && baseline != version) _pendingRefresh = true;
      }
      await _flushIfIdle();
    } catch (_) {
      // Σιωπή: ο φρουρός δεν ρίχνει ποτέ την εφαρμογή.
    } finally {
      _checking = false;
    }
  }

  /// Εκτελεί μια κρατημένη ανανέωση τώρα, αν η οθόνη είναι ελεύθερη.
  ///
  /// Καλείται και από έξω — π.χ. μόλις κλείσει ένας διάλογος — ώστε η αναμονή
  /// να τελειώνει με το που ελευθερώνεται ο χρήστης και όχι στον επόμενο κύκλο.
  Future<void> flushPending() => _flushIfIdle();

  Future<void> _flushIfIdle() async {
    if (!_pendingRefresh) return;
    if (isBusy?.call() ?? false) return;
    _pendingRefresh = false;
    try {
      await onChanged();
    } catch (_) {
      // Η αποτυχία ανανέωσης δεν ξαναζητείται σε βρόχο: ο επόμενος κύκλος θα
      // δει ούτως ή άλλως τον ίδιο μετρητή αν κάτι άλλαξε ξανά.
    }
  }
}
