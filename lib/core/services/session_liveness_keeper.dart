import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../database/database_reachability.dart';
import 'crash_log_service.dart';
import 'current_operator.dart';
import 'database_contact.dart';
import 'log_file_names.dart';
import 'session_liveness_mark.dart';
import 'station_name.dart';
import 'station_shutdown_request.dart';

/// Το ίχνος «τρέχω τώρα» αυτής της εκτέλεσης και ο παλμός του λεπτού.
///
/// Συνεργάτης του [CrashLogService] (Σύνθεση): ο φάκελος, ο φρουρός του δίσκου
/// και η καταγραφή ανήκουν σε εκείνον, που μένει ο **μοναδικός κάτοχος** του
/// φακέλου. Εδώ ζει μόνο ό,τι αφορά το ίχνος: η αναφορά της εκτέλεσης που
/// χάθηκε, η ανανέωσή του, το σβήσιμό του στο κλείσιμο, και ο έλεγχος
/// αιτημάτων κλεισίματος που μοιράζεται τη στιγμή του παλμού.
class SessionLivenessKeeper {
  SessionLivenessKeeper(this.host);

  final CrashLogService host;

  /// Το ίχνος αυτής της εκτέλεσης, όπως γράφτηκε τελευταία φορά.
  SessionLivenessMark? _currentMark;
  Timer? _livenessTimer;

  /// Αναφέρει την εκτέλεση που χάθηκε, αν χάθηκε, και αφήνει το ίχνος της νέας.
  ///
  /// Το ίχνος που βρίσκεται εδώ είναι **μόνο** δικό μας: το όνομα του αρχείου
  /// φέρει τον σταθμό. Ίχνη άλλων σταθμών δεν διαβάζονται και δεν σβήνονται —
  /// ανήκουν σε εκτελέσεις που ίσως τρέχουν αυτή τη στιγμή.
  Future<void> reportAndReplace(Duration timeout) async {
    final lock = _sessionLockFile();
    if (await lock.exists().timeout(timeout)) {
      final previous = SessionLivenessMark.decode(
        await lock.readAsString().timeout(timeout),
      );
      // Ίχνος που δεν διαβάζεται (αλλοιωμένο, ή γραμμένο από έκδοση που δεν
      // κρατούσε τίποτα) εξακολουθεί να είναι είδηση: κάτι χάθηκε. Λέμε ό,τι
      // ξέρουμε, χωρίς να εφευρίσκουμε λεπτομέρειες — εκτός αν η ίδια εκείνη
      // εκτέλεση άφησε τοπικά ότι έκλεισε κανονικά, με σβηστό διακομιστή.
      final closedCleanly =
          await host.cleanExitNote?.consumeMatches(_runSlug, previous) ?? false;
      if (!closedCleanly) await host.recordLostRun(previous);
    } else {
      // Σημείωμα χωρίς ίχνος: ο φάκελος γύρισε και το ίχνος σβήστηκε αλλιώς.
      // Φεύγει, ώστε να μη σκεπάσει ποτέ μελλοντική κατάρρευση.
      await host.cleanExitNote?.consumeMatches(_runSlug, null);
    }
    await _retireMarkFromPreviousNamingScheme(timeout);
    _currentMark = SessionLivenessMark(
      station: StationName.current,
      version: host.appVersion,
      startedAt: host.clock(),
      lastSeen: host.clock(),
      database: host.databaseFileName,
      instance: host.instanceId.isEmpty ? null : host.instanceId,
      // Το ίχνος δηλώνει ό,τι **ισχύει**, όχι ό,τι υπόσχεται η έκδοση: όσο δεν
      // έχει δοθεί χειριστής, κανείς δεν θα δει σημείωμα, και ο αιτών πρέπει να
      // το ξέρει αντί να μετρά αντίστροφα στο κενό.
      listensForShutdownRequests: onShutdownRequested != null,
    );
    await lock
        .writeAsString(_currentMark!.encode(), flush: true)
        .timeout(timeout);
  }

  /// Μαζεύει το ίχνος που άφησε αυτό το αντίγραφο **πριν** μπει η εκτέλεση
  /// στο όνομα του αρχείου.
  ///
  /// Χωρίς αυτό το `session_<σταθμός>.lock` της προηγούμενης έκδοσης δεν θα
  /// ανοιγόταν ποτέ ξανά: θα έμενε για πάντα στον κοινόχρηστο φάκελο, και για
  /// τρία λεπτά μετά από κάθε εκκίνηση θα περνούσε για ζωντανός συνάδελφος.
  ///
  /// Ο έλεγχος του σταθμού είναι απαραίτητος: το ίδιο αρχείο σε σταθμό που
  /// τρέχει ακόμη παλιά εφαρμογή είναι **ζωντανό** ίχνος, και δεν το αγγίζουμε.
  Future<void> _retireMarkFromPreviousNamingScheme(Duration timeout) async {
    if (host.instanceId.isEmpty) return;
    final legacy = File(
      p.join(
        host.logsDirectory,
        LogFileNames.sessionLockFileNameFor(StationName.fileSafe),
      ),
    );
    try {
      if (!await legacy.exists().timeout(timeout)) return;
      final previous = SessionLivenessMark.decode(
        await legacy.readAsString().timeout(timeout),
      );
      // Ίχνος με δηλωμένη εκτέλεση δεν ανήκει στην παλιά ονοματοδοσία — κάποιος
      // άλλος το έγραψε εκεί, και δεν είναι δικό μας να το κρίνουμε.
      if (previous?.instance != null) return;
      await host.recordLostRun(previous);
      await legacy.delete().timeout(timeout);
    } catch (_) {
      // Η εκκαθάριση είναι ευγένεια προς τον φάκελο, όχι προϋπόθεση εκκίνησης.
    }
  }

  /// Ξεκινά το περιοδικό σημάδι ζωής.
  ///
  /// **Ρητό, όχι αυτόματο στο στήσιμο:** τα τεστ στήνουν την υπηρεσία
  /// συνεχώς, και ένας χρονιστής που ξεκινά μόνος του θα κρεμούσε ελέγχους με
  /// πλαστό ρολόι ή θα διέρρεε πέρα από το τέλος τους. Στην εφαρμογή καλείται
  /// μία φορά, αμέσως μετά το άνοιγμα του ημερολογίου.
  ///
  /// **Ξεκινά και με σιωπηλό φάκελο.** Όσο η σιωπή κρατά από την εκκίνηση, ο
  /// παλμός δεν κάνει τίποτα ([pulse]). Η εκκίνηση όμως συχνά καταλήγει σε
  /// άλλη βάση που απαντά ([CrashLogService.retargetTo]), και χωρίς παλμό η
  /// εφαρμογή θα έμενε αόρατη στους συναδέλφους για όλη τη συνεδρία.
  void start() {
    stop();
    _livenessTimer = Timer.periodic(
      CrashLogService.livenessInterval,
      (_) => unawaited(pulse()),
    );
  }

  void stop() {
    _livenessTimer?.cancel();
    _livenessTimer = null;
  }

  bool get isRunning => _livenessTimer != null;

  /// Τι κάνει η εφαρμογή όταν κάποιος της ζητά να κλείσει.
  ///
  /// Δίνεται από έξω ώστε το ημερολόγιο να μη μάθει ποτέ τι σημαίνει «κλείσιμο
  /// εφαρμογής»: η δουλειά του είναι τα αρχεία, και μια υπηρεσία που ξέρει και
  /// τα δύο θα ήταν αδύνατο να ελεγχθεί χωρίς δέντρο widget.
  ///
  /// `null` όσο κανείς δεν ακούει — και τότε το ίχνος **δεν** δηλώνει ότι
  /// ακούει, ώστε ο αιτών να μην περιμένει απάντηση που δεν θα έρθει.
  Future<void> Function(StationShutdownRequest request)?
  get onShutdownRequested => _onShutdownRequested;

  Future<void> Function(StationShutdownRequest request)? _onShutdownRequested;

  /// **Η ανάθεση ξαναγράφει το ίχνος αμέσως.**
  ///
  /// Το ίχνος γεννιέται στην εκκίνηση, πολύ πριν στηθεί το κέλυφος που ακούει.
  /// Χωρίς αυτή την ενημέρωση θα έμενε να δηλώνει «δεν ακούω» ως τον πρώτο
  /// παλμό — ένα ολόκληρο λεπτό κατά το οποίο ο συνάδελφος θα διάβαζε ότι
  /// χρειάζεται τηλέφωνο, ενώ η εφαρμογή ήδη άκουγε.
  set onShutdownRequested(
    Future<void> Function(StationShutdownRequest request)? handler,
  ) {
    final changed = (_onShutdownRequested != null) != (handler != null);
    _onShutdownRequested = handler;
    if (!changed) return;
    final mark = _currentMark;
    if (mark == null) return;
    _currentMark = mark.copyWith(listensForShutdownRequests: handler != null);
    unawaited(_markAlive());
  }

  /// **Ένας παλμός, δύο πράξεις.** Το ίχνος γράφεται και, στην ίδια στιγμή,
  /// ρωτιέται ο φάκελος αν κάποιος ζήτησε κλείσιμο.
  ///
  /// Η κοινή στιγμή δεν είναι οικονομία, είναι **προϋπόθεση ακρίβειας**: ο
  /// αιτών προβλέπει πότε θα δούμε το σημείωμά του προσθέτοντας ένα λεπτό στο
  /// «τελευταίο σημάδι ζωής» που διαβάζει. Αν ο έλεγχος είχε δικό του χρονιστή,
  /// η φάση του θα διέφερε και η πρόβλεψη θα ήταν εικασία.
  ///
  /// **Όσο το ημερολόγιο σιωπά, ο παλμός ρωτά αν ο φάκελος γύρισε** — με την
  /// ίδια εγγραφή του ίχνους, που αν πετύχει ξαναζωντανεύει την καταγραφή.
  Future<void> pulse() async {
    if (host.isDiskAvailable) {
      await _markAlive();
    } else if (!await _tryResume()) {
      return;
    }
    if (onShutdownRequested == null) return;
    await _checkForShutdownRequest();
  }

  /// Το ίχνος ανανεωμένο τώρα — μαζί με το ποιος είναι συνδεδεμένος και πότε
  /// μίλησε τελευταία η εφαρμογή με τη βάση. Ένα σημείο, ώστε κανένα γράψιμο
  /// του ίχνους να μην ξεχνά τα δύο στοιχεία που κρίνουν το «κολλημένο».
  SessionLivenessMark? _freshMark() => _currentMark?.seenAt(
    host.clock(),
    operatorName: CurrentOperator.active?.displayName,
    lastDatabaseContact: DatabaseContact.last,
    databaseConnectionDead:
        DatabaseReachabilitySignal.state ==
        DatabaseReachability.staleConnection,
  );

  Future<bool> _tryResume() async {
    final mark = _freshMark();
    if (mark == null) return false;
    final resumed = await host.tryResumeDisk(
      _sessionLockFile().path,
      mark.encode(),
    );
    if (resumed) _currentMark = mark;
    return resumed;
  }

  /// Ένα «υπάρχεις;» σε γνωστό όνομα αρχείου — ποτέ σάρωση φακέλου.
  ///
  /// Ποτέ δύο έλεγχοι μαζί: σε αργό δικτυακό φάκελο ένας έλεγχος μπορεί να
  /// κρατήσει περισσότερο από το διάστημα, και ο επόμενος παραλείπεται αντί να
  /// στοιβαχτεί.
  bool _checkingShutdownRequest = false;

  Future<void> _checkForShutdownRequest() async {
    if (_checkingShutdownRequest || !host.isDiskAvailable) return;
    _checkingShutdownRequest = true;
    try {
      final request = await readShutdownRequestForMe(
        logsDirectory: host.logsDirectory,
        myStation: StationName.fileSafe,
        myInstance: host.instanceId,
        myDatabase: host.databaseFileName,
        now: host.clock(),
        timeout: CrashLogService.diskProbeTimeout,
      );
      if (request == null) return;
      // **Καταναλώνεται μόλις διαβαστεί, πριν γίνει οτιδήποτε μαζί του.**
      // Το σημείωμα είναι ερέθισμα μιας χρήσης. Αν το αφήναμε στον δίσκο ώσπου
      // να τιμηθεί, μια κατάρρευση ή ένα βίαιο κλείσιμο στη μέση του διαλόγου
      // θα το άφηνε εκεί — και η επόμενη εκκίνηση θα το ξανάβρισκε και θα
      // ξανάκλεινε αμέσως, εγκλωβίζοντας τον συνάδελφο έξω από τη δουλειά του.
      await clearShutdownRequestForMe(
        logsDirectory: host.logsDirectory,
        myStation: StationName.fileSafe,
        myInstance: host.instanceId,
        timeout: CrashLogService.diskProbeTimeout,
      );
      await onShutdownRequested?.call(request);
    } catch (e, stack) {
      // Ο φρουρός δεν ρίχνει ποτέ την εφαρμογή: μια αποτυχία εδώ σημαίνει απλώς
      // ότι το αίτημα θα ξαναβρεθεί στον επόμενο παλμό.
      host.logError(e, stack, fatal: false);
    } finally {
      _checkingShutdownRequest = false;
    }
  }

  /// Ανανεώνει το «μέχρι πότε ζούσα» μέσα από την ουρά του ημερολογίου: το
  /// σημάδι ζωής είναι διαγνωστική άνεση και δεν επιτρέπεται να κρατήσει την
  /// οθόνη. Αν ο φάκελος δεν απαντήσει, σιγεί όλο το ημερολόγιο.
  Future<void> _markAlive() async {
    if (!host.isDiskAvailable) return;
    final mark = _freshMark();
    if (mark == null) return;
    _currentMark = mark;
    await host.writeLivenessMark(_sessionLockFile().path, mark.encode());
  }

  /// Το ομαλό κλείσιμο δεν μπόρεσε να σβήσει το ίχνος: το λέει τοπικά στην
  /// επόμενη εκκίνηση — δες [CleanExitNote].
  Future<void> noteCleanExit() async {
    final mark = _currentMark;
    final note = host.cleanExitNote;
    if (mark == null || note == null) return;
    await note.write(_runSlug, mark);
  }

  /// Ποια εκτέλεση — ίδιο κλειδί με το όνομα του ίχνους.
  String get _runSlug => host.instanceId.isEmpty
      ? StationName.fileSafe
      : CrashLogService.instanceSlug(host.instanceId);

  /// Σβήνει το ίχνος — στο ομαλό κλείσιμο και πριν από κάθε μετακόμιση.
  Future<void> remove() async {
    final lock = _sessionLockFile();
    if (await lock.exists().timeout(CrashLogService.diskProbeTimeout)) {
      await lock.delete().timeout(CrashLogService.diskProbeTimeout);
    }
  }

  File _sessionLockFile() => File(
    p.join(
      host.logsDirectory,
      LogFileNames.sessionLockFileNameFor(
        StationName.fileSafe,
        host.instanceId,
      ),
    ),
  );
}
