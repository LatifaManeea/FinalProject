import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/app_repository.dart';
import '../../models/attendance.dart';
import '../../models/yearly_recap.dart';
import '../../utils/date_format.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/vignette_backdrop.dart';

/// Proposal screen 9 — attended screenings plus the yearly summary
/// card. The recap is recomputed at read time (never stored per-row),
/// so a later correction to a chain's researched ad timing moves these
/// figures with it — a deliberate tradeoff named in the proposal.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Attendance>> _history;
  late Future<YearlyRecap> _recap;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _history = appRepository.history();
    _recap = appRepository.recap(DateTime.now().year);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        showVelvet: false,
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: () async {
              setState(_load);
              await Future.wait([_history, _recap]);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                Text('History & Recap', style: AppTypography.displayMedium),
                const SizedBox(height: 20),
                FutureBuilder<YearlyRecap>(
                  future: _recap,
                  builder: (context, snapshot) {
                    final recap = snapshot.data;
                    if (recap == null) {
                      return const SizedBox(height: 90, child: Center(child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2)));
                    }
                    return _RecapCard(recap: recap);
                  },
                ),
                const SizedBox(height: 28),
                Text('ATTENDED SCREENINGS', style: AppTypography.overline),
                const SizedBox(height: 12),
                FutureBuilder<List<Attendance>>(
                  future: _history,
                  builder: (context, snapshot) {
                    final rows = snapshot.data;
                    if (rows == null) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2)),
                      );
                    }
                    if (rows.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('Nothing yet — upload a ticket to start your first session.', style: AppTypography.bodyMedium),
                      );
                    }
                    return Column(
                      children: [for (final a in rows) _AttendanceRow(attendance: a)],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
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
