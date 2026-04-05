/// Δεν ορίστηκε έγκυρη διαδρομή εξαγωγής Compile (`dictionaryExportPath`).
class DictionaryExportPathMissingException implements Exception {
  DictionaryExportPathMissingException([this.message]);

  final String? message;

  @override
  String toString() =>
      message ?? 'DictionaryExportPathMissingException: κενή διαδρομή εξαγωγής';
}
