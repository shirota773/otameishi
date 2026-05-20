import 'dart:io';

import 'package:flutter/material.dart';

import '../models/business_card.dart';
import '../theme/app_theme.dart';

/// Square-ish tile for gallery grid view.
///
/// The card's front image fills the tile with an [AspectRatio] of 91:55
/// (standard business-card proportions).  The [card.displayName] is shown
/// in a gradient-backed overlay at the bottom for legibility.
class CardGalleryTile extends StatelessWidget {
  const CardGalleryTile({
    super.key,
    required this.card,
    this.onTap,
  });

  final BusinessCard card;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: card.displayName ?? '名前なし',
      button: true,
      child: AspectRatio(
        aspectRatio: 91 / 55,
        child: Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CardImage(path: card.imagePath),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _NameOverlay(name: card.displayName ?? '名前なし'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: Icon(Icons.image_not_supported_outlined, size: 32),
      ),
    );
  }
}

class _NameOverlay extends StatelessWidget {
  const _NameOverlay({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s2,
          AppSpacing.s4,
          AppSpacing.s2,
          AppSpacing.s2,
        ),
        child: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
