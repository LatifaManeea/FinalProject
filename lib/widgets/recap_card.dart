import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import '../models/yearly_recap.dart';
import '../utils/date_format.dart';
import 'stat_tile.dart';

/// The single "how much have I watched" summary on Profile — films,
/// cinemas, and time at the cinema for the year, plus the ad-minutes
/// headline. This used to sit alongside a second, separate FILMS
/// WATCHED / CINEMAS VISITED tile row further up the page; that row
/// was just this same data said twice, so it's gone and this card is
/// now the only place those numbers live.
class RecapCard extends StatelessWidget {
  const RecapCard({super.key, required this.recap});

  /// Null while the first load is still in flight.
  final YearlyRecap? recap;

  @override
  Widget build(BuildContext context) {
    final recap = this.recap;
    if (recap == null) {
      return const SizedBox(
        height: 90,
        child: Center(child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface, AppColors.velvet],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${recap.year} RECAP', style: AppTypography.overline),
          const SizedBox(height: 6),
          Text(
            recap.totalAdMinutes == 0
                ? 'No screenings recorded yet this year.'
                : 'You have watched ${recap.totalAdHours.toStringAsFixed(1)} hours of advertisements this year.',
            style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              StatTile(value: '${recap.filmsWatched}', label: 'FILMS'),
              const SizedBox(width: 10),
              StatTile(value: '${recap.cinemasVisited}', label: 'CINEMAS'),
              const SizedBox(width: 10),
              StatTile(value: formatMinutes(recap.totalWatchMinutes), label: 'TIME AT THE CINEMA'),
            ],
          ),
        ],
      ),
    );
  }
}
