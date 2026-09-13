import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../constants/tmdb.dart';
import '../models/film.dart';
import '../models/tmdb_summary.dart';
import '../utils/date_format.dart';

/// TMDB, read-only. Three calls: what is on now, what matches a title
/// the OCR read off a ticket, and the details of one film.
///
/// The list endpoints do not return `runtime`, so they hand back
/// [TmdbSummary]. Only [getFilmDetails] can build a real [Film].
class TmdbApi {
  final String apiKey = dotenv.get("TMDB_API_KEY");

  /// The home screen's "now showing" list.
  ///
  /// Not the `now_playing` endpoint: that filters on release dates
  /// registered per country, and Saudi dates are mostly missing from
  /// TMDB, so `region=SA` returned barely half the films actually on
  /// screens. This asks `discover` for popular theatrical releases from
  /// the last [Tmdb.nowShowingWindowDays] days instead — Saudi cinemas
  /// screen largely the same global titles, so popularity over a recent
  /// window is the closer approximation.
  Future<List<TmdbSummary>> getNowPlaying() async {
    DateTime today = DateTime.now();
    DateTime windowStart = today.subtract(
      const Duration(days: Tmdb.nowShowingWindowDays),
    );
    // test new pushes

    String link =
        "${Tmdb.baseUrl}/discover/movie"
        "?api_key=$apiKey"
        "&language=${Tmdb.language}"
        "&sort_by=popularity.desc"
        "&with_release_type=${Uri.encodeComponent(Tmdb.theatricalReleaseTypes)}"
        "&primary_release_date.gte=${formatIsoDate(windowStart)}"
        "&primary_release_date.lte=${formatIsoDate(today)}"
        "&page=1";

    // convert [String] to [Uri]
    Uri uri = Uri.parse(link);

    var response = await http.get(uri);

    // Checked before decoding: a 500 answers with an HTML page, and
    // jsonDecode would throw a FormatException over the top of the
    // message we actually want to show.
    if (response.statusCode != 200) {
      throw Exception("Could not load now showing (${response.statusCode})");
    }

    var jsonBody = jsonDecode(response.body);

    List<TmdbSummary> list = [];
    // The films are inside "results", not at the top level.
    for (var item in jsonBody["results"] ?? []) {
      TmdbSummary film = TmdbSummary.fromJson(item);
      list.add(film);
    }
    return list;
  }

  /// Title search — what the OCR'd ticket title is looked up against.
  Future<List<TmdbSummary>> searchFilms(String query) async {
    String link =
        "${Tmdb.baseUrl}/search/movie"
        "?api_key=$apiKey"
        "&query=${Uri.encodeComponent(query)}"
        "&language=${Tmdb.language}";

    Uri uri = Uri.parse(link);

    var response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("Could not search films (${response.statusCode})");
    }

    var jsonBody = jsonDecode(response.body);

    List<TmdbSummary> list = [];
    for (var item in jsonBody["results"] ?? []) {
      TmdbSummary film = TmdbSummary.fromJson(item);
      list.add(film);
    }
    return list;
  }

  /// TMDB's best guess for a title, or null when nothing matched.
  /// TMDB already returns results most-relevant first, so this is the
  /// top hit — the upload screen should still let the user correct it.
  Future<TmdbSummary?> matchFilmByTitle(String ocrTitle) async {
    List<TmdbSummary> results = await searchFilms(ocrTitle);

    if (results.isEmpty) {
      return null;
    }
    return results.first;
  }

  /// SECOND API - the details screen.
  /// tmdbId comes from the film the user tapped on the list screen.
  /// This is the only endpoint that returns `runtime`, so it is the
  /// only one that can produce a [Film].
  Future<Film> getFilmDetails(int tmdbId) async {
    String link =
        "${Tmdb.baseUrl}/movie/$tmdbId"
        "?api_key=$apiKey"
        "&language=${Tmdb.language}";

    Uri uri = Uri.parse(link);

    var response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception("Could not load film details (${response.statusCode})");
    }

    var jsonBody = jsonDecode(response.body);

    Film film = Film.fromTmdb(jsonBody);
    return film;
  }
}
