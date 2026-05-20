import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Fixed set of accent colors the user can choose from.
/// Index 0 is the default pink — identical to [AppColors.brandPrimaryLight] —
/// so users who never open Settings experience zero visual change.
const List<Color> kAccentColors = [
  AppColors.brandPrimaryLight, // ピンク (default)
  Color(0xFF1976D2), // 青
  Color(0xFF00897B), // ティール
  Color(0xFF388E3C), // 緑
  Color(0xFFF57C00), // オレンジ
  Color(0xFF7B1FA2), // 紫
];

/// Localized labels parallel to [kAccentColors].
const List<String> kAccentColorLabels = [
  'ピンク',
  '青',
  'ティール',
  '緑',
  'オレンジ',
  '紫',
];
