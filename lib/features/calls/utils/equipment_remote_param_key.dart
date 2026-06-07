/// Βοηθητικά για κλειδιά στο [EquipmentModel.remoteParams] (μόνο `<tool_id>`).
abstract final class EquipmentRemoteParamKey {
  EquipmentRemoteParamKey._();

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
