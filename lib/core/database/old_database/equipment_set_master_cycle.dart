/// Εντοπίζει codes που συμμετέχουν σε κύκλο `set_master` (A→B→…→A).
Set<int> findEquipmentSetMasterCycleRoots(Map<int, int> masterByCode) {
  final cycleRoots = <int>{};
  for (final root in masterByCode.keys) {
    final seen = <int>{};
    var current = root;
    while (true) {
      if (!seen.add(current)) break;
      final next = masterByCode[current];
      if (next == null) break;
      if (next == root) {
        cycleRoots.add(root);
        break;
      }
      current = next;
    }
  }
  return cycleRoots;
}
