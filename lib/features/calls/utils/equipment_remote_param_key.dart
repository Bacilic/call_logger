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
}
