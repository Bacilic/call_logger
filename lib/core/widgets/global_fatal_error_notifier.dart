import 'package:flutter/foundation.dart';

import '../errors/fatal_error_routing.dart';

/// Κατάσταση πλήρους οθόνης σφάλματος από global handlers ([main] / zone /
/// platform).
///
/// Κρατά **τι είδους** σφάλμα συνέβη, όχι μόνο το κείμενό του: το κέλυφος
/// διαλέγει από εδώ ποια οθόνη θα δείξει, και μια χαλασμένη βάση αξίζει τις
/// διεξόδους της αντί για ένα σκέτο «Επαναδοκιμή».
final ValueNotifier<FatalErrorState?> globalFatalErrorNotifier =
    ValueNotifier<FatalErrorState?>(null);
