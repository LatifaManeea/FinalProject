/// The yearly summary card on History & Recap — "You have watched 6.2
/// hours of advertisements this year." Recomputed at read time by
/// joining through `branches` to `cinemas`, so a later correction to a
/// chain's researched timing moves historical figures with it (a
/// deliberate tradeoff the proposal names explicitly).
class YearlyRecap {
  const YearlyRecap({
    required this.year,
    required this.filmsWatched,
    required this.cinemasVisited,
    required this.totalAdMinutes,
    required this.totalWatchMinutes,
  });

  final int year;
  final int filmsWatched;
  final int cinemasVisited;
  final int totalAdMinutes;
  final int totalWatchMinutes;

  double get totalAdHours => totalAdMinutes / 60;
}
