import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ο φάκελος με τις εικόνες της οθόνης εκκίνησης.
const String kSplashAssetFolder = 'assets/splash/';

/// Χρωματικές εναλλαγές που παίζουν όταν δεν υπάρχει διαθέσιμη εικόνα.
///
/// Δεν είναι δεύτερη κατηγορία: μια εικόνα που λείπει ή δεν αποκωδικοποιείται
/// δεν είναι λόγος να μην ανοίξει η εφαρμογή, και μια μαύρη οθόνη θα έμοιαζε
/// με κόλλημα. Το χρώμα κοστίζει μηδέν byte και δεν αποτυγχάνει ποτέ.
const List<List<Color>> kSplashFallbackGradients = <List<Color>>[
  [Color(0xFF2B1240), Color(0xFF7A2C55), Color(0xFFD4623F)],
  [Color(0xFF061A33), Color(0xFF0D3A63), Color(0xFF1C6F96)],
  [Color(0xFF0A2018), Color(0xFF17452F), Color(0xFF3D7D4F)],
  [Color(0xFF1B0B30), Color(0xFF45228A), Color(0xFF7F67BE)],
  [Color(0xFF23120A), Color(0xFF6B3418), Color(0xFFA95F2C)],
  [Color(0xFF05061A), Color(0xFF221151), Color(0xFF5B2A7A)],
];

/// Τι θα ζωγραφιστεί πίσω από τα βήματα της εκκίνησης.
@immutable
class SplashArtwork {
  const SplashArtwork.image(this.assetPath)
    : gradientColors = null,
      warning = null;

  const SplashArtwork.gradient(this.gradientColors, {this.warning})
    : assetPath = null;

  /// Διαδρομή asset, όταν βρέθηκε εικόνα.
  final String? assetPath;

  /// Χρώματα εφεδρείας, όταν δεν βρέθηκε.
  final List<Color>? gradientColors;

  /// Γιατί έπεσε στην εφεδρεία — γίνεται γραμμή προειδοποίησης στο ημερολόγιο.
  final String? warning;

  bool get isImage => assetPath != null;
}

/// Διαλέγει τι θα δείξει η οθόνη εκκίνησης αυτή τη φορά.
///
/// Οι εικόνες διαβάζονται από το μανιφέστο των assets αντί για καρφωτή λίστα:
/// έτσι μια νέα εικόνα στον φάκελο μπαίνει στην περιστροφή μόνη της, χωρίς
/// αλλαγή κώδικα και χωρίς αριθμό που ξεχνιέται ενημερωμένος.
class SplashArtworkPicker {
  const SplashArtworkPicker({this.bundle, this.random});

  /// Πηγή των assets· `null` σημαίνει το πακέτο της εφαρμογής.
  final AssetBundle? bundle;

  /// Γεννήτρια τυχαιότητας· `null` σημαίνει καινούργια σε κάθε επιλογή.
  final Random? random;

  /// Η εικόνα που έπαιξε την προηγούμενη φορά — για να μην τύχει δύο φορές
  /// στη σειρά η ίδια μέσα στην ίδια συνεδρία.
  static String? _lastAssetPath;

  @visibleForTesting
  static void resetLastPick() => _lastAssetPath = null;

  Future<SplashArtwork> pick() async {
    final rng = random ?? Random();
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(
        bundle ?? rootBundle,
      );
      final candidates =
          manifest
              .listAssets()
              .where(
                (a) =>
                    a.startsWith(kSplashAssetFolder) &&
                    !a.split('/').last.startsWith('_'),
              )
              .toList()
            ..sort();

      if (candidates.isEmpty) {
        return SplashArtwork.gradient(
          _randomGradient(rng),
          warning: 'Δεν βρέθηκε καμία εικόνα εκκίνησης.',
        );
      }

      final choice = _pickAvoidingRepeat(candidates, rng);
      _lastAssetPath = choice;
      return SplashArtwork.image(choice);
    } catch (e) {
      return SplashArtwork.gradient(
        _randomGradient(rng),
        warning: 'Οι εικόνες εκκίνησης δεν διαβάστηκαν: $e',
      );
    }
  }

  String _pickAvoidingRepeat(List<String> candidates, Random random) {
    if (candidates.length == 1) return candidates.first;
    final pool = candidates.where((a) => a != _lastAssetPath).toList();
    return pool[random.nextInt(pool.length)];
  }

  List<Color> _randomGradient(Random random) =>
      kSplashFallbackGradients[random.nextInt(kSplashFallbackGradients.length)];
}
