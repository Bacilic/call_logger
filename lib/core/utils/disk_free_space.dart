import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Ελεύθερος χώρος που μπορεί να χρησιμοποιήσει ο **τρέχων χρήστης** στον
/// τοπικό δίσκο όπου βρίσκεται το [path] — ή `null` όταν δεν μετριέται.
///
/// Ρωτά απευθείας τα Windows και **δεν θέλει δικαιώματα διαχειριστή**. Ως τις
/// 02/10/2026 η μέτρηση γινόταν με το `fsutil`, που τα θέλει: για απλό χρήστη
/// αποτύγχανε πάντα, και οι έλεγχοι χώρου απαντούσαν σιωπηλά «όλα καλά».
///
/// **Δίσκοι δικτύου δεν μετριούνται** (διαδρομή UNC ή γράμμα αντιστοιχισμένο
/// σε διακομιστή): η κλήση είναι σύγχρονη, και διακομιστής που δεν απαντά θα
/// πάγωνε την εφαρμογή χωρίς προθεσμία που να μπορεί να τη σταματήσει.
int? freeBytesOnLocalDrive(String path) {
  if (!Platform.isWindows) return null;
  final match = RegExp(r'^([A-Za-z]):').firstMatch(path.trim());
  if (match == null) return null;
  final rootPtr = '${match.group(1)!.toUpperCase()}:\\'.toPcwstr(
    allocator: calloc,
  );
  final freeForCaller = calloc<Uint64>();
  try {
    if (GetDriveType(rootPtr) == DRIVE_REMOTE) return null;
    final result = GetDiskFreeSpaceEx(rootPtr, freeForCaller, null, null);
    if (!result.value) return null;
    return freeForCaller.value;
  } finally {
    calloc.free(rootPtr);
    calloc.free(freeForCaller);
  }
}
