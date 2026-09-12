import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import '../models/film.dart';

/// A "now showing" card for Home. TMDB poster art lands here once the
/// real client is wired in ([Film.posterUrl]); until then a tasteful
/// placeholder keeps the row from looking unfinished.
class FilmPosterCard extends StatelessWidget {
  const FilmPosterCard({super.key, required this.film, required this.onTap});

  final Film film;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.surface2, AppColors.surface],
                  ),
                ),
                child: Center(
                  child: Icon(Icons.local_movies_outlined, color: AppColors.textTertiary, size: 30),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              film.title,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text('${film.durationMin} min', style: AppTypography.bodySmall),
          ],
        ),
      ),
    );
  }
}
