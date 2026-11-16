// Η σελίδα μιας συσκευής στο Lansweeper: τι δέχεται το πεδίο του αριθμού, και
// πώς χτίζεται η διεύθυνση από τον διακομιστή του URL προβολής ticket.
//
//   flutter test test/core/services/lansweeper_asset_page_test.dart

import 'package:call_logger/core/services/lansweeper_asset_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLansweeperAssetId', () {
    test('η επικολλημένη διεύθυνση δίνει μόνο τον αριθμό', () {
      expect(
        parseLansweeperAssetId(
          'http://10.10.201.22:81/asset.aspx?AssetID=1084',
        ),
        (id: 1084, error: null),
      );
      expect(parseLansweeperAssetId('asset.aspx?assetid=603&tab=1').id, 603);
    });

    test('σκέτος αριθμός, με κενά γύρω, περνά', () {
      expect(parseLansweeperAssetId(' 1084 '), (id: 1084, error: null));
    });

    test('κενό = καμία σελίδα, χωρίς μήνυμα', () {
      expect(parseLansweeperAssetId('   '), (id: null, error: null));
    });

    test('όνομα μηχανήματος ή μηδέν βγάζουν μήνυμα', () {
      expect(parseLansweeperAssetId('AP5087').error, kLansweeperAssetIdError);
      expect(parseLansweeperAssetId('0').error, kLansweeperAssetIdError);
      expect(
        parseLansweeperAssetId('http://10.10.201.22:81/asset.aspx').error,
        kLansweeperAssetIdError,
      );
    });
  });

  group('lansweeperAssetPageUrl', () {
    test('ίδιος διακομιστής και θύρα με το URL προβολής ticket', () {
      expect(
        lansweeperAssetPageUrl(
          'http://10.10.201.22:81/helpdesk/ticket.aspx?tid={tid}',
          1084,
        ),
        'http://10.10.201.22:81/asset.aspx?AssetID=1084',
      );
    });

    test('εγκατάσταση σε υποφάκελο: κρατιέται ό,τι είναι πριν το helpdesk', () {
      expect(
        lansweeperAssetPageUrl(
          'https://it.hospital.example/lansweeper/helpdesk/ticket.aspx?tid=',
          7,
        ),
        'https://it.hospital.example/lansweeper/asset.aspx?AssetID=7',
      );
    });

    test('χωρίς σωστή διεύθυνση διακομιστή δεν βγαίνει σύνδεσμος', () {
      expect(lansweeperAssetPageUrl('', 1084), isNull);
      expect(lansweeperAssetPageUrl('ticket.aspx?tid={tid}', 1084), isNull);
    });
  });
}
