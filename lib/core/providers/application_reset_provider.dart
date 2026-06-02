import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';

/// True όταν τρέχει «Ξεκίνα από την αρχή» και περιμένουμε επιλογή/δημιουργία βάσης.
final applicationResetPendingProvider = FutureProvider<bool>((ref) async {
  return SettingsService().isApplicationResetPending();
});
