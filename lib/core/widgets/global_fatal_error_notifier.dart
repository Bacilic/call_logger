import 'package:flutter/foundation.dart';

import '../database/database_init_result.dart';

/// Κατάσταση πλήρους οθόνης σφάλματος από global handlers ([main] / zone / platform).
final ValueNotifier<DatabaseInitResult?> globalFatalErrorNotifier =
    ValueNotifier<DatabaseInitResult?>(null);
