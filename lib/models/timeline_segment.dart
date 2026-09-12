/// What kind of span a [TimelineSegment] represents — drawn in its own
/// colour per F4 (`AppColors.timelineAds` / `timelineFilm` /
/// `timelineBreak` / `timelineCredits`).
enum TimelineSegmentKind { ads, film, safeBreak, credits }

/// One coloured span on the segmented timeline, in minutes from the
/// ticket time (minute 0 = seating begins).
class TimelineSegment {
  const TimelineSegment({required this.kind, required this.startMin, required this.endMin});

  final TimelineSegmentKind kind;
  final int startMin;
  final int endMin;

  int get lengthMin => endMin - startMin;
}
