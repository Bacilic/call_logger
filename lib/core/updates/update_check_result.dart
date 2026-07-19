import 'update_manifest.dart';

/// Αποτέλεσμα ελέγχου διαθέσιμης ενημέρωσης.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.updateAvailable,
    this.latestVersion,
    this.manifest,
  });

  const UpdateCheckResult.none()
      : updateAvailable = false,
        latestVersion = null,
        manifest = null;

  final bool updateAvailable;
  final String? latestVersion;
  final UpdateManifest? manifest;
}
