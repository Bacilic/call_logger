import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/user_facing_error_messages.dart';
import '../../history/providers/history_provider.dart';
import '../models/knowledge_article.dart';
import '../providers/knowledge_provider.dart';
import '../widgets/knowledge_article_card.dart';
import '../widgets/knowledge_article_dialog.dart';

/// Η οθόνη της Βάσης Γνώσης: οι συνταγές που έχετε κρατήσει από τις κλήσεις.
class KnowledgeScreen extends ConsumerStatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  ConsumerState<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends ConsumerState<KnowledgeScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(knowledgeSearchProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openArticle([KnowledgeArticle? article]) async {
    await showKnowledgeArticleDialog(context, article: article);
  }

  Future<void> _deleteArticle(KnowledgeArticle article) async {
    final id = article.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Διαγραφή άρθρου'),
        content: Text(
          'Να διαγραφεί το «${article.title}»;\n\n'
          'Το περιεχόμενό του μένει στο Ιστορικό Εφαρμογής.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(knowledgeActionsProvider.notifier).delete(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Το άρθρο διαγράφηκε.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Αποτυχία διαγραφής: ${humanizeUserFacingError(e)}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final articlesAsync = ref.watch(knowledgeArticlesProvider);
    final categoriesAsync = ref.watch(historyCategoryEntriesProvider);
    final categoryFilter = ref.watch(knowledgeCategoryFilterProvider);
    final hasFilters =
        ref.watch(knowledgeSearchProvider).trim().isNotEmpty ||
        categoryFilter != null;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openArticle(),
        icon: const Icon(Icons.add),
        label: const Text('Νέο άρθρο'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Αναζήτηση σε σύμπτωμα, λύση, λέξεις-κλειδιά',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Καθαρισμός',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searchController.clear();
                                ref
                                    .read(knowledgeSearchProvider.notifier)
                                    .setQuery('');
                              },
                            ),
                    ),
                    onChanged: (value) => ref
                        .read(knowledgeSearchProvider.notifier)
                        .setQuery(value),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 260,
                  child: categoriesAsync.when(
                    data: (entries) {
                      final options = <({int? id, String name})>[
                        (id: null, name: '— Όλες οι κατηγορίες —'),
                        ...entries.map((e) => (id: e.id, name: e.name)),
                      ];
                      final selected = options.any((e) => e.id == categoryFilter)
                          ? categoryFilter
                          : null;
                      return DropdownButtonFormField<int?>(
                        initialValue: selected,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: options
                            .map(
                              (entry) => DropdownMenuItem<int?>(
                                value: entry.id,
                                child: Text(entry.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => ref
                            .read(knowledgeCategoryFilterProvider.notifier)
                            .select(value),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: articlesAsync.when(
                data: (articles) {
                  if (articles.isEmpty) {
                    return _EmptyState(filtered: hasFilters);
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: articles.length,
                    itemBuilder: (context, index) {
                      final article = articles[index];
                      return KnowledgeArticleCard(
                        article: article,
                        onEdit: () => _openArticle(article),
                        onDelete: () => _deleteArticle(article),
                      );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text(
                    'Αποτυχία φόρτωσης: ${humanizeUserFacingError(error)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.healing,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              filtered
                  ? 'Κανένα άρθρο δεν ταιριάζει με την αναζήτηση.'
                  : 'Η Βάση Γνώσης είναι ακόμη άδεια.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              filtered
                  ? 'Δοκιμάστε λιγότερες λέξεις ή καθαρίστε το φίλτρο κατηγορίας.'
                  : 'Ο συνηθισμένος τρόπος να γεμίσει: στην αναφορά Lansweeper, '
                        'αφού ετοιμάσετε το κείμενο μιας κλήσης, πατήστε '
                        '«Αποθήκευση ως γνώση». Το σύμπτωμα και η λύση '
                        'μεταφέρονται έτοιμα.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
