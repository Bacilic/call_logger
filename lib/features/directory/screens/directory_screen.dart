import 'package:flutter/material.dart';

import 'widgets/categories_tab.dart';
import 'widgets/departments_tab.dart';
import 'widgets/equipment_tab.dart';
import 'widgets/users_tab.dart';

/// Δείκτης καρτέλας «Διάφορα» στον Κατάλογο (0-based).
const int kDirectoryCategoriesTabIndex = 3;

/// Οθόνη Κατάλογου: TabBar Χρήστες | Τμήματα | Εξοπλισμός | Διάφορα.
class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onDirectoryTabChanged);
  }

  /// Φεύγοντας από «Διάφορα», το SnackBar (π.χ. αναίρεση διαγραφής) κλείνει ως επιβεβαίωση.
  void _onDirectoryTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index != kDirectoryCategoriesTabIndex) {
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onDirectoryTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(
          title: const SizedBox.shrink(),
          toolbarHeight: 0,
          titleSpacing: 0,
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Χρήστες'),
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
            CategoriesTab(),
          ],
        ),
      ),
    );
  }
}
