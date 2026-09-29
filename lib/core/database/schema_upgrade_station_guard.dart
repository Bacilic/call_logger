/// Ποιοι **άλλοι** σταθμοί κρατούν τη βάση τη στιγμή που ζητείται μόνιμη
/// αναβάθμιση σχήματος.
///
/// **Γιατί απαγορεύει αντί να προειδοποιεί.** Η συντήρηση (αντίγραφα,
/// επισκευές) προειδοποιεί και αφήνει τον άνθρωπο να αποφασίσει, γιατί ο
/// συντηρητής μπορεί να ξαναδοκιμάσει. Η αναβάθμιση σχήματος δεν αναιρείται:
/// μία επιλογή σφραγίζει το αρχείο σε νέα έκδοση και κόβει από αυτό κάθε
/// συνάδελφο με παλαιότερη εφαρμογή. Ένα «Συνέχεια παρ' όλα αυτά» εδώ θα ήταν
/// κουμπί που μόνο ζημιά μπορεί να κάνει.
///
/// **Το αδιέξοδο λύνεται μόνο του.** Το ίχνος «τρέχω τώρα» παλιώνει μέσα σε
/// [OperatorPresence.onlineWindow], οπότε ένα φάντασμα από απότομο κλείσιμο
/// κρατά την πόρτα κλειστή για λεπτά, όχι για πάντα — και η «Επαναδοκιμή» της
/// οθόνης σφάλματος ξεκλειδώνει χωρίς επανεκκίνηση. Γι' αυτό δεν χρειάζεται
/// καμία διαφυγή τύπου «ξέρω τι κάνω».
///
/// **Η δική μου εκτέλεση δεν μπλοκάρει τον εαυτό της — καμία άλλη όμως δεν
/// εξαιρείται.** Το δεύτερο αντίγραφο στον ίδιο υπολογιστή (η δοκιμαστική
/// δίπλα στην κανονική) κρατά κι εκείνο το αρχείο ανοιχτό με το παλιό σχήμα:
/// αν το αναβαθμίσουμε από κάτω του, παθαίνει ακριβώς ό,τι θα πάθαινε ο
/// συνάδελφος σε άλλον υπολογιστή.
library;

import '../models/operator_presence.dart';
import '../services/crash_log_service.dart';
import '../services/session_liveness_mark.dart';
import '../services/station_name.dart';

/// Τα φρέσκα ίχνη **άλλων εκτελέσεων που κρατούν τη δική μας βάση**.
///
/// Καθαρή συνάρτηση: ο κανόνας κρίνεται χωρίς αρχεία, χωρίς ρολόι και χωρίς
/// σύστημα. Τρία φίλτρα, με αυτή τη σειρά:
///
/// 1. **Φρεσκάδα** — η **ίδια** με την παρουσία στη βάση. Ένα ίχνος που έπαψε
///    να ανανεώνεται είναι κατάρρευση, όχι συνάδελφος.
/// 2. **Ίδια βάση** — ένας φάκελος μπορεί να έχει πολλές βάσεις με έναν κοινό
///    φάκελο `logs`. Ο συνάδελφος που δουλεύει στη διπλανή βάση δεν εμποδίζει
///    τίποτα, και μετρημένος θα έκλεινε την πόρτα για λόγο που δεν υπάρχει.
/// 3. **Άλλη εκτέλεση** — όχι άλλος σταθμός. Το δεύτερο αντίγραφο στον ίδιο
///    υπολογιστή κρατά κι εκείνο το αρχείο ανοιχτό.
///
/// **Η άγνοια μετράει ΥΠΕΡ του φρουρού.** Ίχνος που δεν δηλώνει βάση (γραμμένο
/// από παλαιότερη έκδοση) περνά ως «μπορεί να είναι η ίδια»: ο συνάδελφος με
/// την παλιά εφαρμογή είναι ακριβώς αυτός που η αναβάθμιση θα άφηνε έξω, και
/// δεν επιτρέπεται να γίνει αόρατος τη στιγμή που τον προστατεύουμε.
List<SessionLivenessMark> freshMarksFromOtherStations({
  required List<SessionLivenessMark> marks,
  required DateTime now,
  required String myStation,
  String? myDatabase,
  String? myInstance,
}) {
  return [
    for (final mark in marks)
      if (now.difference(mark.lastSeen) < OperatorPresence.onlineWindow &&
          mark.holdsDatabase(myDatabase) &&
          !mark.isSameRunAs(station: myStation, instance: myInstance))
        mark,
  ];
}

/// Ρωτά τον φάκελο των ιχνών: κρατά κάποιος άλλος τη βάση τώρα;
///
/// Η βάση **δεν** είναι ανοιχτή όταν καλείται αυτό — ο φρουρός τρέχει πριν από
/// το άνοιγμα — οπότε η μόνη πηγή είναι τα ίχνη δίπλα της. Φάκελος που δεν
/// απαντά δίνει κενή λίστα: η άγνοια δεν κλειδώνει την πόρτα.
Future<List<SessionLivenessMark>> otherStationsHoldingDatabase({
  DateTime? now,
  String? logsDirectory,
  String? myStation,
  String? myDatabase,
  String? myInstance,
}) async {
  final log = CrashLogService.instanceOrNull;
  final directory = (logsDirectory ?? _defaultLogsDirectory())?.trim();
  if (directory == null || directory.isEmpty) return const [];
  return freshMarksFromOtherStations(
    marks: await readSessionLivenessMarks(directory),
    now: now ?? DateTime.now(),
    myStation: myStation ?? StationName.current,
    myDatabase: myDatabase ?? log?.databaseFileName,
    myInstance: myInstance ?? log?.instanceId,
  );
}

/// Ο φάκελος των ιχνών — αν το ημερολόγιο έχει ήδη διαπιστώσει ότι ο δίσκος δεν
/// απαντά, δεν τον ξαναρωτάμε: ένας δικτυακός φάκελος που χάθηκε κοστίζει
/// δευτερόλεπτα αναμονής για απάντηση που ξέρουμε ήδη.
String? _defaultLogsDirectory() {
  final log = CrashLogService.instanceOrNull;
  if (log == null || !log.isDiskAvailable) return null;
  return log.logsDirectory;
}

/// «POPINIO · έκδοση 4.1 · πριν από 2΄» — μία γραμμή ανά σταθμό.
///
/// Χωρίς ονόματα ανθρώπων: τα ίχνη δεν ξέρουν ποιος κάθεται στον σταθμό, και το
/// όνομα του υπολογιστή αρκεί για να ξέρει κανείς **πού** να τηλεφωνήσει.
String describeStationsHoldingDatabase(
  List<SessionLivenessMark> marks, {
  required DateTime now,
  String? myStation,
}) {
  final me = (myStation ?? StationName.current).trim().toLowerCase();
  final lines = <String>[];
  for (final mark in marks) {
    final station = mark.station.trim();
    final parts = <String>[station.isEmpty ? 'άγνωστος σταθμός' : station];
    // Ίδιο όνομα υπολογιστή με τον δικό μας σημαίνει δεύτερο αντίγραφο της
    // εφαρμογής εδώ. Χωρίς αυτή τη λέξη ο χρήστης διαβάζει το όνομα του ίδιου
    // του του υπολογιστή και ψάχνει συνάδελφο που δεν υπάρχει.
    if (me.isNotEmpty && station.toLowerCase() == me) {
      parts.add('άλλο αντίγραφο σε αυτόν τον υπολογιστή');
    }
    final version = mark.version.trim();
    if (version.isNotEmpty) parts.add('έκδοση $version');
    parts.add(_describeSince(now, mark.lastSeen));
    lines.add('• ${parts.join(' · ')}');
  }
  return lines.join('\n');
}

String _describeSince(DateTime now, DateTime lastSeen) {
  final elapsed = now.difference(lastSeen);
  if (elapsed.inSeconds < 90) return 'μόλις τώρα';
  return 'πριν από ${elapsed.inMinutes}΄';
}

/// Σε πόση ώρα θα δει ο σταθμός [mark] ένα σημείωμα που στέλνεται τώρα.
///
/// **Η πρόβλεψη στηρίζεται στον κοινό παλμό.** Κάθε εφαρμογή γράφει το ίχνος
/// της και ρωτά για σημείωμα στην **ίδια** στιγμή, κάθε [CrashLogService.
/// livenessInterval]. Άρα ο επόμενος έλεγχός της είναι «τελευταίο σημάδι ζωής
/// συν ένα λεπτό», και η αφαίρεση δίνει την αναμονή.
///
/// `null` όταν η απάντηση δεν μπορεί να ειπωθεί τίμια:
///
/// 1. **Η εκτέλεση δεν ακούει** — παλαιότερη έκδοση, ή εφαρμογή χωρίς κέλυφος.
///    Μια μέτρηση εκεί θα υποσχόταν μήνυμα που δεν πρόκειται να παραδοθεί.
/// 2. **Το ίχνος είναι ήδη ξεπερασμένο** — αν ο υπολογισμός βγάζει παρελθόν, ο
///    παλμός που περιμέναμε έχει ήδη περάσει χωρίς να ανανεωθεί το ίχνος: κάτι
///    δεν πάει καλά εκεί, και μια ένδειξη «σε 0 δευτερόλεπτα» θα ήταν εικασία.
///
/// **Δύο ρολόγια, μία παραδοχή.** Το «τελευταίο σημάδι» γράφτηκε από το ρολόι
/// του άλλου υπολογιστή. Σε δίκτυο domain τα ρολόγια συγχρονίζονται, οπότε η
/// απόκλιση είναι δευτερόλεπτα — αρκετά για ένδειξη αναμονής, ποτέ για κάτι
/// που θα κρινόταν με ακρίβεια.
Duration? shutdownRequestArrivalIn(
  SessionLivenessMark mark, {
  required DateTime now,
  Duration pulse = const Duration(minutes: 1),
}) {
  if (!mark.listensForShutdownRequests) return null;
  final arrival = mark.lastSeen.add(pulse);
  final wait = arrival.difference(now);
  if (wait.isNegative) return null;
  return wait;
}

/// «σε 0:43» — η αναμονή σε μορφή που διαβάζεται με μια ματιά.
String formatShutdownRequestArrival(Duration wait) {
  final seconds = wait.inSeconds;
  if (seconds < 1) return 'όπου να ΄ναι';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return 'σε $minutes:${rest.toString().padLeft(2, '0')}';
}

/// Το μήνυμα που βλέπει ο χρήστης όταν η αναβάθμιση απαγορεύεται.
///
/// Λέει **ποιους** να κλείσει: «κλείστε όλες τις εφαρμογές» χωρίς ονόματα
/// σημαίνει τηλεφωνήματα στα τυφλά σε όλο το δίκτυο.
String schemaUpgradeBlockedMessage({
  required int fileVersion,
  required int appVersion,
  required int stationCount,
}) {
  // «Εφαρμογή», όχι «υπολογιστής»: ένα από τα ανοιχτά αντίγραφα μπορεί να
  // τρέχει σε αυτόν εδώ τον υπολογιστή, και η λίστα από κάτω το λέει.
  final subject = stationCount == 1
      ? 'Μία ακόμη εφαρμογή έχει'
      : '$stationCount ακόμη εφαρμογές έχουν';
  return 'Δεν είναι δυνατή η αναβάθμιση της βάσης: $subject τη βάση ανοιχτή '
      'αυτή τη στιγμή. Η αναβάθμιση από την έκδοση $fileVersion στην '
      '$appVersion είναι μόνιμη και θα άφηνε έξω κάθε εφαρμογή παλαιότερης '
      'έκδοσης. Παρακαλώ κλείστε όλες τις εφαρμογές στο δίκτυο και πατήστε '
      '«Επαναδοκιμή».';
}
