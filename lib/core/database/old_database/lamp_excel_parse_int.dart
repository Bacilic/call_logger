/// Ανάλυση ακεραίου από κείμενο κελιού της Λάμπας: «12», «12.0» → 12· κενό ή «-» → null.
int? lampParseExcelInt(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  if (normalized.isEmpty || normalized == '-') return null;
  return int.tryParse(normalized) ??
      (double.tryParse(normalized)?.truncate() == double.tryParse(normalized)
          ? double.tryParse(normalized)?.toInt()
          : null);
}
