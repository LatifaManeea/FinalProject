/// Everything about TMDB that is a fixed address rather than a
/// decision: where the API lives, where its images live, and the
/// settings every request carries.
class Tmdb {
  static const String baseUrl = "https://api.themoviedb.org/3";

  /// Posters come back as a bare path, so they need a size prefix.
  /// w500 is the usual poster width — big enough for a card, small
  /// enough not to waste the download.
  static const String imageBaseUrl = "https://image.tmdb.org/t/p/w500";

  /// English titles: what is printed on the tickets the OCR reads.
  static const String language = "en-US";

  /// How far back "now showing" reaches. Films stay on screens for
  /// roughly two months, so this is the window `discover` is asked for.
  static const int nowShowingWindowDays = 60;

  /// Theatrical releases only — `3` is a wide release, `2` limited.
  /// Without this, `discover` also returns straight-to-streaming and
  /// digital-only titles, which are never on a cinema ticket.
  static const String theatricalReleaseTypes = "3|2";

  /// Kept for reference, deliberately unused: filtering `now_playing`
  /// or `discover` by `region=SA` drops most films actually screening
  /// here, because Saudi release dates are often never registered with
  /// TMDB. Popularity over the recent window tracks the real listings
  /// far better. Revisit if TMDB's Saudi coverage improves.
  static const String region = "SA";

  /// Turns TMDB's `"poster_path": "/abc.jpg"` into a URL that
  /// `Image.network` can actually load. Null stays null: plenty of
  /// films have no poster.
  static String? posterUrl(String? posterPath) {
    if (posterPath == null) {
      return null;
    }
    return "$imageBaseUrl$posterPath";
  }
}
