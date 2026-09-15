import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/app_repository.dart';
import '../../models/attendance.dart';
import '../../widgets/attendance_row.dart';
import '../../widgets/vignette_backdrop.dart';

/// Every past screening, on its own screen. This used to be a list
/// permanently sitting in the middle of Profile under "ATTENDED
/// SCREENINGS" — moved here since a page full of individual past
/// visits was competing with the recap card for attention on a page
/// that's really about *this* year's numbers and account settings.
/// The data and the row styling are unchanged, just relocated behind
/// a "History" button.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Future<List<Attendance>>? _history;

  @override
  void initState() {
    super.initState();
    _history = appRepository.history();
  }

  Future<void> _refresh() async {
    final next = appRepository.history();
    setState(() => _history = next);
    await next;
  }

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
                    Text('History', style: AppTypography.displaySmall.copyWith(color: AppColors.textPrimary)),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.gold,
                  backgroundColor: AppColors.surface,
                  onRefresh: _refresh,
                  child: FutureBuilder<List<Attendance>>(
                    future: _history,
                    builder: (context, snapshot) {
                      final rows = snapshot.data;
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                        children: [
                          if (rows == null)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2)),
                            )
                          else if (rows.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Text(
                                'Nothing yet — upload a ticket to start your first session.',
                                style: AppTypography.bodyMedium,
                              ),
                            )
                          else
                            for (final a in rows) AttendanceRow(attendance: a),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
