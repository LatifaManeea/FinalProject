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

  final int tmdbId;
  final String title;
  final int durationMin;
  final String? posterUrl;
  final int? creditsStartMin;
  final DateTime? breaksCheckedAt;

  bool get breaksAreCached => breaksCheckedAt != null;
}
