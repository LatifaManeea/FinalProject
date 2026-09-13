import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/film_break.dart';

/// What Gemini answered about one film: where the credits start, and the
/// windows where nothing plot-critical happens.
///
/// Lives in this file rather than in `models/` because nothing else
/// produces one — it only ever comes back from [GeminiApi].
class BreaksAnswer {
  const BreaksAnswer({
    required this.creditsStartMin,
    required this.breaks,
    this.isEstimate = false,
  });

  final int? creditsStartMin;
  final List<FilmBreak> breaks;

  /// True when this came from the estimating pass rather than the
  /// strict one — see [GeminiApi.getBreaksForFilm].
  final bool isEstimate;

  /// Gemini was asked but had nothing usable for this film. The schedule
  /// is still valid, it just has no safe windows marked.
  bool get hasNoKnownBreaks => breaks.isEmpty;
}

/// The safe-break lookup — F5. Asks Gemini where a film can be safely
/// left for a few minutes, and when the credits roll.
class GeminiApi {
  /// Breaks shorter than this are useless — nobody can leave and return.
  static const int minBreakMinutes = 2;

  /// More than this on screen is noise rather than help.
  static const int maxBreaks = 4;

  /// [year] is optional because nothing in the app knows it any more:
  /// `films` is scraped from a cinema's listings, which print a runtime
  /// and a poster but not a release year. The prompt simply leaves it
  /// out when it is null, and leans on the title and runtime instead.
  /// [estimate] swaps the prompt's last rule. Off, the model is told to
  /// return nothing rather than guess about a film it doesn't know —
  /// which, for a catalogue of unreleased and week-old releases, means
  /// it returns nothing almost every time. On, it is told to reason
  /// from how films of this kind are usually paced and answer anyway.
  /// [SupabaseRepository.breaksForFilm] asks the first way, then the
  /// second, so a film the model genuinely knows is never estimated.
  Future<BreaksAnswer> getBreaksForFilm(
    String title,
    int durationMin, {
    int? year,
    bool estimate = false,
  }) async {
    String link = "https://generativelanguage.googleapis.com/v1beta/interactions";

    // convert [String] to [Uri]
    Uri uri = Uri.parse(link);

    Map<String, String> header = {
      "x-goog-api-key": dotenv.env["GEMINI_API_KEY"]!,
      "Content-Type": "application/json",
    };

    Map<String, dynamic> body = {
      "model": "gemini-3.8-flash",
      "input": buildPrompt(title, durationMin, year: year, estimate: estimate),
    };

    var request = await http.post(uri, headers: header, body: jsonEncode(body));

    if (request.statusCode == 429) {
      throw Exception(rateLimitMessage(request.body));
    }
    if (request.statusCode != 200) {
      throw Exception("Could not load film breaks (${request.statusCode})");
    }

    var response = request.body; // String, we want it as Json
    var responseBody = jsonDecode(response);

    String answer = readText(responseBody);

    return readAnswer(answer, durationMin, isEstimate: estimate);
  }

  /// Turns a 429 into a sentence with the actual wait in it.
  ///
  /// The free tier allows 20 requests a minute, and Google's reply says
  /// exactly how long until the window reopens ("Please retry in
  /// 27.387959228s"). That number is the difference between a person
  /// waiting half a minute and assuming the feature is broken, so it is
  /// worth digging out. Falls back to a plain sentence if the body
  /// isn't shaped as expected — an unreadable error must not become a
  /// crash on top of the error.
  String rateLimitMessage(String body) {
    try {
      final message = jsonDecode(body)["error"]?["message"]?.toString() ?? "";
      final seconds = RegExp(r"retry in ([\d.]+)s").firstMatch(message)?.group(1);

      if (seconds != null) {
        final wait = double.parse(seconds).ceil();
        return "Gemini's free tier allows 20 requests a minute, and that's "
            "been reached. Try again in $wait seconds.";
      }
    } catch (_) {
      // Fall through to the generic message below.
    }
    return "Gemini is rate limited, try again shortly.";
  }

  /// Pulls the reply text out of Gemini's `steps` array.
  ///
  /// Found by `type`, not by index: the model puts a `"thought"` step
  /// before its answer, so the text usually sits at `steps[1]` — but
  /// nothing promises that step is always there, and `steps[1]` on a
  /// one-step reply is a range error rather than a readable failure.
  String readText(dynamic responseBody) {
    for (var step in responseBody["steps"] ?? []) {
      if (step["type"] != "model_output") continue;

      for (var part in step["content"] ?? []) {
        if (part["type"] == "text") {
          return part["text"].toString();
        }
      }
    }

    throw Exception("Gemini returned no text");
  }

  /// Asks for bare JSON so the reply can be parsed rather than read.
  String buildPrompt(String title, int durationMin, {int? year, bool estimate = false}) {
    final released = year == null ? "" : " ($year)";

    // The only difference between the two passes. The strict rule is
    // what makes a first-pass answer trustworthy; the estimating rule
    // is what stops an unreleased film returning nothing at all.
    final lastRule = estimate
        ? "- If you do not know this specific film's scenes, do NOT return an "
              "empty list. Reason instead from its title, runtime and likely "
              "genre, and from how films of that kind are usually paced — the "
              "lull after the first act's setup, the stretch before the "
              "climax builds — and give your best windows."
        : "- If you are not confident about this specific film, return "
              "{\"credits_start_min\": null, \"breaks\": []} rather than guessing.";

    return "You are helping cinema-goers decide when they can safely step out "
        "of a screening without missing anything important.\n"
        "\n"
        "Film: \"$title\"$released, running time $durationMin minutes.\n"
        "\n"
        "Reply with ONLY a JSON object, no prose and no code fences, shaped "
        "exactly:\n"
        "\n"
        "{\"credits_start_min\": <integer or null>, \"breaks\": "
        "[{\"start_min\": <integer>, \"end_min\": <integer>}]}\n"
        "\n"
        "Rules:\n"
        "- All values are whole minutes from the first frame of the film, not "
        "from the advertised start time.\n"
        "- \"credits_start_min\" is the minute the end credits begin, or null "
        "if you do not know. It must be less than $durationMin.\n"
        "- Each break is a stretch where nothing plot-critical happens: no "
        "dialogue that matters later, no reveal, no major action beat.\n"
        "- Breaks must be at least $minBreakMinutes minutes long, must not "
        "overlap, and must lie between 0 and $durationMin.\n"
        "- Return at most $maxBreaks breaks, the safest first.\n"
        "$lastRule";
  }

  /// Turns Gemini's reply into a [BreaksAnswer], distrusting all of it.
  ///
  /// A model will eventually answer with a credits minute past the end of
  /// the film, two breaks starting on the same minute, or prose wrapped
  /// around the JSON. None of that should reach the timeline, and none of
  /// it would survive the `credits_start_min < duration_min` check or the
  /// `(film_id, start_min)` key if it were ever written to Supabase.
  BreaksAnswer readAnswer(String answer, int durationMin, {bool isEstimate = false}) {
    // Models often wrap JSON in a code fence despite being told not to,
    // so take the outermost object rather than the whole string.
    int start = answer.indexOf("{");
    int end = answer.lastIndexOf("}");

    if (start == -1 || end == -1) {
      return BreaksAnswer(creditsStartMin: null, breaks: const [], isEstimate: isEstimate);
    }

    dynamic jsonBody;
    try {
      jsonBody = jsonDecode(answer.substring(start, end + 1));
    } catch (e) {
      // A reply we cannot read is the same outcome as "nothing found".
      return BreaksAnswer(creditsStartMin: null, breaks: const [], isEstimate: isEstimate);
    }

    return BreaksAnswer(
      creditsStartMin: readCredits(jsonBody["credits_start_min"], durationMin),
      breaks: readBreaks(jsonBody["breaks"], durationMin, isEstimate: isEstimate),
      isEstimate: isEstimate,
    );
  }

  int? readCredits(dynamic value, int durationMin) {
    if (value is! num) {
      return null;
    }

    int minute = value.round();
    if (minute <= 0 || minute >= durationMin) {
      return null;
    }
    return minute;
  }

  List<FilmBreak> readBreaks(dynamic value, int durationMin, {bool isEstimate = false}) {
    if (value is! List) {
      return [];
    }

    List<FilmBreak> list = [];

    for (var item in value) {
      var rawStart = item["start_min"];
      var rawEnd = item["end_min"];

      if (rawStart is! num || rawEnd is! num) continue;

      int startMin = rawStart.round();
      int endMin = rawEnd.round();

      if (startMin < 0 || endMin > durationMin) continue;
      if (endMin - startMin < minBreakMinutes) continue;

      list.add(FilmBreak(startMin: startMin, endMin: endMin, isEstimated: isEstimate));
    }

    list.sort((a, b) => a.startMin.compareTo(b.startMin));

    // Drop any window that overlaps the one before it.
    List<FilmBreak> spaced = [];
    for (var filmBreak in list) {
      if (spaced.isNotEmpty && filmBreak.startMin < spaced.last.endMin) continue;
      spaced.add(filmBreak);
    }

    if (spaced.length > maxBreaks) {
      return spaced.sublist(0, maxBreaks);
    }
    return spaced;
  }
}
