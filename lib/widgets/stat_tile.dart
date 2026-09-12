import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// A single stat — the yearly recap card and Profile both need a row
/// of "the number that matters" tiles.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Text(value, style: AppTypography.displayMedium),
            const SizedBox(height: 4),
            Text(label, style: AppTypography.overline, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
