import 'branch.dart';
import 'cinema.dart';
import 'film.dart';

/// A row for the History screen (F6) — one past `movies_seen` entry,
/// denormalised with what the screen needs to render without a second
/// round trip — `Database.getHistory` joins through `branches` and
/// `films` in one embedded query and [Attendance.fromJson] flattens it.
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

  /// One row of the embedded history query — see
  /// `Database.getHistory`. PostgREST nests each related row under the
  /// name of the table it came from, so `movies_seen` arrives with a
  /// `branches` map inside it, a `cinemas` map inside that, and a
  /// `films` map alongside.
  ///
  /// [adMinutes] is derived rather than stored: the chain's researched
  /// timing is applied at read time, so correcting a chain later moves
  /// its historical figures with it.
  factory Attendance.fromJson(Map<String, dynamic> json) {
    final branch = Branch.fromJson(json["branches"]);
    final cinema = Cinema.fromJson(json["branches"]["cinemas"]);
    final film = Film.fromJson(json["films"]);

    return Attendance(
      id: json["movie_seen_id"],
      filmTitle: film.title,
      posterUrl: film.posterUrl,
      cinemaName: cinema.name,
      branchName: branch.branchName,
      ticketTime: DateTime.parse(json["ticket_time"]).toLocal(),
      adMinutes: cinema.adMinutesFor(film.durationMin),
      durationMin: film.durationMin,
    );
  }

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
