import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import '../models/film.dart';

/// A "now showing" card for Home. Shows the real poster
/// ([Film.posterUrl], now populated from VOX's own site) when there is
/// one, and falls back to the placeholder tile — for a null URL, a
/// failed load, or the couple of not-yet-released titles VOX itself
/// hasn't uploaded art for yet.
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
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
                  child: film.posterUrl == null
                      ? _placeholderIcon()
                      : Image.network(
                          film.posterUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _placeholderIcon(),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return _placeholderIcon();
                          },
                        ),
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

  Widget _placeholderIcon() {
    return Center(
      child: Icon(Icons.local_movies_outlined, color: AppColors.textTertiary, size: 30),
    );
  }
}
