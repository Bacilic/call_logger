/// Τύπος αναγνωρισμένου συνδέσμου μέσα σε ελεύθερο κείμενο.
enum LinkableTextKind { url, uncPath, localPath }

/// Ένα τμήμα κειμένου: απλό ή σύνδεσμος.
sealed class LinkableTextSegment {
  const LinkableTextSegment();
}

final class PlainLinkableTextSegment extends LinkableTextSegment {
  const PlainLinkableTextSegment(this.text);

  final String text;
}

final class LinkLinkableTextSegment extends LinkableTextSegment {
  const LinkLinkableTextSegment(this.text, this.kind);

  final String text;
  final LinkableTextKind kind;
}

/// Αναλύει κείμενο σε τμήματα με αυτόματη αναγνώριση URL, UNC και τοπικών διαδρομών Windows.
abstract final class LinkableTextParser {
  static const _trailingPunctuation = '.,;:!?)»"\'';

  /// Χαρακτήρες που ανοίγουν και κλείνουν παράθεση γύρω από διαδρομή. Το
  /// «Αντιγραφή ως διαδρομή» των Windows βάζει διπλά εισαγωγικά, οπότε το
  /// ζεύγος τους είναι το ασφαλέστερο όριο για διαδρομή με κενά.
  static const _openQuotes = '"\'«“';
  static const _closeQuotes = '"\'»”';

  /// Η αρχή κάθε διαδρομής: `\\διακομιστής` ή `E:\`.
  static const _pathPrefix = r'(?:\\\\|[A-Za-z]:\\)';

  /// Ενδιάμεσο τμήμα διαδρομής. Τα κενά επιτρέπονται επειδή το lookahead
  /// εγγυάται ότι ακολουθεί κι άλλη ανάποδη κάθετος: το τμήμα δεν είναι το
  /// τελευταίο, άρα δεν μπορεί να καταπιεί το κείμενο που έπεται.
  static const _innerSegment = r'[^\s\\]+(?: +[^\s\\]+)*(?=\\)';

  /// Τελευταίο τμήμα χωρίς κενά — σταματά στην πρώτη λέξη της πρόζας.
  static const _plainSegment = r'[^\s\\]+';

  /// Τελευταίο τμήμα με κενά: γίνεται δεκτό μόνο όταν κλείνει σε κατάληξη
  /// αρχείου, το μόνο σημάδι ότι εκεί τελειώνει η διαδρομή.
  static const _fileSegment = r'[^\s\\]+(?: +[^\s\\]+){0,4}\.[A-Za-z0-9]{1,8}';

  /// Ιστορικό τελευταίο τμήμα τοπικής διαδρομής: λατινικοί χαρακτήρες με κενά.
  static const _latinSegment = r'[A-Za-z0-9 .\-()+#&_]+';

  /// https/http, UNC (`\\server\share`) και τοπικές διαδρομές (`E:\...`).
  /// Οι διαδρομές αναγνωρίζονται με τρεις κανόνες, κατά σειρά: μέσα σε
  /// εισαγωγικά παίρνονται ολόκληρες, ενδιάμεσα τμήματα κρατούν τα κενά τους
  /// και το τελευταίο τμήμα κρατά κενά μόνο όταν καταλήγει σε αρχείο.
  static final RegExp _pattern = RegExp(
    r'https?://[^\s<>\[\](),]+'
    '|'
    '(?<=[$_openQuotes])$_pathPrefix[^$_closeQuotes\\n]+(?=[$_closeQuotes])'
    '|'
    '\\\\\\\\(?:$_innerSegment\\\\)*(?:$_fileSegment|$_plainSegment)'
    '|'
    '[A-Za-z]:\\\\(?:$_innerSegment\\\\)*'
    '(?:$_fileSegment|$_latinSegment|$_plainSegment)',
  );

  static List<LinkableTextSegment> parse(String input) {
    if (input.isEmpty) return const [];

    final segments = <LinkableTextSegment>[];
    var cursor = 0;

    for (final match in _pattern.allMatches(input)) {
      if (match.start > cursor) {
        segments.add(
          PlainLinkableTextSegment(input.substring(cursor, match.start)),
        );
      }

      final raw = match.group(0)!;
      final kind = _kindForMatch(raw);
      final normalized = _normalizeMatch(raw, kind);
      if (normalized.isNotEmpty) {
        segments.add(LinkLinkableTextSegment(normalized, kind));
      }
      cursor = match.start + _consumedLength(raw, kind);
    }

    if (cursor < input.length) {
      segments.add(PlainLinkableTextSegment(input.substring(cursor)));
    }

    return segments;
  }

  static LinkableTextKind _kindForMatch(String raw) {
    final trimmed = raw.trimLeft();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return LinkableTextKind.url;
    }
    if (trimmed.startsWith(r'\\')) {
      return LinkableTextKind.uncPath;
    }
    return LinkableTextKind.localPath;
  }

  static int _consumedLength(String raw, LinkableTextKind kind) {
    if (kind == LinkableTextKind.url) {
      return raw.length;
    }
    return raw.trimRight().length;
  }

  static String _normalizeMatch(String raw, LinkableTextKind kind) {
    var value = raw.trim();
    while (value.isNotEmpty &&
        _trailingPunctuation.contains(value[value.length - 1])) {
      value = value.substring(0, value.length - 1);
    }
    if (kind == LinkableTextKind.url) {
      return value;
    }
    return value.replaceAll('/', r'\').trimRight();
  }
}
