import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calls/provider/lookup_provider.dart';
import 'department_directory_provider.dart';
import 'directory_provider.dart';
import 'equipment_directory_provider.dart';

/// Ανανέωση lookup cache και sibling καταλόγων μετά από mutation.
Future<void> refreshDirectoryCaches(
  Ref ref, {
  bool users = false,
  bool equipment = false,
  bool departments = false,
}) async {
  ref.invalidate(lookupServiceProvider);
  await ref.read(lookupServiceProvider.future);
  if (!ref.mounted) return;
  if (users) {
    await ref.read(directoryProvider.notifier).loadUsers();
    if (!ref.mounted) return;
  }
  if (equipment) {
    await ref.read(equipmentDirectoryProvider.notifier).load();
    if (!ref.mounted) return;
  }
  if (departments) {
    await ref.read(departmentDirectoryProvider.notifier).loadDepartments();
  }
}
