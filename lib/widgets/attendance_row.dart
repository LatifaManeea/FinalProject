import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import '../models/attendance.dart';
import '../utils/date_format.dart';

/// One past screening — poster, title, cinema · branch, and the true
/// (ad-adjusted) start time. Pulled out of what used to be
/// `HistorySection` so it can be reused on its own (see the History
/// screen), with the poster actually drawn now instead of a bare grey
/// box.
class AttendanceRow extends StatelessWidget {
  const AttendanceRow({super.key, required this.attendance});

  final Attendance attendance;

  static Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface2, AppColors.velvet],
        ),
      ),
      child: const Center(
        child: Icon(Icons.local_movies_outlined, color: AppColors.textTertiary, size: 16),
      ),
    );
  }

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
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 38,
              height: 52,
              child: attendance.posterUrl == null
                  ? _placeholder()
                  : Image.network(
                      attendance.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _placeholder(),
                      loadingBuilder: (context, child, progress) => progress == null ? child : _placeholder(),
                    ),
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
