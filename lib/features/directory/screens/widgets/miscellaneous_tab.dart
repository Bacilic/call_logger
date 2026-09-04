import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_asset_image.dart';
import '../../providers/remote_tools_view_intent_provider.dart';
import '../../../operators/screens/operators_management_view.dart';
import '../../../settings/screens/remote_tools_management_screen.dart';
import 'categories_tab.dart';
import 'departments_settings_view.dart';
import 'servers_management_view.dart';
import 'validation_rules_view.dart';

enum MiscView {
  dashboard,
  categories,
  remoteTools,
  validationRules,
  operators,
  servers,
  departments,
}

/// Καρτέλα «Διάφορα»: κεντρικό hub με πλοήγηση σε υπο-οθόνες.
class MiscellaneousTab extends ConsumerStatefulWidget {
  const MiscellaneousTab({super.key});

  @override
  ConsumerState<MiscellaneousTab> createState() => _MiscellaneousTabState();
}

class _MiscellaneousTabState extends ConsumerState<MiscellaneousTab> {
  MiscView _view = MiscView.dashboard;

  /// Αφετηρία των αιτημάτων μετάβασης: ό,τι ζητήθηκε πριν χτιστεί η καρτέλα
  /// δεν είναι δικό της αίτημα.
  late int _remoteToolsRequestBaseline;

  @override
  void initState() {
    super.initState();
    _remoteToolsRequestBaseline = ref.read(remoteToolsViewRequestProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(remoteToolsViewRequestProvider, (previous, next) {
      if (next <= _remoteToolsRequestBaseline) return;
      _remoteToolsRequestBaseline = next;
      setState(() => _view = MiscView.remoteTools);
    });

    if (_view == MiscView.dashboard) {
      return _buildDashboard(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_view == MiscView.categories ||
            _view == MiscView.validationRules ||
            _view == MiscView.operators ||
            _view == MiscView.servers ||
            _view == MiscView.departments)
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
              onBackToDashboard: () =>
                  setState(() => _view = MiscView.dashboard),
            ),
            MiscView.validationRules => const ValidationRulesView(),
            MiscView.operators => const OperatorsManagementView(),
            MiscView.servers => const ServersManagementView(),
            MiscView.departments => const DepartmentsSettingsView(),
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
              SizedBox(
                width: cardWidth.clamp(280.0, 520.0),
                child: _HubNavCard(
                  title: 'Τμήματα',
                  assetPath: 'assets/departments_settings.png',
                  fallbackIcon: Icons.apartment_outlined,
                  onTap: () => setState(() => _view = MiscView.departments),
                ),
              ),
              SizedBox(
                width: cardWidth.clamp(280.0, 520.0),
                child: _HubNavCard(
                  title: 'Κανόνες Επικύρωσης',
                  assetPath: 'assets/validation_rules.png',
                  onTap: () => setState(() => _view = MiscView.validationRules),
                ),
              ),
              SizedBox(
                width: cardWidth.clamp(280.0, 520.0),
                child: _HubNavCard(
                  title: 'Χρήστες',
                  assetPath: 'assets/app_users.png',
                  fallbackIcon: Icons.manage_accounts_outlined,
                  onTap: () => setState(() => _view = MiscView.operators),
                ),
              ),
              SizedBox(
                width: cardWidth.clamp(280.0, 520.0),
                child: _HubNavCard(
                  title: 'Διακομιστές',
                  assetPath: 'assets/servers.png',
                  fallbackIcon: Icons.dns_outlined,
                  onTap: () => setState(() => _view = MiscView.servers),
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
    this.fallbackIcon = Icons.image_outlined,
  });

  final String title;
  final String assetPath;
  final VoidCallback onTap;

  /// Δείχνεται όταν λείπει η εικόνα — ώστε η κάρτα να μη μένει κενή μέχρι να
  /// φτιαχτεί το εικαστικό.
  final IconData fallbackIcon;

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
                  AppAssetImage(
                    assetPath: widget.assetPath,
                    width: 72,
                    height: 72,
                    filterQuality: FilterQuality.medium,
                    fallbackIcon: widget.fallbackIcon,
                    fallbackSize: 56,
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
