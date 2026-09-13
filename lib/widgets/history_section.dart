import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import '../models/attendance.dart';
import '../models/yearly_recap.dart';
import '../utils/date_format.dart';
import 'stat_tile.dart';

/// Proposal screen 9, no longer a screen — the recap card and the
/// attended screenings list, dropped straight into Profile under the
/// signed-in email. There is no History tab and no History button
/// anywhere; this is simply part of the page.
///
/// The recap is recomputed at read time rather than stored per-row, so
/// a later correction to a chain's researched ad timing moves these
/// figures with it — a deliberate tradeoff from the proposal.
class HistorySection extends StatelessWidget {
  const HistorySection({super.key, required this.history, required this.recap});

  /// Null while the first load is still in flight.
  final List<Attendance>? history;
  final YearlyRecap? recap;

  @override
  Widget build(BuildContext context) {
    final rows = history;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recap == null)
          const SizedBox(
            height: 90,
            child: Center(child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2)),
          )
        else
          _RecapCard(recap: recap!),
        const SizedBox(height: 28),
        Text('ATTENDED SCREENINGS', style: AppTypography.overline),
        const SizedBox(height: 12),
        if (rows == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2)),
          )
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Nothing yet — upload a ticket to start your first session.',
              style: AppTypography.bodyMedium,
            ),
          )
        else
          for (final a in rows) _AttendanceRow(attendance: a),
      ],
    );
  }
}

class _RecapCard extends StatelessWidget {
  const _RecapCard({required this.recap});

  final YearlyRecap recap;

  @override
  Widget build(BuildContext context) {
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

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({required this.attendance});

  final Attendance attendance;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: AppColors.surface2,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attendance.filmTitle, style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${attendance.cinemaName} · ${attendance.branchName}', style: AppTypography.bodySmall),
                const SizedBox(height: 2),
                Text(formatDateAndClock(attendance.trueStartTime), style: AppTypography.timerSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
