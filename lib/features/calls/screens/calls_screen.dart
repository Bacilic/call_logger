import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../layout/calls_screen_layout.dart';
/// Οθόνη εισαγωγής κλήσης — row-based layout (πρότυπα Α/Β/Γ/Δ).
class CallsScreen extends ConsumerWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const CallsScreenLayout();
  }
}
