import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'crash_log_service.dart';
import 'station_name.dart';

/// Το σημείωμα «κλείσε, σε παρακαλώ» από έναν σταθμό προς έναν άλλον.
///
/// **Γιατί αρχείο και όχι βάση.** Το αίτημα γεννιέται από την οθόνη της
/// μπλοκαρισμένης αναβάθμισης σχήματος, όπου η βάση **δεν** είναι ανοιχτή — ο
/// φρουρός τρέχει πριν από το άνοιγμα, επίτηδες. Ο αιτών δεν έχει βάση να
/// γράψει μέσα της, και δεν επιτρέπεται να ανοίξει: το άνοιγμα **είναι** η
/// μόνιμη αναβάθμιση που προσπαθούμε να αποτρέψουμε. Ο κοινός φάκελος `logs`
/// δίπλα στη βάση είναι ήδη δίαυλος μεταξύ σταθμών — ως τώρα μονόδρομος.
///
/// **Ένα σημείωμα ανά παραλήπτη.** Το όνομα του αρχείου φέρει την ίδια
/// ταυτότητα με το ίχνος ζωής: σταθμός συν αποτύπωμα της εκτέλεσης. Έτσι κάθε
/// εφαρμογή ρωτά για **ένα** αρχείο με γνωστό όνομα — χωρίς σάρωση φακέλου —
/// και σβήνει μόνο το δικό της. Ένα κοινό αρχείο για πολλούς παραλήπτες θα
/// σήμαινε ότι ο πρώτος που το τιμά το εξαφανίζει από τους υπόλοιπους.
class StationShutdownRequest {
  const StationShutdownRequest({
    required this.fromStation,
    required this.requestedAt,
    required this.immediate,
    this.database,
  });

  /// Ποιος ζητά το κλείσιμο — όνομα υπολογιστή, για να ξέρει ο παραλήπτης
  /// ποιον αφορά η βιασύνη.
  final String fromStation;

  final DateTime requestedAt;

  /// Άμεσο αίτημα: ο αιτών **βλέπει** ότι η θέση είναι άδεια και δεν έχει λόγο
  /// να περιμένει αντίστροφη μέτρηση για άνθρωπο που λείπει.
  final bool immediate;

  /// **Το όνομα αρχείου** της βάσης που αφορά το αίτημα — όχι η διαδρομή, για
  /// τον ίδιο λόγο με το ίχνος ζωής: ο ένας σταθμός βλέπει `\\POPINIO\…` και ο
  /// άλλος `D:\…` για το ίδιο αρχείο.
  ///
  /// Ένας φάκελος μπορεί να φιλοξενεί πολλές βάσεις με κοινό `logs`. Ο
  /// συνάδελφος που δουλεύει στη διπλανή βάση δεν εμποδίζει την αναβάθμιση, και
  /// δεν επιτρέπεται να κλείσει γι' αυτήν.
  final String? database;

  /// Πόσο ζει ένα σημείωμα που δεν παραλήφθηκε ποτέ.
  ///
  /// Ο σταθμός-παραλήπτης μπορεί να ήταν κλειστός. Χωρίς λήξη, το σημείωμα θα
  /// καθόταν στον κοινόχρηστο φάκελο και θα έκλεινε την εφαρμογή του **την
  /// επόμενη μέρα**, για αναβάθμιση που έγινε προ πολλού. Δέκα λεπτά καλύπτουν
  /// με άνεση τον κύκλο ελέγχου του ενός λεπτού και τίποτα παραπάνω.
  static const Duration maxAge = Duration(minutes: 10);

  /// Ισχύει ακόμη αυτό το σημείωμα τη στιγμή [now];
  bool isFreshAt(DateTime now) => now.difference(requestedAt) < maxAge;

  /// Αφορά αυτό το σημείωμα τη βάση [databaseFileName];
  ///
  /// **Η άγνοια απαντά «ναι»**, όπως και στο ίχνος ζωής: όταν λείπει το όνομα
  /// από τη μία ή την άλλη πλευρά, δεν έχουμε λόγο να αγνοήσουμε ένα αίτημα που
  /// κάποιος έστειλε επίτηδες.
  bool targetsDatabase(String? databaseFileName) {
    final mine = databaseFileName?.trim().toLowerCase() ?? '';
    final theirs = database?.trim().toLowerCase() ?? '';
    if (mine.isEmpty || theirs.isEmpty) return true;
    return mine == theirs;
  }

  String encode() => jsonEncode({
    'fromStation': fromStation,
    'requestedAt': requestedAt.toIso8601String(),
    'immediate': immediate,
    if (database != null) 'database': database,
  });

  /// `null` όταν το αρχείο είναι κενό, αλλοιωμένο, ή μισογραμμένο.
  ///
  /// Ένα σημείωμα που δεν διαβάζεται **δεν κλείνει** την εφαρμογή. Στο αίτημα
  /// κλεισίματος η άγνοια οφείλει να πέφτει στην πλευρά που δεν κάνει τίποτα:
  /// το χειρότερο που μπορεί να συμβεί είναι να μείνει ανοιχτή μια εφαρμογή
  /// ένα λεπτό παραπάνω, ενώ το αντίθετο σφάλμα κλείνει τη δουλειά ανθρώπου.
  static StationShutdownRequest? decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, Object?>) return null;
      final requestedAt = DateTime.tryParse(
        decoded['requestedAt']?.toString() ?? '',
      );
      if (requestedAt == null) return null;
      final database = decoded['database']?.toString().trim() ?? '';
      return StationShutdownRequest(
        fromStation: decoded['fromStation']?.toString() ?? '',
        requestedAt: requestedAt,
        immediate: decoded['immediate'] == true,
        database: database.isEmpty ? null : database,
      );
    } on FormatException {
      return null;
    }
  }
}

/// Η απάντηση του παραλήπτη, όταν ο άνθρωπος μπροστά στην οθόνη αρνείται.
///
/// Χωρίς αυτήν ο αιτών βλέπει έναν σταθμό που απλώς δεν φεύγει, και δεν ξέρει
/// αν τον αρνήθηκαν, αν το σημείωμα χάθηκε, ή αν ο συνάδελφος λείπει. Οι τρεις
/// περιπτώσεις θέλουν εντελώς διαφορετική κίνηση από μέρους του.
class StationShutdownReply {
  const StationShutdownReply({
    required this.fromStation,
    required this.repliedAt,
  });

  /// Ποιος αρνήθηκε — όνομα υπολογιστή, όπως εμφανίζεται και στη λίστα.
  final String fromStation;

  final DateTime repliedAt;

  /// Ίδια λήξη με το σημείωμα: μια απάντηση που δεν διαβάστηκε ποτέ δεν
  /// στοιχειώνει την επόμενη αναβάθμιση.
  bool isFreshAt(DateTime now) =>
      now.difference(repliedAt) < StationShutdownRequest.maxAge;

  String encode() => jsonEncode({
    'fromStation': fromStation,
    'repliedAt': repliedAt.toIso8601String(),
  });

  static StationShutdownReply? decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, Object?>) return null;
      final repliedAt = DateTime.tryParse(
        decoded['repliedAt']?.toString() ?? '',
      );
      if (repliedAt == null) return null;
      return StationShutdownReply(
        fromStation: decoded['fromStation']?.toString() ?? '',
        repliedAt: repliedAt,
      );
    } on FormatException {
      return null;
    }
  }
}

/// Το όνομα του σημειώματος για έναν συγκεκριμένο παραλήπτη.
///
/// Ίδιος κανόνας με το `session_<σταθμός>_<αποτύπωμα>.lock`, ώστε η ταυτότητα
/// να είναι **μία** σε όλη την εφαρμογή. Δύο αντίγραφα στον ίδιο υπολογιστή
/// (η κανονική και η δοκιμαστική) παίρνουν διαφορετικό αρχείο, όπως παίρνουν
/// και διαφορετικό ίχνος.
String shutdownRequestFileNameFor(String station, [String instance = '']) {
  final run = instance.trim();
  if (run.isEmpty) return 'shutdown_request_$station.json';
  return 'shutdown_request_${station}_'
      '${CrashLogService.instanceSlug(run)}.json';
}

/// Το όνομα της απάντησης, με την ταυτότητα του **παραλήπτη** πάνω της.
///
/// Την ταυτότητα του απαντώντα κρατά και η απάντηση, ώστε ο αιτών να ξέρει
/// ποιο αρχείο να διαβάσει για ποιον σταθμό — η ίδια αντιστοίχιση που
/// χρησιμοποίησε για να στείλει.
String shutdownReplyFileNameFor(String station, [String instance = '']) {
  final run = instance.trim();
  if (run.isEmpty) return 'shutdown_reply_$station.json';
  return 'shutdown_reply_${station}_'
      '${CrashLogService.instanceSlug(run)}.json';
}

/// Γράφει το σημείωμα για έναν παραλήπτη. `true` όταν έφτασε στον δίσκο.
///
/// **Ατομική εγγραφή.** Το αρχείο γράφεται με προσωρινό όνομα και μετονομάζεται
/// στη θέση του. Ο παραλήπτης ρωτά κάθε λεπτό, και χωρίς αυτό θα μπορούσε να
/// πέσει πάνω σε μισογραμμένο αρχείο — που θα το απέρριπτε ως αλλοιωμένο και θα
/// έχανε το αίτημα ως τον επόμενο κύκλο.
Future<bool> writeShutdownRequest({
  required String logsDirectory,
  required String toStation,
  required String toInstance,
  required StationShutdownRequest request,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final target = File(
    p.join(logsDirectory, shutdownRequestFileNameFor(toStation, toInstance)),
  );
  final staging = File('${target.path}.tmp');
  try {
    await staging.writeAsString(request.encode(), flush: true).timeout(timeout);
    await staging.rename(target.path).timeout(timeout);
    return true;
  } catch (_) {
    // Ο φάκελος δεν απάντησε. Ο αιτών το μαθαίνει και μπορεί να σηκώσει
    // τηλέφωνο — μια αποτυχία εδώ δεν επιτρέπεται να ρίξει την οθόνη του.
    try {
      await staging.delete().timeout(timeout);
    } catch (_) {
      // Το προσωρινό αρχείο είναι σκουπίδι, όχι πρόβλημα: λήγει με τον φάκελο.
    }
    return false;
  }
}

/// Το σημείωμα που περιμένει **εμένα**, αν περιμένει.
///
/// Ένα «υπάρχεις;» σε γνωστό όνομα — όχι σάρωση φακέλου. Το περιεχόμενο
/// διαβάζεται μόνο όταν το αρχείο υπάρχει, που συμβαίνει ελάχιστες φορές τον
/// χρόνο. Είναι η φθηνότερη δυνατή ερώτηση προς έναν δικτυακό φάκελο.
///
/// **Ληγμένο σημείωμα σβήνεται και δεν επιστρέφεται.** Αν κανείς δεν το
/// μάζευε, θα ξανά-ρωτιόταν σε κάθε κύκλο για πάντα.
Future<StationShutdownRequest?> readShutdownRequestForMe({
  required String logsDirectory,
  required String myStation,
  required String myInstance,
  required DateTime now,
  String? myDatabase,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final file = File(
    p.join(logsDirectory, shutdownRequestFileNameFor(myStation, myInstance)),
  );
  try {
    if (!await file.exists().timeout(timeout)) return null;
    final request = StationShutdownRequest.decode(
      await file.readAsString().timeout(timeout),
    );
    if (request == null || !request.isFreshAt(now)) {
      await _deleteQuietly(file, timeout);
      return null;
    }
    if (!request.targetsDatabase(myDatabase)) return null;
    return request;
  } catch (_) {
    // Φάκελος που χάθηκε ή αρχείο που δεν διαβάζεται: καμία ενέργεια. Η άγνοια
    // πέφτει πάντα στην πλευρά που αφήνει την εφαρμογή ανοιχτή.
    return null;
  }
}

/// Μαζεύει το σημείωμα μόλις τιμηθεί ή απορριφθεί.
///
/// Χωρίς αυτό, η επόμενη εκκίνηση της ίδιας εφαρμογής θα έβρισκε το ίδιο
/// σημείωμα και θα ξανάκλεινε αμέσως — ατέρμονος κύκλος για τον συνάδελφο που
/// προσπαθεί να ξαναμπεί.
Future<void> clearShutdownRequestForMe({
  required String logsDirectory,
  required String myStation,
  required String myInstance,
  Duration timeout = const Duration(seconds: 3),
}) async {
  await _deleteQuietly(
    File(
      p.join(logsDirectory, shutdownRequestFileNameFor(myStation, myInstance)),
    ),
    timeout,
  );
}

/// Αφήνει την άρνηση για τον αιτούντα και μαζεύει το σημείωμα.
Future<void> writeShutdownDenial({
  required String logsDirectory,
  required String myStation,
  required String myInstance,
  required DateTime now,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final target = File(
    p.join(logsDirectory, shutdownReplyFileNameFor(myStation, myInstance)),
  );
  final staging = File('${target.path}.tmp');
  final reply = StationShutdownReply(fromStation: myStation, repliedAt: now);
  try {
    await staging.writeAsString(reply.encode(), flush: true).timeout(timeout);
    await staging.rename(target.path).timeout(timeout);
  } catch (_) {
    // Η άρνηση είναι ευγένεια προς τον αιτούντα, όχι προϋπόθεση για να μείνει
    // ανοιχτή η εφαρμογή. Αν δεν γραφτεί, εκείνος βλέπει απλώς ότι ο σταθμός
    // δεν έφυγε — που είναι η αλήθεια.
  }
  await clearShutdownRequestForMe(
    logsDirectory: logsDirectory,
    myStation: myStation,
    myInstance: myInstance,
    timeout: timeout,
  );
}

/// Διαβάζει την άρνηση ενός συγκεκριμένου σταθμού, αν υπάρχει, και τη μαζεύει.
///
/// Την καταναλώνει ο αιτών: διαβάζεται **μία φορά** και σβήνει, ώστε μια παλιά
/// άρνηση να μη στοιχειώνει την επόμενη προσπάθεια.
Future<StationShutdownReply?> takeShutdownDenial({
  required String logsDirectory,
  required String fromStation,
  required String fromInstance,
  required DateTime now,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final file = File(
    p.join(logsDirectory, shutdownReplyFileNameFor(fromStation, fromInstance)),
  );
  try {
    if (!await file.exists().timeout(timeout)) return null;
    final reply = StationShutdownReply.decode(
      await file.readAsString().timeout(timeout),
    );
    await _deleteQuietly(file, timeout);
    if (reply == null || !reply.isFreshAt(now)) return null;
    return reply;
  } catch (_) {
    return null;
  }
}

Future<void> _deleteQuietly(File file, Duration timeout) async {
  try {
    await file.delete().timeout(timeout);
  } catch (_) {
    // Αρχείο που έφυγε στο μεταξύ, ή φάκελος που δεν απαντά.
  }
}

/// Η ταυτότητα αυτού του αντιγράφου, όπως τη γράφουν τα ονόματα αρχείων.
///
/// Μία πηγή για τον σταθμό και την εκτέλεση: το ίχνος ζωής, το σημείωμα και η
/// απάντηση οφείλουν να συμφωνούν, αλλιώς η εφαρμογή θα έψαχνε σημείωμα σε
/// όνομα που κανείς δεν γράφει.
({String station, String instance}) currentStationIdentity() => (
  station: StationName.fileSafe,
  instance: CrashLogService.instanceOrNull?.instanceId ?? '',
);
