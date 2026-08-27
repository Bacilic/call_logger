import '../../models/managed_server.dart';
import 'server_session_models.dart';

/// Από πού προέκυψε ο διακομιστής που θα ρωτήσουμε.
enum ServerTargetOrigin {
  /// Από τη διεύθυνση που έχει ο ίδιος ο εξοπλισμός στην «Απομακρυσμένη».
  fromEquipment,

  /// Ο εξοπλισμός δεν έδειχνε τίποτα — πέσαμε στον προεπιλεγμένο.
  fallbackNoAddress,

  /// Ο εξοπλισμός έδειχνε κάτι, αλλά δεν είναι καταχωρημένος διακομιστής.
  fallbackUnknownAddress,

  /// Δεν υπάρχει κανένας καταχωρημένος διακομιστής.
  none,
}

/// Ο διακομιστής που προτείνεται, μαζί με το **γιατί**.
///
/// Το «γιατί» δεν είναι διακοσμητικό: ο χειριστής πρέπει να βλέπει αν ρωτάμε
/// τον διακομιστή του εξοπλισμού ή απλώς τον προεπιλεγμένο, γιατί στη δεύτερη
/// περίπτωση η λίστα συνεδριών μπορεί να μην έχει καμία σχέση μαζί του.
class ServerTargetChoice {
  const ServerTargetChoice({
    required this.server,
    required this.origin,
    required this.equipmentAddress,
  });

  final ManagedServer? server;
  final ServerTargetOrigin origin;

  /// Ό,τι ακριβώς είχε ο εξοπλισμός στην «Απομακρυσμένη» (για το μήνυμα).
  final String equipmentAddress;

  /// Επεξήγηση κάτω από τον επιλογέα διακομιστή.
  String get explanation => switch (origin) {
    ServerTargetOrigin.fromEquipment =>
      'Η διεύθυνση αυτού του εξοπλισμού δείχνει εδώ.',
    ServerTargetOrigin.fallbackNoAddress =>
      'Ο εξοπλισμός δεν έχει καταχωρημένη απομακρυσμένη διεύθυνση — '
          'προτείνεται ο προεπιλεγμένος διακομιστής.',
    ServerTargetOrigin.fallbackUnknownAddress =>
      'Η διεύθυνση του εξοπλισμού («$equipmentAddress») δεν είναι '
          'καταχωρημένος διακομιστής — προτείνεται ο προεπιλεγμένος.',
    ServerTargetOrigin.none => 'Δεν υπάρχει καταχωρημένος διακομιστής.',
  };
}

/// Μία συνεδρία μαζί με ό,τι ξέρουμε γι' αυτήν σε σχέση με τον εξοπλισμό.
class LogoffCandidate {
  const LogoffCandidate({
    required this.session,
    required this.matchesEquipment,
    required this.isAdminAccount,
  });

  final ServerSession session;

  /// Η συνεδρία άνοιξε από τον σταθμό αυτού του εξοπλισμού.
  final bool matchesEquipment;

  /// Είναι η συνεδρία του ίδιου του λογαριασμού διαχειριστή που χρησιμοποιούμε.
  ///
  /// Ο τερματισμός της κόβει το κλαδί που κάθεται ο χειριστής — και πιθανότατα
  /// πετάει έξω συνάδελφο που δουλεύει εκείνη τη στιγμή στον διακομιστή.
  final bool isAdminAccount;
}

/// Τι προτείνουμε στον χειριστή μόλις απαντήσει ο διακομιστής.
class LogoffSessionPlan {
  const LogoffSessionPlan({
    required this.candidates,
    required this.preselectedSessionId,
    required this.matchCount,
  });

  final List<LogoffCandidate> candidates;

  /// Η συνεδρία που έρχεται προεπιλεγμένη — `null` όταν δεν προτείνουμε καμία.
  final int? preselectedSessionId;

  /// Πόσες συνεδρίες ήρθαν από τον σταθμό αυτού του εξοπλισμού.
  final int matchCount;

  /// Δύο ή περισσότερες συνεδρίες από τον ίδιο σταθμό: ο χειριστής πρέπει να
  /// διαλέξει ρητά.
  bool get needsExplicitChoice => matchCount > 1;
}

/// Επιλογή διακομιστή και πρότασης συνεδρίας — καθαρές συναρτήσεις.
abstract final class LogoffTargetResolution {
  LogoffTargetResolution._();

  /// Ποιον διακομιστή ρωτάμε για αυτόν τον εξοπλισμό.
  ///
  /// Σειρά: η διεύθυνση του εξοπλισμού αν αντιστοιχεί σε καταχωρημένο
  /// διακομιστή, αλλιώς ο προεπιλεγμένος, αλλιώς ο πρώτος της λίστας.
  ///
  /// **Δεν** εφευρίσκουμε διακομιστή από άγνωστη διεύθυνση: το πεδίο της
  /// «Απομακρυσμένης» είναι ελεύθερο κείμενο και μπορεί κάλλιστα να κρατά όνομα
  /// απλού σταθμού (π.χ. `PC3698`). Ένα «τυφλό» ταξίδι εκεί θα ζητούσε
  /// τερματισμό συνεδρίας σε υπολογιστή γραφείου.
  static ServerTargetChoice resolveServer({
    required String equipmentRemoteAddress,
    required List<ManagedServer> servers,
  }) {
    final address = equipmentRemoteAddress.trim();

    if (servers.isEmpty) {
      return ServerTargetChoice(
        server: null,
        origin: ServerTargetOrigin.none,
        equipmentAddress: address,
      );
    }

    final fallback = servers.firstWhere(
      (s) => s.isDefault,
      orElse: () => servers.first,
    );

    if (address.isEmpty) {
      return ServerTargetChoice(
        server: fallback,
        origin: ServerTargetOrigin.fallbackNoAddress,
        equipmentAddress: address,
      );
    }

    final lower = address.toLowerCase();
    for (final s in servers) {
      if (s.host.trim().toLowerCase() == lower) {
        return ServerTargetChoice(
          server: s,
          origin: ServerTargetOrigin.fromEquipment,
          equipmentAddress: address,
        );
      }
    }

    return ServerTargetChoice(
      server: fallback,
      origin: ServerTargetOrigin.fallbackUnknownAddress,
      equipmentAddress: address,
    );
  }

  /// Ταξινόμηση και πρόταση συνεδρίας με βάση το όνομα σταθμού.
  ///
  /// [equipmentStationName] έρχεται έτοιμο από τον καλούντα (π.χ. `PC3414`),
  /// υπολογισμένο με τον **ίδιο** κανόνα που χρησιμοποιεί το VNC — ώστε να μην
  /// υπάρχουν δύο ορισμοί του «ποιο PC είναι ο εξοπλισμός 3414».
  ///
  /// Όταν ταιριάζουν **δύο ή περισσότερες** συνεδρίες, δεν προεπιλέγεται
  /// καμία: ένας σταθμός μπορεί κάλλιστα να κρατά δύο συνεδρίες στον
  /// διακομιστή (επιβεβαιωμένο στον .82), και το αυτόματο μάντεμα θα έκλεινε
  /// λάθος.
  static LogoffSessionPlan buildPlan({
    required List<ServerSession> sessions,
    required String equipmentStationName,
    required String adminUser,
  }) {
    final station = equipmentStationName.trim().toLowerCase();
    final admin = adminUser.trim().toLowerCase();

    final candidates = <LogoffCandidate>[];
    for (final s in sessions) {
      if (!s.isLogoffCandidate) continue;
      final matches =
          station.isNotEmpty && s.stationName.trim().toLowerCase() == station;
      candidates.add(
        LogoffCandidate(
          session: s,
          matchesEquipment: matches,
          isAdminAccount:
              admin.isNotEmpty && s.username.trim().toLowerCase() == admin,
        ),
      );
    }

    candidates.sort(_compareCandidates);

    final matched = candidates.where((c) => c.matchesEquipment).toList();
    final preselected = matched.length == 1
        ? matched.first.session.sessionId
        : null;

    return LogoffSessionPlan(
      candidates: candidates,
      preselectedSessionId: preselected,
      matchCount: matched.length,
    );
  }

  /// Πρώτα όσες ταιριάζουν με τον εξοπλισμό, μετά οι ενεργές, μετά αλφαβητικά.
  static int _compareCandidates(LogoffCandidate a, LogoffCandidate b) {
    if (a.matchesEquipment != b.matchesEquipment) {
      return a.matchesEquipment ? -1 : 1;
    }
    final aActive = a.session.state == ServerSessionState.active;
    final bActive = b.session.state == ServerSessionState.active;
    if (aActive != bActive) return aActive ? -1 : 1;
    final byName = a.session.username.toLowerCase().compareTo(
      b.session.username.toLowerCase(),
    );
    if (byName != 0) return byName;
    return a.session.sessionId.compareTo(b.session.sessionId);
  }
}
