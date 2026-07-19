import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../calls/provider/lookup_provider.dart';

/// Ανανέωση καρτέλας καταλόγου μετά από reload του [lookupServiceProvider],
/// χωρίς `ref.watch` κατά το `build` (αποφυγή race με `invalidate`).
mixin CatalogTabLookupReloadMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  ProviderSubscription<AsyncValue<LookupLoadResult>>? _catalogLookupReloadSub;

  void attachCatalogLookupReloadListener() {
    if (_catalogLookupReloadSub != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _catalogLookupReloadSub ??=
          ref.listenManual<AsyncValue<LookupLoadResult>>(
        lookupServiceProvider,
        (_, _) {
          if (mounted) setState(() {});
        },
      );
    });
  }

  void detachCatalogLookupReloadListener() {
    _catalogLookupReloadSub?.close();
    _catalogLookupReloadSub = null;
  }
}
