import 'dart:io';

import 'package:call_logger/features/database/debug/publish_cli.dart';

/// Λεπτό σημείο εισόδου: δημοσίευση έκδοσης από τερματικό.
///
/// Παράδειγμα:
/// `dart run tool/publish.dart --bump=patch --folder="\\server\share\updates"`
Future<void> main(List<String> arguments) async {
  exit(await publishCliMain(arguments));
}
