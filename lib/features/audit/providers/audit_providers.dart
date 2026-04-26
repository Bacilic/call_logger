import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../models/audit_filter_model.dart';
import '../models/audit_log_model.dart';
import '../models/audit_page_result.dart';
import '../services/audit_entity_preview_resolver.dart';
import '../services/audit_formatter_service.dart';

final auditFormatterServiceProvider = Provider<AuditFormatterService>(
  (ref) => const AuditFormatterService(),
);

final auditServiceAsyncProvider = FutureProvider<AuditService>((ref) async {
  final db = await DatabaseHelper.instance.database;
  return AuditService(db);
});

final auditFilterProvider =
    NotifierProvider<AuditFilterNotifier, AuditFilterModel>(
  AuditFilterNotifier.new,
);

class AuditFilterNotifier extends Notifier<AuditFilterModel> {
  @override
  AuditFilterModel build() => const AuditFilterModel();

  void update(AuditFilterModel Function(AuditFilterModel) fn) {
    state = fn(state);
  }
}

final auditPageIndexProvider =
    NotifierProvider<AuditPageIndexNotifier, int>(AuditPageIndexNotifier.new);

class AuditPageIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setPage(int i) => state = i < 0 ? 0 : i;

  void reset() => state = 0;
}

const int kAuditPageSize = 50;

final auditListProvider =
    FutureProvider.autoDispose<AuditPageResult>((ref) async {
  final filter = ref.watch(auditFilterProvider);
  final page = ref.watch(auditPageIndexProvider);
  final svc = await ref.watch(auditServiceAsyncProvider.future);
  final kw = SearchTextNormalizer.normalizeForSearch(filter.keyword.trim());
  final result = await svc.queryPage(
    offset: page * kAuditPageSize,
    limit: kAuditPageSize,
    keywordNormalized: kw.isEmpty ? null : kw,
    action: filter.action,
    entityType: filter.entityType,
    dateFromInclusiveIso: filter.dateFromInclusiveIso,
    dateToExclusiveIso: filter.dateToExclusiveIso,
  );
  final items =
      result.rows.map((m) => AuditLogModel.fromMap(m)).toList();
  return AuditPageResult(items: items, totalCount: result.total);
});

/// Διαθέσιμες ενέργειες για dropdown φίλτρου, βάσει τρέχοντος τύπου οντότητας.
final auditActionOptionsProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final filter = ref.watch(auditFilterProvider);
  final svc = await ref.watch(auditServiceAsyncProvider.future);
  return svc.queryDistinctActions(
    entityType: filter.entityType,
    dateFromInclusiveIso: filter.dateFromInclusiveIso,
    dateToExclusiveIso: filter.dateToExclusiveIso,
  );
});

final selectedAuditEntryIdProvider =
    NotifierProvider<SelectedAuditEntryNotifier, int?>(
  SelectedAuditEntryNotifier.new,
);

class SelectedAuditEntryNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? id) => state = id;
}

/// Εμφάνιση δεξιού side panel (προεπισκόπηση οντότητας).
class AuditSidePanelOpenNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setOpen(bool value) => state = value;

  void toggle() => state = !state;
}

final auditSidePanelOpenProvider =
    NotifierProvider<AuditSidePanelOpenNotifier, bool>(
  AuditSidePanelOpenNotifier.new,
);

/// Προεπισκόπηση οντότητας για επιλεγμένη γραμμή (lazy + cache ανά id).
final auditEntityPreviewProvider = FutureProvider.autoDispose.family<
    AuditEntityPreview?,
    ({int auditId, String? entityType, int? entityId})>(
  (ref, key) async {
    if (key.entityType == null ||
        key.entityType!.trim().isEmpty ||
        key.entityId == null) {
      return null;
    }
    final db = await DatabaseHelper.instance.database;
    final resolver = AuditEntityPreviewResolver(db);
    return resolver.resolve(
      entityType: key.entityType!,
      entityId: key.entityId!,
    );
  },
);
