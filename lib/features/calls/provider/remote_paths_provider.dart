import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/services/remote_args_service.dart';
import '../../../core/services/remote_connection_service.dart';
import '../../../core/services/remote_launcher_service.dart';
import '../../../core/services/settings_service.dart';

/// Provider για το [RemoteArgsService].
final remoteArgsServiceProvider = Provider<RemoteArgsService>((ref) {
  return RemoteArgsService(DatabaseHelper.instance);
});

/// Επιστρέφει τις έγκυρες διαδρομές VNC και AnyDesk (null αν η ρυθμισμένη διαδρομή δεν υπάρχει).
/// Χρησιμοποιείται στην αρχική οθόνη κλήσεων για απενεργοποίηση κουμπιών και tooltip.
final validRemotePathsProvider = FutureProvider<({String? vncPath, String? anydeskPath})>((ref) async {
  final service = ref.read(remoteConnectionServiceProvider);
  final vncPath = await service.getValidVncPath();
  final anydeskPath = await service.getValidAnydeskPath();
  return (vncPath: vncPath, anydeskPath: anydeskPath);
});

/// Κατάσταση για τα κουμπιά εκκίνησης χωρίς παραμέτρους: διαδρομή + ακριβές μήνυμα σφάλματος όταν απενεργό.
typedef LauncherStatus = ({String? path, String? errorReason});

/// Επιστρέφει για AnyDesk και VNC την έγκυρη διαδρομή (αν υπάρχει) και το ακριβές μήνυμα σφάλματος όταν απενεργό.
final remoteLauncherStatusProvider = FutureProvider<({
  LauncherStatus anydesk,
  LauncherStatus vnc,
})>((ref) async {
  final launcher = ref.read(remoteLauncherServiceProvider);
  final anydesk = await launcher.getAnydeskStatus();
  final vnc = await launcher.getVncStatus();
  return (anydesk: anydesk, vnc: vnc);
});

/// Provider για το [RemoteConnectionService] (εκκίνηση VNC/AnyDesk).
final remoteConnectionServiceProvider = Provider<RemoteConnectionService>((ref) {
  return RemoteConnectionService(
    SettingsService(),
    ref.read(remoteArgsServiceProvider),
  );
});

/// Provider για το [RemoteLauncherService] (εκκίνηση χωρίς παραμέτρους).
final remoteLauncherServiceProvider = Provider<RemoteLauncherService>((ref) {
  return RemoteLauncherService(
    SettingsService(),
    ref.read(remoteArgsServiceProvider),
  );
});
