import 'package:flutter/material.dart';

import 'widgets/users_tab.dart';

/// Οθόνη Κατάλογου: TabBar Χρήστες | Εξοπλισμός.
class DirectoryScreen extends StatelessWidget {
  const DirectoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const SizedBox.shrink(),
          toolbarHeight: 0,
          titleSpacing: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Χρήστες'),
              Tab(text: 'Εξοπλισμός'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            UsersTab(),
            _EquipmentPlaceholder(),
          ],
        ),
      ),
    );
  }
}

class _EquipmentPlaceholder extends StatelessWidget {
  const _EquipmentPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Εξοπλισμός – σύντομα',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}
