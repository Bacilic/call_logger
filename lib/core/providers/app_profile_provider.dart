import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// CLI προφίλ (`--profile`), null στην κανονική παραγωγική εκτέλεση.
final activeProfileProvider = Provider<String?>(
  (ref) => AppConfig.activeProfile,
);

/// True όταν η εφαρμογή τρέχει με απομονωμένο προφίλ δοκιμών.
final hasActiveProfileProvider = Provider<bool>(
  (ref) => AppConfig.hasActiveProfile,
);
