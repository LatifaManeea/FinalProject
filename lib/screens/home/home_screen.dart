import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/app_repository.dart';
import '../../models/attendance.dart';
import '../../models/film.dart';
import '../../widgets/film_poster_card.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/vignette_backdrop.dart';
import '../schedule/schedule_card_screen.dart';
import '../ticket/upload_ticket_screen.dart';

/// Proposal screen 5 — now showing in Riyadh, "Upload your ticket" as
/// the primary action, and the most recent session.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Film>> _nowShowing;
  late Future<List<Attendance>> _history;

  @override
  void initState() {
    super.initState();
    _nowShowing = appRepository.nowShowing();
    _history = appRepository.history();
  }

  void _refreshHistory() {
    setState(() => _history = appRepository.history());
  }

  Future<void> _openUploadTicket() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadTicketScreen()));
    _refreshHistory();
  }

  Future<void> _openFilm(Film film) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScheduleCardScreen(preselectedFilm: film),
      ),
    );
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
                _nowShowing = appRepository.nowShowing();
                _history = appRepository.history();
              });
              await Future.wait([_nowShowing, _history]);
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
                Text('NOW SHOWING IN RIYADH', style: AppTypography.overline),
                const SizedBox(height: 12),
                SizedBox(
                  height: 190,
                  child: FutureBuilder<List<Film>>(
                    future: _nowShowing,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                        );
                      }
                      final films = snapshot.data!;
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: films.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, i) => FilmPosterCard(
                          film: films[i],
                          onTap: () => _openFilm(films[i]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
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
