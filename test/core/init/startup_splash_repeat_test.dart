// Η εικόνα εκκίνησης δεν επαναλαμβάνεται δύο φορές στη σειρά.
//
// Η μνήμη πρέπει να επιζεί του κλεισίματος: η οθόνη εμφανίζεται μία φορά ανά
// άνοιγμα, οπότε «θυμάμαι μέσα στη συνεδρία» σημαίνει «δεν θυμάμαι ποτέ».
//
//   flutter test test/core/init/startup_splash_repeat_test.dart

import 'dart:math';

import 'package:call_logger/core/init/startup_splash_artwork.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _images = [
  'assets/splash/splash-1.webp',
  'assets/splash/splash-2.webp',
  'assets/splash/splash-3.webp',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('η επιλογή αποφεύγει την προηγούμενη', () {
    test('με πολλές εικόνες, η προηγούμενη ΔΕΝ ξαναβγαίνει ποτέ', () {
      final rng = Random(7);
      for (var i = 0; i < 500; i++) {
        final choice = SplashArtworkPicker.pickAvoidingRepeat(
          candidates: _images,
          previous: _images[1],
          random: rng,
        );
        expect(choice, isNot(_images[1]));
      }
    });

    test('χωρίς προηγούμενη, όλες είναι υποψήφιες', () {
      final rng = Random(3);
      final seen = <String>{};
      for (var i = 0; i < 200; i++) {
        seen.add(
          SplashArtworkPicker.pickAvoidingRepeat(
            candidates: _images,
            previous: null,
            random: rng,
          ),
        );
      }
      expect(seen, hasLength(_images.length));
    });

    test('με μία μόνο εικόνα παίζει αυτή, όσο κι αν επαναλαμβάνεται', () {
      final choice = SplashArtworkPicker.pickAvoidingRepeat(
        candidates: const ['assets/splash/μόνη.webp'],
        previous: 'assets/splash/μόνη.webp',
        random: Random(1),
      );

      expect(
        choice,
        'assets/splash/μόνη.webp',
        reason: 'Καλύτερα επανάληψη παρά μαύρη οθόνη.',
      );
    });

    test('άγνωστη προηγούμενη δεν αδειάζει τη δεξαμενή', () {
      final choice = SplashArtworkPicker.pickAvoidingRepeat(
        candidates: _images,
        previous: 'assets/splash/έχει-διαγραφεί.webp',
        random: Random(5),
      );

      expect(_images, contains(choice));
    });
  });

  group('η μνήμη επιζεί του κλεισίματος', () {
    test('η επιλογή καταγράφεται και τιμάται στο επόμενο άνοιγμα', () async {
      String? stored;
      final bundle = _FakeSplashBundle(_images);

      // Πρώτο «άνοιγμα»: γράφει ό,τι διάλεξε.
      final first = await SplashArtworkPicker(
        bundle: bundle,
        random: Random(11),
        readLastAsset: () async => stored,
        writeLastAsset: (a) async => stored = a,
      ).pick();

      expect(first.isImage, isTrue);
      expect(stored, first.assetPath);

      // Κάθε επόμενο «άνοιγμα» είναι νέο αντικείμενο, όπως νέα διεργασία.
      var previous = first.assetPath;
      for (var i = 0; i < 30; i++) {
        final next = await SplashArtworkPicker(
          bundle: bundle,
          random: Random(i),
          readLastAsset: () async => stored,
          writeLastAsset: (a) async => stored = a,
        ).pick();

        expect(
          next.assetPath,
          isNot(previous),
          reason:
              'Η εικόνα του προηγούμενου ανοίγματος δεν επιτρέπεται να '
              'ξαναπαίξει αμέσως — αυτό ακριβώς έβλεπε ο χρήστης.',
        );
        expect(stored, next.assetPath, reason: 'η μνήμη μένει ενημερωμένη');
        previous = next.assetPath;
      }
    });

    test('αποτυχία ανάγνωσης μνήμης δεν εμποδίζει την εκκίνηση', () async {
      final artwork = await SplashArtworkPicker(
        bundle: _FakeSplashBundle(_images),
        random: Random(2),
        readLastAsset: () async => throw StateError('χαλασμένες ρυθμίσεις'),
        writeLastAsset: (_) async {},
      ).pick();

      expect(artwork.isImage, isTrue);
    });

    test('αποτυχία εγγραφής μνήμης δεν εμποδίζει την εκκίνηση', () async {
      final artwork = await SplashArtworkPicker(
        bundle: _FakeSplashBundle(_images),
        random: Random(2),
        readLastAsset: () async => null,
        writeLastAsset: (_) async => throw StateError('δίσκος γεμάτος'),
      ).pick();

      expect(artwork.isImage, isTrue);
    });
  });
}

/// Δέσμη assets με μανιφέστο που περιέχει μόνο τις [images].
class _FakeSplashBundle extends CachingAssetBundle {
  _FakeSplashBundle(this.images);

  final List<String> images;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final entries = <String, Object?>{
        for (final image in images) image: <Object?>[],
      };
      final data = const StandardMessageCodec().encodeMessage(entries);
      if (data == null) throw FlutterError('κενό μανιφέστο');
      return data;
    }
    throw FlutterError('δεν χρειάζεται: $key');
  }
}
