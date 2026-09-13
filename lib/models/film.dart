import '../constants/tmdb.dart';

/// Mirrors `films` — a thin local mirror of TMDB, not a metadata
/// store. `breaksCheckedAt` is the two-state-encodes-three-outcomes
/// column from the proposal: null means never asked; non-null with no
/// [FilmBreak] rows means asked and nothing usable was found.
class Film {
  const Film({
    required this.tmdbId,
    required this.title,
    required this.durationMin,
    this.posterUrl,
    this.creditsStartMin,
    this.breaksCheckedAt,
  });

  /// One row of `films`. Written only by the Edge Function (service
  /// role) — the client has SELECT and nothing more.
  factory Film.fromJson(Map<String, dynamic> json) {
    final checkedAt = json["breaks_checked_at"];

    return Film(
      tmdbId: json["tmdb_id"],
      title: json["title"],
      durationMin: json["duration_min"],
      posterUrl: json["poster_url"],
      creditsStartMin: json["credits_start_min"],
      breaksCheckedAt: checkedAt == null ? null : DateTime.parse(checkedAt).toLocal(),
    );
  }

  /// The `/movie/{id}` details response, whose field names are nothing
  /// like the column names above — hence a second factory rather than
  /// a branch inside the first.
  ///
  /// [creditsStartMin] and [breaksCheckedAt] stay null: TMDB knows
  /// nothing about either. They are filled in from `films` once the
  /// Edge Function has run.
  factory Film.fromTmdb(Map<String, dynamic> json) {
    return Film(
      tmdbId: json["id"],
      title: json["title"],
      // TMDB leaves `runtime` null or 0 for films it has no length
      // for — read 0 as "unknown", never as a real duration.
      durationMin: json["runtime"] ?? 0,
      posterUrl: Tmdb.posterUrl(json["poster_path"]),
    );
  }

  final int tmdbId;
  final String title;
  final int durationMin;
  final String? posterUrl;
  final int? creditsStartMin;
  final DateTime? breaksCheckedAt;

  /// Used to attach Gemini's credits answer to the TMDB mirror before
  /// caching it — TMDB knows the runtime, Gemini knows the credits, and
  /// the `films` row needs both.
  Film copyWith({int? creditsStartMin, DateTime? breaksCheckedAt}) {
    return Film(
      tmdbId: tmdbId,
      title: title,
      durationMin: durationMin,
      posterUrl: posterUrl,
      creditsStartMin: creditsStartMin ?? this.creditsStartMin,
      breaksCheckedAt: breaksCheckedAt ?? this.breaksCheckedAt,
    );
  }

  bool get breaksAreCached => breaksCheckedAt != null;

  /// False when TMDB had no runtime — a schedule cannot be built from
  /// this film until a real duration is known.
  bool get hasKnownDuration => durationMin > 0;
}
