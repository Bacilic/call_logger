/// Αμετάβλητο μοντέλο για το `version.json` του φακέλου ενημερώσεων.
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.build,
    required this.released,
    required this.zipFile,
    required this.sha256,
  });

  final String version;
  final int build;
  final String released;
  final String zipFile;
  final String sha256;

  /// Ανθεκτική ανάλυση· επιστρέφει null σε ελλιπή/λάθος πεδία (όχι crash).
  static UpdateManifest? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(raw);
      final version = (map['version'] as String?)?.trim() ?? '';
      final released = (map['released'] as String?)?.trim() ?? '';
      final zipFile = (map['zipFile'] as String?)?.trim() ?? '';
      final sha256 = (map['sha256'] as String?)?.trim() ?? '';
      final buildRaw = map['build'];
      final int? build = switch (buildRaw) {
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v.trim()),
        _ => null,
      };
      if (version.isEmpty ||
          build == null ||
          build < 0 ||
          released.isEmpty ||
          zipFile.isEmpty ||
          sha256.isEmpty) {
        return null;
      }
      if (_parseSemVer(version) == null) return null;
      return UpdateManifest(
        version: version,
        build: build,
        released: released,
        zipFile: zipFile,
        sha256: sha256,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'build': build,
    'released': released,
    'zipFile': zipFile,
    'sha256': sha256,
  };

  /// Σύγκριση «ποιο πακέτο είναι νεότερο» — αποφασίζει το BUILD, όχι η ετικέτα.
  ///
  /// Το build αυξάνεται κατά 1 σε κάθε δημοσίευση και δεν μηδενίζει ποτέ, άρα
  /// επιβιώνει και από αναπροσαρμογή της αρίθμησης εκδόσεων (π.χ. η γραμμή
  /// γύρισε από 0.24.x σε 0.22.0). Αν αποφάσιζε η ετικέτα, ξεχασμένη
  /// εγκατάσταση με «μπροστινό» αριθμό έκδοσης θα θεωρούσε για πάντα τον
  /// εαυτό της νεότερο και δεν θα αυτοενημερωνόταν ποτέ. Η ετικέτα `X.Y.Z`
  /// χρησιμεύει μόνο ως δεύτερο κριτήριο σε ίσα builds (αμυντικό — κανονικά
  /// κάθε δημοσίευση έχει μοναδικό build).
  ///
  /// Αρνητικό αν A < B, 0 αν ίσα, θετικό αν A > B.
  static int compareVersions({
    required String versionA,
    required int buildA,
    required String versionB,
    required int buildB,
  }) {
    if (buildA != buildB) return buildA.compareTo(buildB);
    return compareVersionLabels(versionA, versionB);
  }

  /// Αριθμητική σύγκριση ΜΟΝΟ της ετικέτας `X.Y.Z` — για την ένδειξη προς τον
  /// χρήστη (π.χ. «η νέα έκδοση φαίνεται μικρότερη λόγω αναπροσαρμογής»),
  /// ΟΧΙ για την απόφαση ενημέρωσης.
  static int compareVersionLabels(String versionA, String versionB) {
    final a = _parseSemVer(versionA) ?? const (0, 0, 0);
    final b = _parseSemVer(versionB) ?? const (0, 0, 0);
    if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
    if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
    return a.$3.compareTo(b.$3);
  }

  static (int, int, int)? _parseSemVer(String raw) {
    final core = raw.trim().split(RegExp(r'[-+]')).first;
    final parts = core.split('.');
    if (parts.length != 3) return null;
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);
    if (major == null || minor == null || patch == null) return null;
    return (major, minor, patch);
  }
}
