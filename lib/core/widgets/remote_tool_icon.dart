import 'dart:io';

import 'package:flutter/material.dart';

import '../services/portable_tool_image_storage.dart';

/// Εικονίδιο εργαλείου από `icon_asset_key` (assets, `images/…`, legacy απόλυτη).
class RemoteToolIcon extends StatelessWidget {
  const RemoteToolIcon({
    super.key,
    required this.iconAssetKey,
    this.size = 22,
    this.fallback,
  });

  final String? iconAssetKey;
  final double size;
  final IconData? fallback;

  @override
  Widget build(BuildContext context) {
    final raw = iconAssetKey?.trim() ?? '';
    if (raw.isEmpty) {
      return fallback == null
          ? const SizedBox.shrink()
          : Icon(fallback, size: size);
    }

    Widget broken() => Icon(
      fallback ?? Icons.broken_image_outlined,
      size: size,
    );

    if (raw.startsWith('assets/')) {
      return Image.asset(
        raw,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => broken(),
      );
    }

    final resolved = PortableToolImageStorage.resolveIconFilePath(raw);
    if (resolved != null) {
      return Image.file(
        File(resolved),
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => broken(),
      );
    }

    if (fallback != null) return Icon(fallback, size: size);
    return Icon(Icons.image_outlined, size: size);
  }
}
