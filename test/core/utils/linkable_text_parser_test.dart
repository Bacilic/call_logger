import 'package:call_logger/core/utils/linkable_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinkableTextParser', () {
    test('parses plain text only', () {
      final segments = LinkableTextParser.parse('Απλό κείμενο χωρίς συνδέσμους.');
      expect(segments, hasLength(1));
      expect(segments.single, isA<PlainLinkableTextSegment>());
      expect((segments.single as PlainLinkableTextSegment).text, 'Απλό κείμενο χωρίς συνδέσμους.');
    });

    test('parses https URL', () {
      final segments = LinkableTextParser.parse(
        'έγινε το αίτημα: https://tt.datamed.gr/Request/ViewTicket/57964',
      );
      expect(segments, hasLength(2));
      expect(segments[0], isA<PlainLinkableTextSegment>());
      expect(segments[1], isA<LinkLinkableTextSegment>());
      final link = segments[1] as LinkLinkableTextSegment;
      expect(link.kind, LinkableTextKind.url);
      expect(link.text, 'https://tt.datamed.gr/Request/ViewTicket/57964');
    });

    test('trims trailing punctuation from URL', () {
      final segments = LinkableTextParser.parse(
        'Δες το https://example.com/page.',
      );
      final link = segments.whereType<LinkLinkableTextSegment>().single;
      expect(link.text, 'https://example.com/page');
    });

    test('parses UNC path', () {
      final segments = LinkableTextParser.parse(r'Φάκελος: \\gnk.local\Departments');
      final link = segments.whereType<LinkLinkableTextSegment>().single;
      expect(link.kind, LinkableTextKind.uncPath);
      expect(link.text, r'\\gnk.local\Departments');
    });

    test('parses local path with spaces', () {
      final segments = LinkableTextParser.parse(r'Άνοιξε E:\Winget Update');
      final link = segments.whereType<LinkLinkableTextSegment>().single;
      expect(link.kind, LinkableTextKind.localPath);
      expect(link.text, r'E:\Winget Update');
    });

    test('does not include trailing prose in local path', () {
      final segments = LinkableTextParser.parse(r'Άνοιξε E:\Winget Update και δες');
      final link = segments.whereType<LinkLinkableTextSegment>().single;
      expect(link.text, r'E:\Winget Update');
      expect(segments.last, isA<PlainLinkableTextSegment>());
      expect((segments.last as PlainLinkableTextSegment).text, ' και δες');
    });

    test('parses multiple links in one line', () {
      final segments = LinkableTextParser.parse(
        'URL https://a.test/x και φάκελος E:\\Data',
      );
      final links = segments.whereType<LinkLinkableTextSegment>().toList();
      expect(links, hasLength(2));
      expect(links[0].kind, LinkableTextKind.url);
      expect(links[1].kind, LinkableTextKind.localPath);
      expect(links[1].text, r'E:\Data');
    });
  });
}
