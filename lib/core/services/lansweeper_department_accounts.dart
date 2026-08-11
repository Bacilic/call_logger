import 'dart:convert';

import 'lansweeper_ticket_requester_fields.dart';

/// Ένας λογαριασμός Lansweeper όπως τον γράφει ο χρήστης στο τμήμα:
/// «Υπάλληλος Βιοχημικού #1 = gnk\bio1».
///
/// Η [label] ζει **μόνο** μέσα στην εφαρμογή, για να ξεχωρίζει ο χρήστης ποιον
/// διαλέγει· στο Lansweeper φεύγει αποκλειστικά το [username]. Το API δεν
/// επιστρέφει ονόματα χρηστών, οπότε η ετικέτα δεν μπορεί να προκύψει αλλιώς.
class LansweeperAccount {
  const LansweeperAccount({required this.username, this.label = ''});

  final String username;
  final String label;

  /// Τι βλέπει ο χρήστης: η ετικέτα όταν υπάρχει, αλλιώς το αναγνωριστικό.
  String get displayLabel => label.isEmpty ? username : '$label — $username';

  Map<String, String> toJson() => {
    'username': username,
    if (label.isNotEmpty) 'label': label,
  };

  /// Η μορφή που πληκτρολογεί και βλέπει ο χρήστης στο πεδίο του τμήματος.
  String toInputText() => label.isEmpty ? username : '$label = $username';

  @override
  bool operator ==(Object other) =>
      other is LansweeperAccount &&
      other.username == username &&
      other.label == label;

  @override
  int get hashCode => Object.hash(username, label);
}

/// Χωρίζει ένα ζεύγος «ετικέτα = αναγνωριστικό» στα δύο του μέρη.
///
/// Χωρίς `=` δοκιμάζεται και το ξεχασμένο ίσον: όταν η τελευταία λέξη είναι
/// από μόνη της έγκυρη ταυτότητα («Γραφείο Λοιμώξεων gnk\loimokseis1»), τα
/// προηγούμενα γίνονται ονομασία. Αλλιώς ολόκληρο το κείμενο μένει
/// αναγνωριστικό — δεν μαντεύουμε, ο χρήστης θα δει προειδοποίηση.
///
/// Επιστρέφει `null` όταν δεν μένει αναγνωριστικό.
LansweeperAccount? parseLansweeperAccount(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final separator = text.indexOf('=');
  if (separator >= 0) {
    final label = text.substring(0, separator).trim();
    final username = text.substring(separator + 1).trim();
    if (username.isEmpty) return null;
    return LansweeperAccount(username: username, label: label);
  }

  final lastSpace = text.lastIndexOf(RegExp(r'\s'));
  if (lastSpace > 0) {
    final tail = text.substring(lastSpace + 1).trim();
    if (tail.isNotEmpty && !lansweeperAgentValueLooksLikeDisplayName(tail)) {
      return LansweeperAccount(
        username: tail,
        label: text.substring(0, lastSpace).trim(),
      );
    }
  }
  return LansweeperAccount(username: text);
}

// Η παλιά συγκεντρωτική προειδοποίηση (lansweeperAccountsWarning)
// αντικαταστάθηκε 12/08/2026 από τη στοχευμένη διάγνωση ανά λογαριασμό
// (lansweeper_identity_diagnosis.dart) — κάθε chip κουβαλά το δικό του λάθος.

/// Τα ζεύγη που πληκτρολόγησε ο χρήστης, χωρισμένα με κόμμα.
///
/// Διπλά αναγνωριστικά αγνοούνται — δύο ίδιοι λογαριασμοί στο ίδιο τμήμα δεν
/// προσφέρουν επιλογή, μόνο σύγχυση στον επιλογέα.
List<LansweeperAccount> parseLansweeperAccountsInput(String raw) {
  final out = <LansweeperAccount>[];
  final seen = <String>{};
  for (final part in raw.split(',')) {
    final account = parseLansweeperAccount(part);
    if (account == null) continue;
    if (!seen.add(account.username.toLowerCase())) continue;
    out.add(account);
  }
  return out;
}

/// Αποκωδικοποιεί τα αποθηκευμένα ζεύγη. Ανθεκτικό σε ό,τι βρει: παλιό απλό
/// κείμενο με κόμματα διαβάζεται κι αυτό, ώστε μια χειροκίνητη εγγραφή στη
/// βάση να μη χάνεται σιωπηλά.
List<LansweeperAccount> decodeLansweeperAccounts(String? stored) {
  final raw = stored?.trim() ?? '';
  if (raw.isEmpty) return const [];

  if (raw.startsWith('[')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final out = <LansweeperAccount>[];
        final seen = <String>{};
        for (final item in decoded) {
          if (item is! Map) continue;
          final username = (item['username'] ?? '').toString().trim();
          if (username.isEmpty) continue;
          if (!seen.add(username.toLowerCase())) continue;
          out.add(
            LansweeperAccount(
              username: username,
              label: (item['label'] ?? '').toString().trim(),
            ),
          );
        }
        return out;
      }
    } catch (_) {
      // Χαλασμένο JSON: πέφτουμε στην ανάγνωση με κόμματα παρακάτω.
    }
  }
  return parseLansweeperAccountsInput(raw);
}

/// Κωδικοποιεί για αποθήκευση. Κενή λίστα → `null`, ώστε η στήλη να αδειάζει
/// πραγματικά αντί να κρατά «[]».
String? encodeLansweeperAccounts(List<LansweeperAccount> accounts) {
  if (accounts.isEmpty) return null;
  return jsonEncode(accounts.map((a) => a.toJson()).toList());
}
