/// Mirrors `films`. `breaksCheckedAt` is the two-state-encodes-three-outcomes
/// column from the proposal: null means never asked; non-null with no
/// [FilmBreak] rows means asked and nothing usable was found.
///
/// Populated by scraping cinema sites directly (VOX Cinemas first —
/// see scripts/vox_scraper.py) rather than TMDB: `filmId` is a plain
/// auto-incrementing id, not any third party's id.
class Film {
  const Film({
    required this.filmId,
    required this.title,
    required this.durationMin,
    this.posterUrl,
    this.creditsStartMin,
    this.breaksCheckedAt,
  });

  /// One row of `films`. Written by the scraper's sync job (service
  /// role) and, for the shared breaks cache, by any signed-in client —
  /// see database.dart.
  factory Film.fromJson(Map<String, dynamic> json) {
    final checkedAt = json["breaks_checked_at"];

    return Film(
      filmId: json["film_id"],
      title: json["title"],
      durationMin: json["duration_min"],
      posterUrl: json["poster_url"],
      creditsStartMin: json["credits_start_min"],
      breaksCheckedAt: checkedAt == null ? null : DateTime.parse(checkedAt).toLocal(),
    );
  }

  final int filmId;
  final String title;
  final int durationMin;
  final String? posterUrl;
  final int? creditsStartMin;
  final DateTime? breaksCheckedAt;

  /// Used to attach Gemini's credits answer to the cached row before
  /// writing it back — Gemini is only ever asked for the credits/break
  /// timing, never for title/duration/poster, so those three pass
  /// through untouched here.
  Film copyWith({int? creditsStartMin, DateTime? breaksCheckedAt}) {
    return Film(
      filmId: filmId,
      title: title,
      durationMin: durationMin,
      posterUrl: posterUrl,
      creditsStartMin: creditsStartMin ?? this.creditsStartMin,
      breaksCheckedAt: breaksCheckedAt ?? this.breaksCheckedAt,
    );
  }

  bool get breaksAreCached => breaksCheckedAt != null;

  /// False when the source site had no runtime listed yet (VOX leaves
  /// this off for titles that haven't opened) — a schedule cannot be
  /// built from this film until a real duration is known.
  bool get hasKnownDuration => durationMin > 0;
}
