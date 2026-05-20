import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/business_card.dart';
import '../theme/app_theme.dart';

/// Tile presentation for a [BusinessCard] in lists.
class CardTile extends StatelessWidget {
  const CardTile({super.key, required this.card, this.onTap});

  final BusinessCard card;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMd('ja');

    return Semantics(
      label: card.displayName ?? '名前なし',
      button: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s3),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: _Thumbnail(path: card.imagePath),
                ),
                const SizedBox(width: AppSpacing.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        card.displayName ?? '名前なし',
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.s1),
                      Text(
                        dateFmt.format(card.createdAt.toLocal()),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (card.tags.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.s2),
                        Wrap(
                          spacing: AppSpacing.s1,
                          runSpacing: AppSpacing.s1,
                          children: card.tags
                              .map((t) => _TagChip(label: t.name))
                              .toList(growable: false),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    const w = 72.0;
    const h = (72.0 * 55) / 91; // aspect 91:55 → ~43.5
    return SizedBox(
      width: w,
      height: h,
      child: file.existsSync()
          ? Image.file(file, fit: BoxFit.cover)
          : Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.image_not_supported_outlined),
            ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(label, style: theme.textTheme.bodySmall),
    );
  }
}
