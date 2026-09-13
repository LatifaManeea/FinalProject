import '../constants/tmdb.dart';

/// One entry of a TMDB list — `now_playing` or `search/movie`.
///
/// Deliberately smaller than [Film]: those endpoints do not return
/// `runtime`, and a [Film] without a duration would be a lie every
/// schedule calculation depends on. Pick one of these and fetch
/// `TmdbApi.getFilmDetails` to get the real thing.
class TmdbSummary {
  const TmdbSummary({
    required this.tmdbId,
    required this.title,
    this.posterUrl,
    this.releaseDate,
  });

  factory TmdbSummary.fromJson(Map<String, dynamic> json) {
    final released = json["release_date"];

    return TmdbSummary(
      tmdbId: json["id"],
      title: json["title"],
      posterUrl: Tmdb.posterUrl(json["poster_path"]),
      // Unreleased films come back with an empty string, not null.
      releaseDate: (released == null || released == "") ? null : DateTime.parse(released),
    );
  }

  final int tmdbId;
  final String title;
  final String? posterUrl;
  final DateTime? releaseDate;
}
