import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../provider/import_log_provider.dart';

/// Live console για οπτικοποίηση του Import Excel (μαύρο φόντο, πράσινο κείμενο, auto-scroll).
class ImportConsoleWidget extends ConsumerStatefulWidget {
  const ImportConsoleWidget({super.key});

  @override
  ConsumerState<ImportConsoleWidget> createState() => _ImportConsoleWidgetState();
}

class _ImportConsoleWidgetState extends ConsumerState<ImportConsoleWidget> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  void _scrollToEnd() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(importLogProvider);

    ref.listen<List<String>>(importLogProvider, (_, next) {
      if (next.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
      }
    });

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(12),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: logs.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              logs[index],
              style: GoogleFonts.robotoMono(
                fontSize: 12,
                color: Colors.green.shade300,
              ),
            ),
          );
        },
      ),
    );
  }
}
