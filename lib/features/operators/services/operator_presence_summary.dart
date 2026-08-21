import 'package:intl/intl.dart';

import '../../../core/models/operator_presence.dart';

/// Μία γραμμή σύνδεσης, έτοιμη για την κάρτα του χρήστη.
class OperatorPresenceLine {
  const OperatorPresenceLine({required this.online, required this.text});

  /// Το ίχνος είναι φρέσκο — δείχνεται ως «τώρα».
  final bool online;

  final String text;
}

final DateFormat _stamp = DateFormat('dd/MM/yyyy HH:mm');

/// Μεταφράζει τα ίχνη σύνδεσης σε ό,τι διαβάζει ο άνθρωπος στην κάρτα.
///
/// **Καθαρή συνάρτηση με ρητό [now]:** ο κανόνας «τι θεωρείται τώρα» ελέγχεται
/// χωρίς οθόνη, και η οθόνη δεν αποκτά δεύτερο ρολόι.
///
/// Οι κανόνες, με τη σειρά:
/// 1. **Κανένα ίχνος** → δεν έχει συνδεθεί ποτέ. Δεν είναι σφάλμα: το προφίλ
///    μπορεί να φτιάχτηκε από τον διαχειριστή και να μην το έχει πατήσει κανείς.
/// 2. **Υπάρχει φρέσκο ίχνος** → όλοι οι σταθμοί που είναι αυτή τη στιγμή
///    ανοιχτοί, γιατί το ίδιο προφίλ μπορεί να δουλεύει από δύο θέσεις.
/// 3. **Μόνο παλιά ίχνη** → μόνο το πιο πρόσφατο. Το «πού ήταν πριν από έναν
///    μήνα» δεν ενδιαφέρει κανέναν και θα γέμιζε την κάρτα.
List<OperatorPresenceLine> describeOperatorPresence(
  List<OperatorPresence> marks,
  DateTime now,
) {
  if (marks.isEmpty) {
    return const [
      OperatorPresenceLine(online: false, text: 'Δεν έχει συνδεθεί ποτέ'),
    ];
  }

  final sorted = [...marks]
    ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
  final online = sorted.where((mark) => mark.isOnlineAt(now)).toList();

  if (online.isNotEmpty) {
    return [
      for (final mark in online)
        OperatorPresenceLine(
          online: true,
          text: 'Συνδεδεμένος τώρα — ${mark.station}',
        ),
    ];
  }

  final last = sorted.first;
  return [
    OperatorPresenceLine(
      online: false,
      text:
          'Τελευταία σύνδεση ${_stamp.format(last.lastSeenAt)} — '
          '${last.station}',
    ),
  ];
}
