import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../widgets/vignette_backdrop.dart';

/// Proposal screen 12 — the developers, contact details and LinkedIn
/// profiles; the problem the project solves and how it works. Names
/// and links are left as placeholders for you and your teammate to
/// fill in — swap [_Developer]'s two entries below for the real ones.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _developers = [
    _Developer(name: 'Add your name', role: 'Interface & Device', linkedIn: 'linkedin.com/in/your-handle'),
    _Developer(name: 'Add teammate\'s name', role: 'Backend & Data', linkedIn: 'linkedin.com/in/their-handle'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        showVelvet: false,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    ),
                    Text('About Us', style: AppTypography.displaySmall.copyWith(color: AppColors.textPrimary)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [
                    Text(
                      'Your ticket says 9:00. The film actually starts at 9:18. We timed it.',
                      style: AppTypography.displaySmall.copyWith(color: AppColors.gold),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Every cinema ticket states a time that is not the time the film begins. '
                      'Ticked tells you the real start time, the real end time, and when it\'s safe '
                      'to leave your seat — using ad-block timings researched directly at each '
                      'cinema chain in Riyadh.',
                      style: AppTypography.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'The ad block is researched by the team, not learned from users — it doesn\'t '
                      'get more accurate with use. Safe breaks are AI-generated on first request and '
                      'cached forever after, so only the first person to watch a film pays the cost.',
                      style: AppTypography.bodyMedium,
                    ),
                    const SizedBox(height: 30),
                    Text('THE TEAM', style: AppTypography.overline),
                    const SizedBox(height: 12),
                    for (final d in _developers) _DeveloperCard(developer: d),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Developer {
  const _Developer({required this.name, required this.role, required this.linkedIn});

  final String name;
  final String role;
  final String linkedIn;
}

class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard({required this.developer});

  final _Developer developer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.surface2,
            child: Text(
              developer.name.isNotEmpty ? developer.name[0].toUpperCase() : '?',
              style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(developer.name, style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(developer.role, style: AppTypography.bodySmall),
                const SizedBox(height: 2),
                Text(developer.linkedIn, style: AppTypography.bodySmall.copyWith(color: AppColors.gold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
