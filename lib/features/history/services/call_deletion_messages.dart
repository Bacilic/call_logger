// Καθαρή λογική μηνυμάτων διαγραφής κλήσης (χωρίς widgets/βάση).

import '../../../core/database/call_deletion_impact.dart';

/// Πόσα εισιτήρια ονομάζονται πριν το μήνυμα κόψει με «κ.ά.».
const int _maxNamedTickets = 4;

/// Πόσοι τίτλοι εκκρεμοτήτων απαριθμούνται πριν το «και N ακόμη».
const int _maxNamedTasks = 4;

/// Πόσες κλήσεις-με-συνδέσεις απαριθμούνται στη μαζική διαγραφή.
const int kMaxListedConnectedCalls = 30;

/// Τίτλος εκκρεμότητας που έμεινε κενός — ο χρήστης πρέπει να δει ότι υπάρχει.
const String _untitledTask = '(χωρίς τίτλο)';

/// Η εισαγωγική γραμμή του διαλόγου διαγραφής μίας κλήσης.
String callDeletionHeadline(CallDeletionImpact impact) {
  if (!impact.hasConnections) return 'Επιβεβαιώστε τη διαγραφή της κλήσης.';
  return 'Η κλήση συνδέεται με:';
}

/// Η εισαγωγική γραμμή του διαλόγου μαζικής διαγραφής.
///
/// Ονομάζει **όλα** τα είδη σύνδεσης, όχι μόνο τις εκκρεμότητες: όσο έλεγε
/// «N συνδεδεμένες εκκρεμότητες» ενώ μετρούσε και αιτήματα Lansweeper, ο
/// αριθμός ήταν σωστός και η λέξη ψέμα.
String callBulkDeletionHeadline(
  CallDeletionImpact impact, {
  required int callCount,
}) {
  final calls = callCount == 1
      ? 'Η επιλεγμένη κλήση'
      : 'Οι $callCount επιλεγμένες κλήσεις';
  if (!impact.hasConnections) {
    return callCount == 1
        ? 'Να διαγραφεί η επιλεγμένη κλήση;'
        : 'Να διαγραφούν οι $callCount επιλεγμένες κλήσεις;';
  }
  final verb = callCount == 1 ? 'έχει' : 'έχουν';
  final total = impact.totalConnections == 1
      ? '1 σύνδεση'
      : '${impact.totalConnections} συνδέσεις';
  return '$calls $verb συνολικά $total: ${_connectionBreakdown(impact)}.';
}

/// «2 εκκρεμότητες και 1 αίτημα Lansweeper» — μηδενικά είδη παραλείπονται.
String _connectionBreakdown(CallDeletionImpact impact) {
  final parts = <String>[
    if (impact.hasLinkedTasks)
      impact.linkedTasks == 1
          ? '1 εκκρεμότητα'
          : '${impact.linkedTasks} εκκρεμότητες',
    if (impact.hasExternalLinks)
      impact.externalLinks == 1
          ? '1 αίτημα Lansweeper'
          : '${impact.externalLinks} αιτήματα Lansweeper',
  ];
  if (parts.length == 1) return parts.single;
  return '${parts.first} και ${parts.last}';
}

/// Η γραμμή για το Lansweeper — `null` όταν η κλήση δεν πέρασε ποτέ.
///
/// Ορατή **πάντα**, ανεξάρτητα από τον διακόπτη της οριστικής διαγραφής: το «με
/// τι συνδέεται αυτή η κλήση» είναι πληροφορία που κρίνει την απόφαση, όχι
/// συνέπεια της απόφασης. Τι θα χαθεί το λέει χωριστά το
/// [callHardDeleteLossWarning].
String? callLansweeperConnectionLine(CallDeletionImpact impact) {
  return _lansweeperLine(
    externalLinks: impact.externalLinks,
    ticketIds: impact.lansweeperTicketIds,
  );
}

/// Η γραμμή-επικεφαλίδα των εκκρεμοτήτων — `null` όταν δεν υπάρχουν.
String? callTasksConnectionLine(CallDeletionImpact impact) {
  if (!impact.hasLinkedTasks) return null;
  if (impact.linkedTasks == 1) return '1 συνδεδεμένη εκκρεμότητα:';
  return '${impact.linkedTasks} συνδεδεμένες εκκρεμότητες:';
}

/// Οι τίτλοι των εκκρεμοτήτων προς εμφάνιση, κομμένοι στο όριο απαρίθμησης.
List<String> callTaskTitleLines(CallDeletionImpact impact) {
  final titles = [
    for (final title in impact.taskTitles)
      if (title.trim().isEmpty) _untitledTask else title.trim(),
  ];
  if (titles.length <= _maxNamedTasks) return titles;
  return titles.take(_maxNamedTasks).toList(growable: false);
}

/// «και 3 ακόμη» όταν η λίστα κόπηκε — `null` όταν φαίνονται όλες.
///
/// Ο περιορισμός δηλώνεται αντί να σιωπά: λίστα που σταματά χωρίς εξήγηση
/// διαβάζεται ως «αυτές είναι όλες».
String? callTaskTitlesOverflowLine(CallDeletionImpact impact) {
  final remaining = impact.linkedTasks - _maxNamedTasks;
  if (remaining <= 0) return null;
  return remaining == 1 ? 'και 1 ακόμη' : 'και $remaining ακόμη';
}

/// Οι κλήσεις-με-συνδέσεις που απαριθμεί η μαζική διαγραφή.
List<CallConnectionSummary> callConnectionRows(CallDeletionImpact impact) {
  final connected = impact.connectedCalls;
  if (connected.length <= kMaxListedConnectedCalls) return connected;
  return connected.take(kMaxListedConnectedCalls).toList(growable: false);
}

/// «και 170 ακόμη κλήσεις με συνδέσεις» — `null` όταν φαίνονται όλες.
String? callConnectionRowsOverflowLine(CallDeletionImpact impact) {
  final remaining = impact.connectedCalls.length - kMaxListedConnectedCalls;
  if (remaining <= 0) return null;
  final calls = remaining == 1
      ? '1 ακόμη κλήση με συνδέσεις'
      : '$remaining ακόμη κλήσεις με συνδέσεις';
  return 'και $calls (εμφανίζονται οι πρώτες '
      '$kMaxListedConnectedCalls)';
}

/// «03-08-2026 09:40» από τα πεδία της βάσης· ό,τι λείπει παραλείπεται.
String callConnectionRowTimestamp(CallConnectionSummary call) {
  final parts = call.date.split('-');
  final day = parts.length == 3
      ? '${parts[2]}-${parts[1]}-${parts[0]}'
      : call.date;
  if (day.isEmpty) return call.time;
  if (call.time.isEmpty) return day;
  return '$day ${call.time}';
}

/// «Lansweeper — εισιτήριο 7001 · 2 εκκρεμότητες» για μία γραμμή της λίστας.
String callConnectionRowLabel(CallConnectionSummary call) {
  final parts = <String>[
    ?_lansweeperLine(
      externalLinks: call.externalLinks,
      ticketIds: call.lansweeperTicketIds,
    ),
    if (call.linkedTasks == 1)
      '1 εκκρεμότητα'
    else if (call.linkedTasks > 1)
      '${call.linkedTasks} εκκρεμότητες',
  ];
  return parts.join(' · ');
}

/// Ο τίτλος του κουμπιού που αφήνει τις εκκρεμότητες στη θέση τους.
String callKeepTasksButtonLabel({required int callCount}) =>
    callCount == 1 ? 'Διαγραφή μόνο της κλήσης' : 'Διαγραφή μόνο των κλήσεων';

/// Τι ακριβώς κάνει το κουμπί που αφήνει τις εκκρεμότητες.
String callKeepTasksButtonHint(CallDeletionImpact impact) {
  final tasks = impact.linkedTasks == 1
      ? 'Η εκκρεμότητα μένει'
      : 'Οι ${impact.linkedTasks} εκκρεμότητες μένουν';
  return '$tasks στη λίστα σας, χωρίς σύνδεση με κλήση.';
}

/// Ο τίτλος του κουμπιού που παρασύρει και τις εκκρεμότητες.
String callCascadeButtonLabel({required int callCount}) => callCount == 1
    ? 'Διαγραφή κλήσης και εκκρεμοτήτων'
    : 'Διαγραφή κλήσεων και εκκρεμοτήτων';

/// Τι ακριβώς κάνει το κουμπί που παρασύρει και τις εκκρεμότητες.
String callCascadeButtonHint(CallDeletionImpact impact) {
  return impact.linkedTasks == 1
      ? 'Διαγράφεται και η συνδεδεμένη εκκρεμότητα.'
      : 'Διαγράφονται και οι ${impact.linkedTasks} συνδεδεμένες εκκρεμότητες.';
}

/// Ότι τα αιτήματα Lansweeper δεν παίζουν ρόλο στην επιλογή — `null` όταν
/// δεν υπάρχουν ή όταν η οριστική διαγραφή τα σβήνει ούτως ή άλλως.
///
/// Χωρίς αυτή τη γραμμή ο χρήστης βλέπει το εισιτήριο στην κάρτα συνδέσεων και
/// εύλογα υποθέτει ότι κάποιο από τα δύο κουμπιά αποφασίζει και γι' αυτό.
String? callLansweeperUnaffectedNote(
  CallDeletionImpact impact, {
  required bool hardDelete,
}) {
  if (!impact.hasExternalLinks || hardDelete) return null;
  return impact.externalLinks == 1
      ? 'Το αίτημα Lansweeper δεν επηρεάζεται από καμία από τις δύο επιλογές.'
      : 'Τα αιτήματα Lansweeper δεν επηρεάζονται από καμία από τις δύο '
            'επιλογές.';
}

/// Τι χάνεται ανεπιστρεπτί **μόνο** με την οριστική διαγραφή.
///
/// Επιστρέφει `null` όταν δεν υπάρχει τίποτα να προειδοποιήσει. Ο έλεγχος δεν
/// είναι διακοσμητικός: στην αναστρέψιμη διαγραφή το ιστορικό Lansweeper μένει
/// άθικτο, οπότε ένα μόνιμο μήνυμα θα έλεγε ψέματα προς την αντίθετη κατεύθυνση.
String? callHardDeleteLossWarning(CallDeletionImpact impact) {
  if (!impact.hasExternalLinks) return null;
  return 'Η οριστική διαγραφή σβήνει και το ιστορικό σύνδεσης με το '
      'Lansweeper. Μετά από αυτό η κλήση δεν βρίσκεται πια με αναζήτηση του '
      'αριθμού εισιτηρίου.';
}

/// Το ίδιο για τη μαζική διαγραφή — ονομάζει **πόσες** κλήσεις αφορά.
///
/// Ποιες ακριβώς τις δείχνει ήδη η λίστα από πάνω· εδώ χρειάζεται μόνο το
/// μέγεθος της απώλειας, ώστε ο χρήστης να ξέρει αν αφορά μία ή τριάντα.
String? callBulkHardDeleteLossWarning(CallDeletionImpact impact) {
  if (!impact.hasExternalLinks) return null;
  final affected = impact.callsWithExternalLinks;
  final subject = affected == 1
      ? '1 από τις κλήσεις που διαγράφετε έχει αίτημα Lansweeper'
      : '$affected από τις κλήσεις που διαγράφετε έχουν αίτημα Lansweeper';
  final result = affected == 1
      ? 'Μετά από αυτό δεν βρίσκεται πια με αναζήτηση του αριθμού εισιτηρίου.'
      : 'Μετά από αυτό δεν βρίσκονται πια με αναζήτηση του αριθμού '
            'εισιτηρίου.';
  return 'Η οριστική διαγραφή σβήνει και το ιστορικό σύνδεσης με το '
      'Lansweeper — $subject. $result';
}

String? _lansweeperLine({
  required int externalLinks,
  required List<String> ticketIds,
}) {
  if (externalLinks <= 0) return null;
  if (ticketIds.isEmpty) {
    final records = externalLinks == 1
        ? '1 εγγραφή ιστορικού'
        : '$externalLinks εγγραφές ιστορικού';
    return 'Lansweeper — $records χωρίς αριθμό εισιτηρίου';
  }
  final named = ticketIds.length == 1
      ? 'εισιτήριο ${ticketIds.single}'
      : 'εισιτήρια ${_namedTickets(ticketIds)}';
  // Το πλήθος εγγραφών μπαίνει μόνο όταν διαφέρει από το πλήθος εισιτηρίων:
  // αλλιώς επαναλαμβάνει την ίδια πληροφορία με άλλα λόγια.
  if (externalLinks == ticketIds.length) return 'Lansweeper — $named';
  return 'Lansweeper — $named ($externalLinks εγγραφές ιστορικού)';
}

/// `5067` ή `5067, 5102 κ.ά.` — χωρίς παρενθέσεις, τις βάζει ο καλών.
String _namedTickets(List<String> ticketIds) {
  if (ticketIds.length <= _maxNamedTickets) return ticketIds.join(', ');
  return '${ticketIds.take(_maxNamedTickets).join(', ')} κ.ά.';
}
