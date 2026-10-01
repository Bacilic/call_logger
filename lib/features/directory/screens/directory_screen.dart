import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/directory_tab_intent_provider.dart';
import '../providers/misc_dashboard_request_provider.dart';
import 'widgets/miscellaneous_tab.dart';
import 'widgets/departments_tab.dart';
import 'widgets/equipment_tab.dart';
import 'widgets/users_tab.dart';

/// Δείκτης καρτέλας «Διάφορα» στον Κατάλογο (0-based).
const int kDirectoryCategoriesTabIndex = 3;

/// Οθόνη Κατάλογου: TabBar Υπάλληλοι | Τμήματα | Εξοπλισμός | Διάφορα.
class DirectoryScreen extends ConsumerStatefulWidget {
  const DirectoryScreen({super.key});

  @override
  ConsumerState<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends ConsumerState<DirectoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Η καρτέλα όπου βρισκόταν ο χρήστης πριν από το τελευταίο πάτημα — για να
  /// ξεχωρίζει το «ξαναπάτησα την ίδια» από τη «μόλις ήρθα εδώ».
  int _settledIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onDirectoryTabChanged);
  }

  /// Φεύγοντας από «Διάφορα», το SnackBar (π.χ. αναίρεση διαγραφής) κλείνει ως επιβεβαίωση.
  void _onDirectoryTabChanged() {
    if (_tabController.indexIsChanging) return;
    _settledIndex = _tabController.index;
    if (_tabController.index != kDirectoryCategoriesTabIndex) {
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    }
  }

  /// Νέο πάτημα της ήδη ενεργής «Διάφορα» = επιστροφή στις κάρτες της, όπως
  /// οι άλλες καρτέλες φέρνουν πάντα στη δική τους οθόνη.
  void _onTabTapped(int index) {
    if (index != kDirectoryCategoriesTabIndex) return;
    if (_settledIndex != kDirectoryCategoriesTabIndex) return;
    ref.read(miscDashboardRequestProvider.notifier).request();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onDirectoryTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int?>(directoryTabIntentProvider, (previous, next) {
      if (next == null || !mounted) return;
      final i = next.clamp(0, 3);
      if (_tabController.index != i) {
        _tabController.animateTo(i);
      }
      ref.read(directoryTabIntentProvider.notifier).clear();
    });

    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(
          title: const SizedBox.shrink(),
          toolbarHeight: 0,
          titleSpacing: 0,
          bottom: TabBar(
            controller: _tabController,
            onTap: _onTabTapped,
            tabs: const [
              Tab(text: 'Υπάλληλοι'),
              Tab(text: 'Τμήματα'),
              Tab(text: 'Εξοπλισμός'),
              Tab(text: 'Διάφορα'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: const [
            UsersTab(),
            DepartmentsTab(),
            EquipmentTab(),
            MiscellaneousTab(),
          ],
        ),
      ),
    );
  }
}
