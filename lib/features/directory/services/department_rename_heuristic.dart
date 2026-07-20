/// Κρίνει αν η μαζική μεταφορά σε νέο τμήμα μοιάζει με μετονομασία
/// (και όχι με πραγματική διάλυση/συγχώνευση).
bool looksLikeDepartmentRename({
  required int movedTotal,
  required int movedToDominantTarget,
  required bool dominantTargetIsNew,
  double threshold = 0.4,
}) {
  if (!dominantTargetIsNew) return false;
  if (movedTotal <= 0) return false;
  return movedToDominantTarget / movedTotal > threshold;
}
