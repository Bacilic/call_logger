/// Αναζήτηση με `LIKE` που ψάχνει **κατά λέξη** ό,τι έγραψε ο χρήστης.
///
/// Στο `LIKE` της SQLite το `%` σημαίνει «οτιδήποτε» και το `_` «ένας
/// οποιοσδήποτε χαρακτήρας». Χωρίς διαφυγή, το «50%» ψάχνει «50 και ό,τι
/// ακολουθεί» — δηλαδή κάθε κλήση με «50» μέσα της (τηλέφωνο 2250, εξοπλισμός
/// 5062…) — και το σκέτο «%» φέρνει τα πάντα, χωρίς καμία ένδειξη.
///
/// Κάθε `LIKE` με τιμή από τον χρήστη γράφεται ως [op] με όρισμα από τα
/// [contains] / [startsWith] / [endsWith] / [exact]: τα δύο πάνε πάντα μαζί,
/// γιατί η διαφυγή χωρίς το `ESCAPE` της SQL δεν ισχύει.
abstract final class SqlLike {
  /// Ο τελεστής, με τη δήλωση του χαρακτήρα διαφυγής.
  static const String op = r"LIKE ? ESCAPE '\'";

  /// Εξουδετερώνει τους μπαλαντέρ του `LIKE` μέσα στο [text].
  static String escape(String text) => text
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  /// «περιέχει» το [text].
  static String contains(String text) => '%${escape(text)}%';

  /// «ξεκινά με» το [text].
  static String startsWith(String text) => '${escape(text)}%';

  /// «τελειώνει σε» το [text].
  static String endsWith(String text) => '%${escape(text)}';

  /// Ακριβώς το [text] — για συνδυασμούς όπως «λέξη ανάμεσα σε κενά».
  static String exact(String text) => escape(text);
}
