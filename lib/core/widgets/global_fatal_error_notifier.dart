import 'package:flutter/foundation.dart';

import '../errors/app_error_result.dart';

/// Κατάσταση πλήρους οθόνης σφάλματος από global handlers ([main] / zone / platform).
final ValueNotifier<AppErrorResult?> globalFatalErrorNotifier =
    ValueNotifier<AppErrorResult?>(null);
