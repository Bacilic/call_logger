// Πότε προσφέρεται αναβάθμιση σε χρήστη που κόλλησε σε «βάση νεότερης έκδοσης».
//
// Καθαρή λογική, χωρίς διεπαφή: η απόφαση «αξίζει να το προτείνουμε;»
// κρίνεται με αριθμούς — αν η αναβάθμιση δεν αλλάζει τίποτα, δεν προσφέρεται.
//
//   flutter test test/core/updates/app_upgrade_offer_test.dart

import 'package:call_logger/core/updates/app_upgrade_offer.dart';
import 'package:call_logger/core/updates/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UpdateManifest manifest({
    String version = '0.30.0',
    int build = 300,
    int? schemaVersion,
  }) => UpdateManifest(
    version: version,
    build: build,
    released: '2026-08-25',
    zipFile: 'call_logger_$version($build).zip',
    sha256: 'abc',
    schemaVersion: schemaVersion,
  );

  test('χωρίς πακέτο στον φάκελο ενημερώσεων δεν προσφέρεται τίποτα', () {
    final offer = evaluateAppUpgradeOffer(
      manifest: null,
      currentVersion: '0.29.0',
      currentBuild: 290,
      fileSchemaVersion: 54,
    );

    expect(offer, isNull);
  });

  test('πακέτο ίδιου build δεν προσφέρεται — δεν θα άλλαζε τίποτα', () {
    final offer = evaluateAppUpgradeOffer(
      manifest: manifest(version: '0.29.0', build: 290, schemaVersion: 54),
      currentVersion: '0.29.0',
      currentBuild: 290,
      fileSchemaVersion: 54,
    );

    expect(offer, isNull);
  });

  test('παλαιότερο πακέτο δεν προσφέρεται', () {
    final offer = evaluateAppUpgradeOffer(
      manifest: manifest(version: '0.28.0', build: 280, schemaVersion: 54),
      currentVersion: '0.29.0',
      currentBuild: 290,
      fileSchemaVersion: 54,
    );

    expect(offer, isNull);
  });

  test('νεότερο πακέτο που φτάνει την έκδοση της βάσης: βέβαιη λύση', () {
    final offer = evaluateAppUpgradeOffer(
      manifest: manifest(build: 300, schemaVersion: 54),
      currentVersion: '0.29.0',
      currentBuild: 290,
      fileSchemaVersion: 54,
    );

    expect(offer, isNotNull);
    expect(offer!.confidence, AppUpgradeConfidence.resolvesForSure);
    expect(offer.version, '0.30.0');
  });

  test('νεότερο πακέτο που ΔΕΝ φτάνει τη βάση δεν προσφέρεται', () {
    final offer = evaluateAppUpgradeOffer(
      manifest: manifest(build: 300, schemaVersion: 50),
      currentVersion: '0.29.0',
      currentBuild: 290,
      fileSchemaVersion: 54,
    );

    expect(offer, isNull);
  });

  test('νεότερο πακέτο χωρίς δηλωμένη έκδοση βάσης: πιθανή λύση', () {
    final offer = evaluateAppUpgradeOffer(
      manifest: manifest(build: 300),
      currentVersion: '0.29.0',
      currentBuild: 290,
      fileSchemaVersion: 54,
    );

    expect(offer, isNotNull);
    expect(offer!.confidence, AppUpgradeConfidence.likelyResolves);
  });

  test('άγνωστη έκδοση αρχείου: το πακέτο κρίνεται μόνο ως νεότερο', () {
    final offer = evaluateAppUpgradeOffer(
      manifest: manifest(build: 300, schemaVersion: 50),
      currentVersion: '0.29.0',
      currentBuild: 290,
      fileSchemaVersion: 0,
    );

    expect(offer, isNotNull);
    expect(offer!.confidence, AppUpgradeConfidence.likelyResolves);
  });
}
