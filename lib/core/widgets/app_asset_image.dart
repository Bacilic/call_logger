import 'package:flutter/material.dart';

/// Εικόνα από asset με εναλλακτικό εικονίδιο όταν το αρχείο λείπει.
///
/// Γενικεύει το μοτίβο RemoteToolIcon (`errorBuilder` → fallback) ώστε να μην
/// καταλήγει η εφαρμογή σε οθόνη σφάλματος από γυμνό [Image.asset].
class AppAssetImage extends StatelessWidget {
  const AppAssetImage({
    super.key,
    required this.assetPath,
    required this.fallbackIcon,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
    this.fallbackSize,
    this.fallbackColor,
    this.fallback,
  });

  final String assetPath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final IconData fallbackIcon;
  final double? fallbackSize;
  final Color? fallbackColor;

  /// Αν δοθεί, υπερισχύει του [Icon] με [fallbackIcon].
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      errorBuilder: (_, _, _) =>
          fallback ??
          Icon(
            fallbackIcon,
            size: fallbackSize,
            color: fallbackColor,
          ),
    );
  }
}
