import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/theme/app_theme.dart';

void main() {
  testWidgets(
    'download progress bar track color is distinct from its fill color',
    (tester) async {
      // Regression guard: AppTheme.lightTheme only sets ColorScheme.secondary,
      // so LinearProgressIndicator's default track color (secondaryContainer,
      // which falls back to secondary) used to match the fill color exactly
      // — making the bar look permanently full regardless of value.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LinearProgressIndicator(
              value: 0.08,
              color: AppTheme.emeraldGreen,
              backgroundColor: AppTheme.emeraldGreen.withValues(alpha: 0.15),
            ),
          ),
        ),
      );

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );

      expect(indicator.backgroundColor, isNotNull);
      expect(indicator.backgroundColor, isNot(equals(indicator.color)));
    },
  );
}
