import 'package:flutter/services.dart';

import '../config/app_config.dart';

/// Λίστα bundled `.txt` από το AssetManifest (προαιρετικά — χωρίς crash αν λείπουν).
Future<List<String>> listBundledDictionaryAssets() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final prefix = AppConfig.bundledDictionariesAssetPrefix;
  final assets = manifest
      .listAssets()
      .where(
        (a) =>
            a.startsWith(prefix) &&
            a.toLowerCase().endsWith('.txt'),
      )
      .toList()
    ..sort();
  return assets;
}
