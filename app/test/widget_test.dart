import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otameishi/theme/app_theme.dart';
import 'package:otameishi/widgets/empty_state.dart';

void main() {
  testWidgets('EmptyState renders icon and message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: EmptyState(
          icon: Icons.style_outlined,
          message: 'まだ名刺がありません',
          hint: '右下のカメラから始めましょう',
        ),
      ),
    ));
    expect(find.text('まだ名刺がありません'), findsOneWidget);
    expect(find.text('右下のカメラから始めましょう'), findsOneWidget);
    expect(find.byIcon(Icons.style_outlined), findsOneWidget);
  });

  test('AppTheme.light builds with brand primary', () {
    final theme = AppTheme.light();
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, AppColors.brandPrimaryLight);
  });

  test('AppTheme.dark builds with dark brightness', () {
    final theme = AppTheme.dark();
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.brightness, Brightness.dark);
  });
}
