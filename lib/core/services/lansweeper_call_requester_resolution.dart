import '../database/user_repository.dart';
import '../../features/calls/models/call_model.dart';
import 'lansweeper_party_requester_resolution.dart';
import 'lansweeper_requester_resolution.dart';
import 'lookup_service.dart';

/// Ποιος μπαίνει αιτών στο ticket για τις δοσμένες κλήσεις.
///
/// Μεταφράζει τις κλήσεις σε πρόσωπα-και-τμήματα και αφήνει την **ίδια**
/// ιεραρχία να αποφασίσει. Η λογική δεν ζει εδώ επίτηδες: μόλις μια δεύτερη
/// οντότητα (η εκκρεμότητα) χρειάστηκε τον ίδιο αιτούντα, μια δεύτερη
/// υλοποίηση θα απέκλινε από αυτήν μέσα σε λίγες αλλαγές.
///
/// Η σειρά των [calls] μετράει: πρώτη η κύρια κλήση του ticket.
Future<LansweeperRequesterOptions> resolveLansweeperRequesterForCalls({
  required UserRepository userRepository,
  required LookupService lookup,
  required List<CallModel> calls,
}) {
  return resolveLansweeperRequesterForParties(
    userRepository: userRepository,
    lookup: lookup,
    parties: [
      for (final call in calls)
        LansweeperRequesterParty(
          personId: call.callerId,
          personLabel: _callerLabel(call),
          departmentText: call.departmentText ?? '',
        ),
    ],
  );
}

/// Πώς αναγνωρίζει ο χρήστης τον καλούντα στον επιλογέα αιτούντα.
///
/// Η εφεδρεία («Καλών #42») είναι γλώσσα **της κλήσης** και γι' αυτό φτιάχνεται
/// εδώ: η εκκρεμότητα λέει τα ίδια πράγματα με άλλα λόγια, και ο κοινός
/// πυρήνας δεν έχει λόγο να ξέρει ποια από τις δύο τον κάλεσε.
String _callerLabel(CallModel call) {
  final displayName = (call.callerText ?? '').trim();
  return displayName.isEmpty ? 'Καλών #${call.callerId}' : displayName;
}
