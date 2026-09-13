import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/app_repository.dart';
import '../../models/attendance.dart';
import '../../models/cinema.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/vignette_backdrop.dart';
import '../ticket/upload_ticket_screen.dart';

/// Proposal screen 5 — "Upload your ticket" as the primary action, the
/// most recent session, and a shortcut into the Cinemas tab. The
/// "now showing in Riyadh" carousel that used to sit at the bottom now
/// lives there, one row per chain.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onBrowseCinema});

  /// Asks [MainShell] to open the Cinemas tab at one chain.
  final ValueChanged<String> onBrowseCinema;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Cinema>> _cinemas;
  late Future<List<Attendance>> _history;

  @override
  void initState() {
    super.initState();
    _cinemas = appRepository.cinemas();
    _history = appRepository.history();
  }

  void _refreshHistory() {
    setState(() => _history = appRepository.history());
  }

  Future<void> _openUploadTicket() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadTicketScreen()));
    _refreshHistory();
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
              setState(() {
                _cinemas = appRepository.cinemas();
                _history = appRepository.history();
              });
              await Future.wait([_cinemas, _history]);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                Text('TICKED', style: AppTypography.displaySmall.copyWith(color: AppColors.textTertiary)),
                const SizedBox(height: 4),
                Text('Never miss the first frame', style: AppTypography.displayMedium),
                const SizedBox(height: 22),
                _UploadTicketCard(onTap: _openUploadTicket),
                const SizedBox(height: 30),
                _MostRecentSession(historyFuture: _history),
                const SizedBox(height: 30),
                Text('BROWSE BY CINEMA', style: AppTypography.overline),
                const SizedBox(height: 12),
                FutureBuilder<List<Cinema>>(
                  future: _cinemas,
                  builder: (context, snapshot) {
                    final cinemas = snapshot.data;
                    if (cinemas == null) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                        ),
                      );
                    }
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final cinema in cinemas)
                          _CinemaChip(
                            label: cinema.name,
                            onTap: () => widget.onBrowseCinema(cinema.name),
                          ),
                      ],
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

/// One chain, tapped to open the Cinemas tab scrolled to its row.
class _CinemaChip extends StatelessWidget {
  const _CinemaChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppTypography.label.copyWith(color: AppColors.textPrimary)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.gold, size: 16),
          ],
        ),
      ),
    );
  }
}

class _UploadTicketCard extends StatelessWidget {
  const _UploadTicketCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.confirmation_number_outlined, color: AppColors.gold, size: 26),
          const SizedBox(height: 12),
          Text('Got a ticket?', style: AppTypography.displaySmall.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(
            'Upload the photo and we\'ll tell you when it really starts.',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: 16),
          TickedPrimaryButton(label: 'Upload your ticket', onPressed: onTap),
        ],
      ),
    );
  }
}

class _MostRecentSession extends StatelessWidget {
  const _MostRecentSession({required this.historyFuture});

  final Future<List<Attendance>> historyFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Attendance>>(
      future: historyFuture,
      builder: (context, snapshot) {
        final rows = snapshot.data;
        if (rows == null || rows.isEmpty) return const SizedBox.shrink();
        final latest = rows.first;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MOST RECENT SESSION', style: AppTypography.overline),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.surface2, AppColors.velvet],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          latest.filmTitle,
                          style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text('${latest.cinemaName} · ${latest.branchName}', style: AppTypography.bodySmall),
                      ],
                    ),
                  ),
                  Text('${latest.adMinutes} min ads', style: AppTypography.timerSmall),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
