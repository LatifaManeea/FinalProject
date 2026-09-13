/// One showing of one film, at one branch, on one screen. Mirrors the
/// `showtimes` table — written only by the scraper's daily sync job
/// (scripts/sync_to_supabase.py, using the service role key), never by
/// the app itself. Regular signed-in users only ever read it.
class Showtime {
  const Showtime({
    required this.branchId,
    required this.filmId,
    required this.screenType,
    required this.time,
    this.soldOut = false,
  });

  factory Showtime.fromJson(Map<String, dynamic> json) {
    return Showtime(
      branchId: json["branch_id"],
      filmId: json["film_id"],
      screenType: json["screen_type"],
      time: DateTime.parse(json["show_time"]).toLocal(),
      soldOut: json["sold_out"] ?? false,
    );
  }

  /// Points at [Branch.id].
  final int branchId;

  /// Points at [Film.filmId].
  final int filmId;

  /// VOX's own screen names as scraped: "IMAX", "MAX", "Premium",
  /// "VIP", "Standard", "THEATRE", "Private Cinema", ...
  final String screenType;

  final DateTime time;

  /// True when the source site shows the slot as unavailable (VOX
  /// renders these as a plain `<span>` instead of a booking link).
  final bool soldOut;
}
