import 'package:flutter/material.dart';

import '../../../settings/screens/remote_tools_management_screen.dart';
import 'categories_tab.dart';

enum MiscView { dashboard, categories, remoteTools }

/// Καρτέλα «Διάφορα»: κεντρικό hub με πλοήγηση σε υπο-οθόνες.
class MiscellaneousTab extends StatefulWidget {
  const MiscellaneousTab({super.key});

  @override
  State<MiscellaneousTab> createState() => _MiscellaneousTabState();
}

class _MiscellaneousTabState extends State<MiscellaneousTab> {
  MiscView _view = MiscView.dashboard;

  @override
  Widget build(BuildContext context) {
    if (_view == MiscView.dashboard) {
      return _buildDashboard(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_view == MiscView.categories)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Επιστροφή στο hub',
                  onPressed: () => setState(() => _view = MiscView.dashboard),
                ),
                Text(
                  'Επιστροφή',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        Expanded(
          child: switch (_view) {
            MiscView.categories => const CategoriesView(),
            MiscView.remoteTools => RemoteToolsManagementScreen(
              embedded: true,
              onBackToDashboard: () => setState(() => _view = MiscView.dashboard),
            ),
            MiscView.dashboard => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }

  Widget _buildDashboard(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cardWidth = maxW > 900 ? (maxW - 48) / 2 : maxW - 32;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: cardWidth.clamp(280.0, 520.0),
                child: _HubNavCard(
                  title: 'Κατηγορίες Προβλήματος',
                  assetPath: 'assets/problem_category.png',
                  onTap: () => setState(() => _view = MiscView.categories),
                ),
              ),
              SizedBox(
                width: cardWidth.clamp(280.0, 520.0),
                child: _HubNavCard(
                  title: 'Απομακρυσμένα Εργαλεία',
                  assetPath: 'assets/remote_tools.png',
                  onTap: () => setState(() => _view = MiscView.remoteTools),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HubNavCard extends StatefulWidget {
  const _HubNavCard({
    required this.title,
    required this.assetPath,
    required this.onTap,
  });

  final String title;
  final String assetPath;
  final VoidCallback onTap;

  @override
  State<_HubNavCard> createState() => _HubNavCardState();
}

class _HubNavCardState extends State<_HubNavCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerLow;
    final hoverSurface = theme.colorScheme.surfaceContainerHigh;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: _hover ? 10 : 2,
          shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.35),
          color: _hover ? hoverSurface : base,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Row(
                children: [
                  Image.asset(
                    widget.assetPath,
                    width: 72,
                    height: 72,
                    filterQuality: FilterQuality.medium,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
