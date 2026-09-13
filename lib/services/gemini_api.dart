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
  const BreaksAnswer({required this.creditsStartMin, required this.breaks});

  final int? creditsStartMin;
  final List<FilmBreak> breaks;

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

  Future<BreaksAnswer> getBreaksForFilm(
    String title,
    int year,
    int durationMin,
  ) async {
    String link = "https://generativelanguage.googleapis.com/v1beta/interactions";

    // convert [String] to [Uri]
    Uri uri = Uri.parse(link);

    Map<String, String> header = {
      "x-goog-api-key": dotenv.env["GEMINI_API_KEY"]!,
      "Content-Type": "application/json",
    };

    Map<String, dynamic> body = {
      "model": "gemini-3.8-flash",
      "input": buildPrompt(title, year, durationMin),
    };

    var request = await http.post(uri, headers: header, body: jsonEncode(body));

    if (request.statusCode == 429) {
      throw Exception("Gemini is rate limited, try again shortly");
    }
    if (request.statusCode != 200) {
      throw Exception("Could not load film breaks (${request.statusCode})");
    }

    var response = request.body; // String, we want it as Json
    var responseBody = jsonDecode(response);

    String answer = readText(responseBody);

    return readAnswer(answer, durationMin);
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
  String buildPrompt(String title, int year, int durationMin) {
    return "You are helping cinema-goers decide when they can safely step out "
        "of a screening without missing anything important.\n"
        "\n"
        "Film: \"$title\" ($year), running time $durationMin minutes.\n"
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
        "- If you are not confident about this specific film, return "
        "{\"credits_start_min\": null, \"breaks\": []} rather than guessing.";
  }

  /// Turns Gemini's reply into a [BreaksAnswer], distrusting all of it.
  ///
  /// A model will eventually answer with a credits minute past the end of
  /// the film, two breaks starting on the same minute, or prose wrapped
  /// around the JSON. None of that should reach the timeline, and none of
  /// it would survive the `credits_start_min < duration_min` check or the
  /// `(film_id, start_min)` key if it were ever written to Supabase.
  BreaksAnswer readAnswer(String answer, int durationMin) {
    // Models often wrap JSON in a code fence despite being told not to,
    // so take the outermost object rather than the whole string.
    int start = answer.indexOf("{");
    int end = answer.lastIndexOf("}");

    if (start == -1 || end == -1) {
      return const BreaksAnswer(creditsStartMin: null, breaks: []);
    }

    dynamic jsonBody;
    try {
      jsonBody = jsonDecode(answer.substring(start, end + 1));
    } catch (e) {
      // A reply we cannot read is the same outcome as "nothing found".
      return const BreaksAnswer(creditsStartMin: null, breaks: []);
    }

    return BreaksAnswer(
      creditsStartMin: readCredits(jsonBody["credits_start_min"], durationMin),
      breaks: readBreaks(jsonBody["breaks"], durationMin),
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

  List<FilmBreak> readBreaks(dynamic value, int durationMin) {
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

      list.add(FilmBreak(startMin: startMin, endMin: endMin));
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
