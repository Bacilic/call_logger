/// Τύπος αναγνωρισμένου συνδέσμου μέσα σε ελεύθερο κείμενο.
enum LinkableTextKind {
  url,
  uncPath,
  localPath,
}

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

  /// https/http, UNC (`\\server\share`) και τοπικές διαδρομές (`E:\...`).
  static final RegExp _pattern = RegExp(
    r'https?://[^\s<>\[\](),]+'
    r'|'
    r'\\\\[^\s\\]+(?:\\[^\s\\]+)*'
    r'|'
    r'[A-Za-z]:\\(?:[A-Za-z0-9 .\-()+#&_]+(?:\\[A-Za-z0-9 .\-()+#&_]+)*)',
  );

  static List<LinkableTextSegment> parse(String input) {
    if (input.isEmpty) return const [];

    final segments = <LinkableTextSegment>[];
    var cursor = 0;

    for (final match in _pattern.allMatches(input)) {
      if (match.start > cursor) {
        segments.add(PlainLinkableTextSegment(input.substring(cursor, match.start)));
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
    while (value.isNotEmpty && _trailingPunctuation.contains(value[value.length - 1])) {
      value = value.substring(0, value.length - 1);
    }
    if (kind == LinkableTextKind.url) {
      return value;
    }
    return value.replaceAll('/', r'\').trimRight();
  }
}
