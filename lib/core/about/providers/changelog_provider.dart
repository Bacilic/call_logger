import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/changelog_entry.dart';
import '../services/changelog_service.dart';

final changelogProvider = FutureProvider<List<ChangelogEntry>>((ref) async {
  return ChangelogService().load();
});
