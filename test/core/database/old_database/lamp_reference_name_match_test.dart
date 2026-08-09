// Ταύτιση ωμής τιμής με το όνομα εγγραφής αναφοράς.
//
// Το ζεύγος που τη γέννησε είναι αληθινό: «30236» και η σύμβαση 231
// «30236 18/12/2024».
//
//   flutter test test/core/database/old_database/lamp_reference_name_match_test.dart

import 'package:call_logger/core/database/old_database/lamp_reference_name_match.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  LampNameMatchStrength? match(String raw, String? name) =>
      lampReferenceNameMatch(rawValue: raw, name: name);

  group('ταιριάζει', () {
    test('«30236» με «30236 18/12/2024»', () {
      expect(
        match('30236', '30236 18/12/2024'),
        LampNameMatchStrength.prefix,
        reason: greekExpectMsg(
          'Ο αριθμός πρωτοκόλλου στην αρχή του ονόματος είναι σχεδόν πάντα '
          'το ίδιο έγγραφο — αυτό έψαχνε ο χρήστης',
        ),
      );
    });

    test('ακριβές όνομα', () {
      expect(match('8006/8-6-2004', '8006/8-6-2004'),
          LampNameMatchStrength.exact);
    });

    test('η τιμή ως ολόκληρη λέξη μέσα στο όνομα', () {
      expect(
        match('17446', 'Σύμβαση 17446 προμήθειας'),
        LampNameMatchStrength.word,
      );
    });

    test('τόνοι και πεζά-κεφαλαία δεν εμποδίζουν', () {
      expect(match('ΔΩΡΕΑ', 'δωρεά'), LampNameMatchStrength.exact);
    });
  });

  group('δεν ταιριάζει', () {
    test('υποσύμβολο δεν είναι ταύτιση', () {
      expect(
        match('236', '30236 18/12/2024'),
        isNull,
        reason: greekExpectMsg(
          'Κάθε κοντός αριθμός θα κολλούσε σε τυχαίες συμβάσεις — η '
          'σύγκριση γίνεται σε ολόκληρες λέξεις',
        ),
      );
      expect(match('3023', '30236 18/12/2024'), isNull);
    });

    test('άσχετη τιμή', () {
      expect(match('99999', '30236 18/12/2024'), isNull);
    });

    test('κενά', () {
      expect(match('', '30236'), isNull);
      expect(match('30236', null), isNull);
      expect(match('30236', '   '), isNull);
    });
  });

  group('βαρύτητα', () {
    test('η ταύτιση ονόματος ξεπερνά τα συμφραζόμενα', () {
      // Στον αναλυτή τα συμφραζόμενα δίνουν το πολύ 55 + 25 + 30 χρήση.
      expect(
        LampNameMatchStrength.prefix.score,
        greaterThan(55 + 25),
        reason: greekExpectMsg(
          'Το ότι δύο μηχανήματα κάθονται στο ίδιο γραφείο δεν λέει τίποτα '
          'για τη σύμβασή τους· το όνομα λέει',
        ),
      );
    });

    test('ισχυρότερη ταύτιση, μεγαλύτερο βάρος', () {
      expect(
        LampNameMatchStrength.exact.score,
        greaterThan(LampNameMatchStrength.prefix.score),
      );
      expect(
        LampNameMatchStrength.prefix.score,
        greaterThan(LampNameMatchStrength.word.score),
      );
    });
  });
}
