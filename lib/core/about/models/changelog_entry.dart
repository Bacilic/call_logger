/// Εγγραφή ιστορικού αλλαγών (changelog) ανά έκδοση.
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.added,
    required this.changed,
    required this.fixed,
  });

  final String version;

  /// ISO 8601 ημερομηνία (yyyy-MM-dd).
  final String date;
  final List<String> added;
  final List<String> changed;
  final List<String> fixed;

  factory ChangelogEntry.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) {
      final raw = json[key];
      if (raw == null) return [];
      if (raw is List) {
        return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
      return [];
    }

    return ChangelogEntry(
      version: json['version']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      added: strings('added'),
      changed: strings('changed'),
      fixed: strings('fixed'),
    );
  }
}
