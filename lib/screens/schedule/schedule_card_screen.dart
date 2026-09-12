import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/app_repository.dart';
import '../../models/branch.dart';
import '../../models/cinema.dart';
import '../../models/film.dart';
import '../../models/film_break.dart';
import '../../models/schedule.dart';
import '../../utils/date_format.dart';
import '../../widgets/segmented_timeline.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/vignette_backdrop.dart';

enum _Phase { editing, live, ended }

/// Proposal screens 7 & 8 — one screen, two (really three, counting
/// the summary) states, sharing a widget tree. Before Start it's an
/// editable preview and the manual-entry path; after Start the
/// editable fields disappear and the same timeline advances against
/// the clock; when the film ends, a summary replaces it.
class ScheduleCardScreen extends StatefulWidget {
  const ScheduleCardScreen({
    super.key,
    this.preselectedFilm,
    this.preselectedCinemaName,
    this.initialTicketTime,
    this.ocrConfidence,
  });

  final Film? preselectedFilm;
  final String? preselectedCinemaName;
  final DateTime? initialTicketTime;
  final double? ocrConfidence;

  @override
  State<ScheduleCardScreen> createState() => _ScheduleCardScreenState();
}

class _ScheduleCardScreenState extends State<ScheduleCardScreen> {
  _Phase _phase = _Phase.editing;

  List<Cinema> _cinemas = [];
  List<Film> _filmOptions = [];
  List<Branch> _branchOptions = [];

  Film? _film;
  String? _cinemaName;
  Branch? _branch;
  late DateTime _ticketTime;

  int? _adMinutes;
  List<FilmBreak> _breaks = [];
  bool _loadingBreaks = false;

  DateTime? _liveStartedAt;
  Timer? _ticker;
  bool _demoSpeedEnabled = false;
  static const _demoSpeedMultiplier = 90;

  @override
  void initState() {
    super.initState();
    _film = widget.preselectedFilm;
    _cinemaName = widget.preselectedCinemaName;
    _ticketTime = widget.initialTicketTime ?? DateTime.now();
    _bootstrap();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final cinemas = await appRepository.cinemas();
    final films = await appRepository.nowShowing();
    if (!mounted) return;
    setState(() {
      _cinemas = cinemas;
      _filmOptions = films;
    });
    if (_cinemaName != null) await _onCinemaChanged(_cinemaName, keepBranch: false);
    if (_film != null) await _loadBreaksAndAdMinutes();
  }

  Future<void> _onCinemaChanged(String? name, {bool keepBranch = true}) async {
    if (name == null) return;
    setState(() {
      _cinemaName = name;
      if (!keepBranch) _branch = null;
      _branchOptions = [];
    });
    final branches = await appRepository.branches(name);
    if (!mounted) return;
    setState(() {
      _branchOptions = branches;
      _branch = branches.isEmpty ? null : branches.first;
    });
    await _loadBreaksAndAdMinutes();
  }

  Future<void> _onFilmChanged(Film? film) async {
    if (film == null) return;
    setState(() {
      _film = film;
      _breaks = [];
    });
    await _loadBreaksAndAdMinutes();
  }

  Future<void> _loadBreaksAndAdMinutes() async {
    final film = _film;
    final cinemaName = _cinemaName;
    if (film != null && cinemaName != null) {
      final ad = await appRepository.adMinutes(cinemaName, film.durationMin);
      if (mounted) setState(() => _adMinutes = ad);
    }
    if (film != null) {
      setState(() => _loadingBreaks = true);
      final breaks = await appRepository.breaksForFilm(film.tmdbId);
      if (!mounted) return;
      setState(() {
        _breaks = breaks;
        _loadingBreaks = false;
      });
    }
  }

  Future<void> _pickTicketTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _ticketTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_ticketTime));
    if (time == null) return;
    setState(() {
      _ticketTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Schedule? get _schedule {
    final film = _film;
    final branch = _branch;
    final ad = _adMinutes;
    if (film == null || branch == null || ad == null) return null;
    return Schedule(branch: branch, film: film, ticketTime: _ticketTime, adMinutes: ad, breaks: _breaks);
  }

  Duration get _elapsedRealDuration =>
      _liveStartedAt == null ? Duration.zero : DateTime.now().difference(_liveStartedAt!);

  int get _elapsedSeconds {
    final real = _elapsedRealDuration.inSeconds;
    return _demoSpeedEnabled ? real * _demoSpeedMultiplier : real;
  }

  int get _elapsedMinutes => _elapsedSeconds ~/ 60;

  Future<void> _start() async {
    final schedule = _schedule;
    if (schedule == null) return;
    await appRepository.recordAttendance(schedule);
    setState(() {
      _liveStartedAt = DateTime.now();
      _phase = _Phase.live;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_elapsedMinutes >= schedule.totalMinutes) _endSession();
    });
  }

  void _endSession() {
    _ticker?.cancel();
    if (mounted) setState(() => _phase = _Phase.ended);
  }

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;

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
                      onPressed: () {
                        if (_phase == _Phase.live) {
                          _confirmLeaveLiveSession();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    ),
                    Text(
                      _phase == _Phase.editing ? 'Schedule' : 'Live Session',
                      style: AppTypography.displaySmall.copyWith(color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: switch (_phase) {
                    _Phase.editing => _buildEditing(schedule),
                    _Phase.live => _buildLive(schedule!),
                    _Phase.ended => _buildEnded(schedule!),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLeaveLiveSession() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Leave Live Session?', style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
        content: Text('The countdown keeps running while the app is open. Leaving now ends it.', style: AppTypography.bodyMedium),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    if (leave == true && mounted) {
      _ticker?.cancel();
      Navigator.of(context).pop();
    }
  }

  // ---- Editing / preview (screen 7) ---------------------------------------

  Widget _buildEditing(Schedule? schedule) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.ocrConfidence != null) ...[
          _OcrHintBanner(confidence: widget.ocrConfidence!),
          const SizedBox(height: 18),
        ],
        Text('FILM', style: AppTypography.overline),
        const SizedBox(height: 8),
        _buildFilmDropdown(),
        const SizedBox(height: 20),
        Text('CINEMA', style: AppTypography.overline),
        const SizedBox(height: 8),
        _buildCinemaDropdown(),
        const SizedBox(height: 20),
        Text('BRANCH', style: AppTypography.overline),
        const SizedBox(height: 8),
        _buildBranchDropdown(),
        const SizedBox(height: 20),
        Text('TICKET TIME', style: AppTypography.overline),
        const SizedBox(height: 8),
        _buildTicketTimeField(),
        const SizedBox(height: 28),
        if (schedule != null) _buildScheduleSummary(schedule) else _buildIncompleteHint(),
        const SizedBox(height: 28),
        TickedPrimaryButton(label: 'Start', onPressed: schedule == null ? null : _start),
      ],
    );
  }

  Widget _buildFilmDropdown() {
    return _DropdownShell<Film>(
      value: _film,
      hint: 'Choose a film',
      items: _filmOptions.map((f) => DropdownMenuItem(value: f, child: Text(f.title))).toList(),
      itemLabel: (f) => f.title,
      onChanged: _onFilmChanged,
    );
  }

  Widget _buildCinemaDropdown() {
    return _DropdownShell<String>(
      value: _cinemaName,
      hint: 'Choose a chain',
      items: _cinemas.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
      itemLabel: (n) => n,
      onChanged: (name) => _onCinemaChanged(name),
    );
  }

  Widget _buildBranchDropdown() {
    return _DropdownShell<Branch>(
      value: _branch,
      hint: _cinemaName == null ? 'Choose a chain first' : 'Choose a branch',
      items: _branchOptions.map((b) => DropdownMenuItem(value: b, child: Text(b.branchName))).toList(),
      itemLabel: (b) => b.branchName,
      onChanged: (b) => setState(() => _branch = b),
    );
  }

  Widget _buildTicketTimeField() {
    return GestureDetector(
      onTap: _pickTicketTime,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule, color: AppColors.textTertiary, size: 18),
            const SizedBox(width: 10),
            Text(formatDateAndClock(_ticketTime), style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('Change', style: AppTypography.label.copyWith(color: AppColors.gold)),
          ],
        ),
      ),
    );
  }

  Widget _buildIncompleteHint() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Text(
        'Pick a film, chain and branch to see the real start and end time.',
        style: AppTypography.bodyMedium,
      ),
    );
  }

  Widget _buildScheduleSummary(Schedule schedule) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Starts ${formatClock(schedule.trueStartTime)} · ends ${formatClock(schedule.trueEndTime)}',
            style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('${schedule.adMinutes} min of advertising, researched at ${schedule.branch.cinemaName}', style: AppTypography.bodySmall),
          const SizedBox(height: 16),
          SegmentedTimeline(segments: schedule.buildTimeline(), totalMinutes: schedule.totalMinutes),
          const SizedBox(height: 10),
          _buildLegend(),
          if (_loadingBreaks) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                ),
                const SizedBox(width: 8),
                Text('Finding safe breaks…', style: AppTypography.bodySmall),
              ],
            ),
          ] else if (schedule.breaks.isEmpty) ...[
            const SizedBox(height: 10),
            Text('No safe breaks found for this film.', style: AppTypography.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _buildLegend() {
    Widget dot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: AppTypography.bodySmall),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        dot(AppColors.timelineAds, 'Ads'),
        dot(AppColors.timelineFilm, 'Film'),
        dot(AppColors.timelineBreak, 'Safe break'),
        dot(AppColors.timelineCredits, 'Credits'),
      ],
    );
  }

  // ---- Live (screen 8) ----------------------------------------------------

  Widget _buildLive(Schedule schedule) {
    final remainingSeconds = (schedule.totalMinutes * 60) - _elapsedSeconds;
    final nextBreak = schedule.nextBreakAfter(_elapsedMinutes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(schedule.film.title, style: AppTypography.displayMedium, textAlign: TextAlign.center),
        Text('${schedule.branch.cinemaName} · ${schedule.branch.branchName}', style: AppTypography.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: 22),
        Center(
          child: Column(
            children: [
              Text('TIME REMAINING', style: AppTypography.overline),
              const SizedBox(height: 4),
              Text(formatCountdown(Duration(seconds: remainingSeconds < 0 ? 0 : remainingSeconds)), style: AppTypography.timerLarge),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SegmentedTimeline(
          segments: schedule.buildTimeline(),
          totalMinutes: schedule.totalMinutes,
          elapsedMin: _elapsedMinutes,
        ),
        const SizedBox(height: 10),
        _buildLegend(),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: nextBreak == null
              ? Text('No more safe breaks in this screening.', style: AppTypography.bodyMedium)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NEXT SAFE BREAK', style: AppTypography.overline),
                    const SizedBox(height: 4),
                    Text(
                      _elapsedMinutes >= schedule.adMinutes + nextBreak.startMin
                          ? 'Now, for ${nextBreak.lengthMin} more min'
                          : 'In ${schedule.adMinutes + nextBreak.startMin - _elapsedMinutes} min, for ${nextBreak.lengthMin} min',
                      style: AppTypography.bodyLarge.copyWith(color: AppColors.gold, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 22),
        SwitchListTile(
          value: _demoSpeedEnabled,
          onChanged: (v) => setState(() => _demoSpeedEnabled = v),
          activeColor: AppColors.gold,
          contentPadding: EdgeInsets.zero,
          title: Text('Demo speed', style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary)),
          subtitle: Text('Compresses the screening for a live demo — judging only.', style: AppTypography.bodySmall),
        ),
        const SizedBox(height: 8),
        TickedSecondaryButton(label: 'End session', onPressed: _endSession),
      ],
    );
  }

  // ---- Ended / summary -----------------------------------------------------

  Widget _buildEnded(Schedule schedule) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.check_circle_outline, color: AppColors.gold, size: 44),
        const SizedBox(height: 14),
        Text('Session complete', style: AppTypography.displayMedium, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(schedule.film.title, style: AppTypography.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: _SummaryTile(value: '${schedule.adMinutes}', label: 'MIN OF ADS ENDURED'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryTile(value: '${schedule.breaks.length}', label: 'SAFE BREAKS TAKEN'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        TickedPrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

class _OcrHintBanner extends StatelessWidget {
  const _OcrHintBanner({required this.confidence});

  final double confidence;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Filled in from your ticket photo — double-check before starting.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text(value, style: AppTypography.displayLarge.copyWith(color: AppColors.gold)),
          const SizedBox(height: 4),
          Text(label, style: AppTypography.overline, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _DropdownShell<T> extends StatelessWidget {
  const _DropdownShell({
    required this.value,
    required this.hint,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    // ignore: unused_element_parameter
    super.key,
  });

  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(hint, style: AppTypography.bodyLarge.copyWith(color: AppColors.textDisabled)),
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textTertiary),
          dropdownColor: AppColors.surface2,
          style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
