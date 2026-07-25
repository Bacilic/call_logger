import 'package:call_logger/core/utils/bundled_dictionary_assets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingAssetBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) {
    throw Exception('Unable to load asset: $key');
  }
}

void main() {
  test(
    'listBundledDictionaryAssets με bundle που πετάει → κενή λίστα χωρίς εξαίρεση',
    () async {
      final assets = await listBundledDictionaryAssets(
        bundle: _ThrowingAssetBundle(),
      );

      expect(assets, isEmpty);
      expect(assets, equals(const <String>[]));
    },
  );
}
