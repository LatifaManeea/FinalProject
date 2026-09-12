/// A row for the History screen (F6) — one past `movies_seen` entry,
/// denormalised with what the screen needs to render without a second
/// round trip (the real repository would join through `branches` and
/// `films`; the fake one just builds it directly).
class Attendance {
  const Attendance({
    required this.id,
    required this.filmTitle,
    required this.posterUrl,
    required this.cinemaName,
    required this.branchName,
    required this.ticketTime,
    required this.adMinutes,
    required this.durationMin,
  });

  final int id;
  final String filmTitle;
  final String? posterUrl;
  final String cinemaName;
  final String branchName;
  final DateTime ticketTime;
  final int adMinutes;
  final int durationMin;

  DateTime get trueStartTime => ticketTime.add(Duration(minutes: adMinutes));
}
