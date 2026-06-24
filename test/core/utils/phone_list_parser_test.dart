import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoneListParser.activeSegmentBounds', () {
    test('ολόκληρο κείμενο χωρίς κόμμα', () {
      const text = '2377';
      final b = PhoneListParser.activeSegmentBounds(text, 4);
      expect(b.start, 0);
      expect(b.end, 4);
      expect(b.segmentIn(text), '2377');
    });

    test('δεύτερο τμήμα μετά από κόμμα', () {
      const text = '2377, 25';
      final b = PhoneListParser.activeSegmentBounds(text, text.length);
      expect(b.segmentIn(text), '25');
    });

    test('κέρσορας στο πρώτο τμήμα', () {
      const text = '2377, 2577';
      final b = PhoneListParser.activeSegmentBounds(text, 2);
      expect(b.segmentIn(text), '2377');
    });
  });

  group('PhoneListParser.replaceActiveSegment', () {
    test('αντικατάσταση στο τέλος προσθέτει κόμμα', () {
      const text = '2377, 2';
      final r = PhoneListParser.replaceActiveSegment(
        text: text,
        cursor: text.length,
        replacement: '2577',
      );
      expect(r.text, '2377, 2577, ');
      expect(r.cursor, r.text.length);
    });

    test('αντικατάσταση στη μέση δεν προσθέτει κόμμα', () {
      const text = '25, 30';
      final r = PhoneListParser.replaceActiveSegment(
        text: text,
        cursor: 2,
        replacement: '2577',
      );
      expect(r.text, '2577, 30');
    });
  });

  group('PhoneListParser.autocompletePhonesForSegment', () {
    const all = ['1234', '22345', '9923', '500'];

    test('κενό ή σύντομο query', () {
      expect(
        PhoneListParser.autocompletePhonesForSegment(
          allKnownPhones: all,
          segmentQuery: '2',
        ),
        isEmpty,
      );
    });

    test('περιέχει ψηφία σε όλα τα τηλέφωνα βάσης', () {
      final matches = PhoneListParser.autocompletePhonesForSegment(
        allKnownPhones: all,
        segmentQuery: '23',
      ).toList();
      expect(matches, containsAll(['1234', '22345', '9923']));
      expect(matches, isNot(contains('500')));
    });
  });
}
