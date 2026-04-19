/// Κανονικοποίηση ετικέτας εργαλείου (ρυθμίσεις) → κλειδί στο [EquipmentModel.remoteParams].
abstract final class EquipmentRemoteParamKey {
  EquipmentRemoteParamKey._();

  static const String anydesk = 'anydesk';
  static const String vnc = 'vnc';
  static const String rdp = 'rdp';

  static String forToolLabel(String label) {
    final lower = label.trim().toLowerCase();
    if (lower.contains('anydesk')) return anydesk;
    if (lower.contains('vnc')) return vnc;
    if (lower.contains('rdp') ||
        lower.contains('remote desktop') ||
        lower.contains('απομακρυσμένη επιφάνεια')) {
      return rdp;
    }
    final slug = lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? label.trim().toLowerCase() : slug;
  }

  /// Πρόθεμα για τιμή παραμέτρου που **δεν** είναι ενεργή (chip off) στη φόρμα εξοπλισμού·
  /// παραμένει στο JSON ώστε να επανέρχεται με re-enable χωρίς να θεωρείται ενεργός στόχος.
  static const String remoteParamStashPrefix = '__stash_';

  static String remoteParamStashKeyFor(String paramKey) =>
      '$remoteParamStashPrefix$paramKey';

  static bool isRemoteParamStashKey(String key) =>
      key.startsWith(remoteParamStashPrefix);

  static String? remoteParamStashRealKeyOrNull(String key) {
    if (!isRemoteParamStashKey(key)) return null;
    final rest = key.substring(remoteParamStashPrefix.length);
    return rest.isEmpty ? null : rest;
  }
}
