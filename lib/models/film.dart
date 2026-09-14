/// One cinema's listing of a film — a row of `films`, carrying its own
/// Gemini answers (`credits_start_min`, `breaks_checked_at`) directly.
///
/// There used to be a separate `movies` table shared across chains, so
/// VOX's and Muvi's listings of the same title asked Gemini once between
/// them (see the old scripts/add_movies_table.sql). That table has been
/// dropped — each cinema's listing now caches its own answer, so the
/// same title showing at two chains asks Gemini twice. Simpler, at that
/// cost.
///
/// `breaksCheckedAt` is the two-state-encodes-three-outcomes column from
/// the proposal: null means never asked; non-null with no [FilmBreak]
/// rows means asked and nothing usable was found.
class Film {
  const Film({
    required this.filmId,
    required this.movieId,
    required this.title,
    required this.durationMin,
    this.source,
    this.sourceSlug,
    this.posterUrl,
    this.creditsStartMin,
    this.breaksCheckedAt,
  });

  /// A `films` row, ideally with its movie embedded — queried as
  /// `select("*, movies(*)")`. Without the embed (history rows don't need
  /// it) the credits and checked-at simply come through null; nothing
  /// that reads history uses them.
  factory Film.fromJson(Map<String, dynamic> json) {
    final checkedAt = json["breaks_checked_at"];

    return Film(
      filmId: json["film_id"],
      // No separate `movies` table any more — this listing's own row is
      // what breaks/credits are cached against, so this is just filmId.
      movieId: json["film_id"],
      title: json["title"],
      // `duration_min` is nullable in the schema — VOX leaves the
      // runtime off titles that haven't opened yet. 0 carries that
      // through as "unknown", which [hasKnownDuration] reads.
      durationMin: json["duration_min"] ?? 0,
      source: json["source"],
      sourceSlug: json["source_slug"],
      posterUrl: json["poster_url"],
      creditsStartMin: json["credits_start_min"],
      breaksCheckedAt: checkedAt == null ? null : DateTime.parse(checkedAt).toLocal(),
    );
  }

  /// This cinema's listing.
  final int filmId;

  /// Breaks/credits are cached against this — equal to [filmId] now
  /// that there is no separate `movies` table (see the class doc).
  final int movieId;

  final String title;
  final int durationMin;

  /// Which cinema's site this film was scraped from ('vox'), and that
  /// site's own slug for it ('the-odyssey'). Together they're the
  /// film's identity at the source, which is what [bookingUrl] rebuilds
  /// a link out of. Null only for a row written before the scraper
  /// existed.
  final String? source;
  final String? sourceSlug;
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
      movieId: movieId,
      title: title,
      durationMin: durationMin,
      source: source,
      sourceSlug: sourceSlug,
      posterUrl: posterUrl,
      creditsStartMin: creditsStartMin ?? this.creditsStartMin,
      breaksCheckedAt: breaksCheckedAt ?? this.breaksCheckedAt,
    );
  }

  /// Where each scraped site's own film page lives, as a template the
  /// slug is substituted into. The scraper builds the very same URL to
  /// read the runtime and poster off (`f"{BASE}/movies/{slug}"` in
  /// vox_scraper.py), so a link built here lands on the page the row
  /// came from — the one with that cinema's own booking flow on it.
  /// Adding a chain is one line here — the key is the `films.source`
  /// token its scraper stamps rows with, the value is everything before
  /// the slug. Take both from the scraper itself rather than from a
  /// browser's address bar: the scraper already has to build this exact
  /// URL to read the film's page, so its `BASE` and its slug are the
  /// two halves that are known to work together.
  ///
  /// The other four chains are deliberately absent rather than guessed.
  /// A wrong template here would send someone to a 404 on a cinema's
  /// real site, which is worse than no link — and until their scrapers
  /// exist there are no films with those sources anyway.
  static const Map<String, String> _filmPageBySource = {
    'vox': 'https://ksa.voxcinemas.com/movies/',
    'muvi': 'https://www.muvicinemas.com/en/movies/',
    // 'scene': 'https://.../',
    // 'reel': 'https://.../',
    // 'cinema-house': 'https://.../',
  };

  /// The cinema's own page for this film, or null when the film was
  /// scraped from a site with no template on record — in which case no
  /// link is shown rather than a guessed one.
  Uri? get bookingUrl {
    final base = _filmPageBySource[source];
    final slug = sourceSlug;

    if (base == null || slug == null || slug.isEmpty) {
      return null;
    }
    return Uri.parse('$base$slug');
  }

  /// Two rows for the same `film_id` are the same film, whichever
  /// query built them. Without this, a film tapped on the Cinemas tab
  /// (from `filmsForCinema`) and the same film in the Schedule Card's
  /// picker (from `nowShowing`) are two unequal objects, and
  /// DropdownButton asserts that its value matches exactly one item.
  @override
  bool operator ==(Object other) => other is Film && other.filmId == filmId;

  @override
  int get hashCode => filmId.hashCode;

  bool get breaksAreCached => breaksCheckedAt != null;

  /// False when the source site had no runtime listed yet (VOX leaves
  /// this off for titles that haven't opened) — a schedule cannot be
  /// built from this film until a real duration is known.
  bool get hasKnownDuration => durationMin > 0;
}
