import 'dart:convert';
import 'dart:typed_data';

import '../models/branch.dart';
import '../models/film.dart';
import '../services/gemini_api.dart';
import 'app_repository.dart';

/// What reading a ticket photo hands back. Every field is optional and
/// already checked against the database: a cinema, branch or film is
/// only here if it really exists, so the Schedule Card can preselect it
/// as-is. Anything missing is left for the person to pick.
class ParsedTicket {
  const ParsedTicket({
    this.cinemaName,
    this.branch,
    this.film,
    this.ticketTime,
    this.titleOnTicket,
  });

  final String? cinemaName;
  final Branch? branch;
  final Film? film;
  final DateTime? ticketTime;

  /// The title exactly as printed, even when it matched no listing —
  /// so the Schedule Card can say which film it couldn't find.
  final String? titleOnTicket;

  bool get isEmpty => cinemaName == null && branch == null && film == null && ticketTime == null;
}

/// Reading the photo failed as a whole: no connection, Gemini busy, or
/// the photo isn't a ticket. Carries the sentence the Upload Ticket
/// screen shows beside its "Enter manually" action.
class TicketScanFailed implements Exception {
  const TicketScanFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class TicketOcrService {
  Future<ParsedTicket> parseTicketPhoto(Uint8List bytes);
}

/// Reads a ticket photo with Gemini vision.
///
/// Not ML Kit: its on-device text recognition has no Arabic script, and
/// Saudi tickets print the film, branch and date in Arabic.
///
/// Gemini is shown the photo together with every cinema, branch and
/// film the app knows, and picks from those lists by id. That turns
/// "مول الرياض بارك" into the Riyadh Park branch and "الأوديسة" into The
/// Odyssey without any string matching here — and every id it returns
/// is checked against the lists before it's trusted.
///
/// One Gemini request per scan (up to four if Google is overloaded —
/// see [GeminiApi.generate]).
class GeminiTicketOcrService implements TicketOcrService {
  final GeminiApi _gemini = GeminiApi();

  @override
  Future<ParsedTicket> parseTicketPhoto(Uint8List bytes) async {
    final catalogue = await _loadCatalogue();

    final String answer;
    try {
      answer = await _gemini.generate([
        {"type": "text", "text": buildPrompt(catalogue, DateTime.now())},
        {"type": "image", "data": base64Encode(bytes), "mime_type": imageMimeType(bytes)},
      ], thinkingLevel: "high");
    } on GeminiFailure catch (failure) {
      throw TicketScanFailed(switch (failure.kind) {
        GeminiFailureKind.offline => 'No internet connection, so the ticket couldn\'t be read.',
        GeminiFailureKind.rejected => 'The ticket couldn\'t be read (${failure.detail}).',
        GeminiFailureKind.busy => 'Gemini is busy right now, so the ticket couldn\'t be read. Try again in a minute.',
      });
    }

    final parsed = readAnswer(answer, catalogue, DateTime.now());
    if (parsed == null) {
      throw const TicketScanFailed('That photo doesn\'t look like a cinema ticket.');
    }
    return parsed;
  }

  /// Every chain with its branches and films, fetched together. These
  /// are Supabase reads, not Gemini requests.
  Future<List<CinemaCatalogue>> _loadCatalogue() async {
    try {
      final cinemas = await appRepository.cinemas();
      return await Future.wait(cinemas.map((cinema) async {
        final (branches, films) =
            await (appRepository.branches(cinema.name), appRepository.filmsForCinema(cinema.name)).wait;
        return CinemaCatalogue(cinema.name, branches, films);
      }));
    } catch (e) {
      throw const TicketScanFailed('Couldn\'t load the cinema list, so the ticket couldn\'t be matched. Check your connection.');
    }
  }

  /// Gemini rejects an image whose declared type doesn't match its
  /// bytes, and image_picker can hand back either PNG (screenshots) or
  /// JPEG, so read the signature rather than trust the file name.
  static String imageMimeType(List<int> bytes) {
    bool startsWith(List<int> sig, [int offset = 0]) {
      if (bytes.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (bytes[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (startsWith([0x89, 0x50, 0x4E, 0x47])) return "image/png";
    if (startsWith([0x52, 0x49, 0x46, 0x46]) && startsWith([0x57, 0x45, 0x42, 0x50], 8)) return "image/webp";
    if (startsWith([0x66, 0x74, 0x79, 0x70], 4)) return "image/heic";
    return "image/jpeg";
  }

  static String buildPrompt(List<CinemaCatalogue> catalogue, DateTime now) {
    final lists = StringBuffer();
    for (final cinema in catalogue) {
      lists.writeln('Cinema "${cinema.name}"');
      lists.writeln('  Branches:');
      for (final b in cinema.branches) {
        lists.writeln('    ${b.id}: ${b.branchName}');
      }
      if (cinema.films.isEmpty) {
        lists.writeln('  Films: (none listed)');
      } else {
        lists.writeln('  Films:');
        for (final f in cinema.films) {
          lists.writeln('    ${f.filmId}: ${f.title}');
        }
      }
    }

    return "This photo should be a cinema ticket from Saudi Arabia, often a "
        "screenshot of a digital ticket. Text may be Arabic, English or both.\n"
        "\n"
        "These are the only cinemas, branches and films the app knows:\n"
        "\n"
        "$lists"
        "\n"
        "Reply with ONLY a JSON object, no prose and no code fences, shaped "
        "exactly:\n"
        "\n"
        "{\"is_ticket\": <true or false>, \"cinema\": <string or null>, "
        "\"branch_id\": <integer or null>, \"film_id\": <integer or null>, "
        "\"title_on_ticket\": <string or null>, \"year\": <integer or null>, "
        "\"month\": <integer or null>, \"day\": <integer or null>, "
        "\"hour\": <integer or null>, \"minute\": <integer or null>}\n"
        "\n"
        "Rules:\n"
        "- \"is_ticket\" is false if the photo is not a cinema ticket or "
        "booking; then set everything else to null.\n"
        "- \"cinema\" must be one of the cinema names above, spelled exactly, "
        "identified from the logo or text on the ticket. Otherwise null.\n"
        "- \"branch_id\" must be an id from that cinema's branches. Branch "
        "names on tickets are often Arabic (\"مول الرياض بارك\" is Riyadh "
        "Park Mall). Null if you can't tell which one — never guess.\n"
        "- \"film_id\" must be an id from that cinema's films. Titles on "
        "tickets are often Arabic translations of English titles (\"الأوديسة\" "
        "is \"The Odyssey\"); ignore age ratings like [R15] and formats like "
        "IMAX. Null if the film isn't in that cinema's list — never pick a "
        "different film because it's close.\n"
        "- \"title_on_ticket\" is the film title as printed, without rating.\n"
        "- Date and time are the showtime printed on the ticket. \"hour\" is "
        "24-hour: \"م\" or PM adds 12 (02:30 م is 14), \"ص\" or AM does not. "
        "Arabic month names: يناير 1, فبراير 2, مارس 3, أبريل 4, مايو 5, "
        "يونيو 6, يوليو 7, أغسطس 8, سبتمبر 9, أكتوبر 10, نوفمبر 11, ديسمبر 12. "
        "\"year\" is null when the ticket doesn't print one — today is "
        "${now.year}-${now.month}-${now.day}, but do not fill it in yourself.\n"
        "- Any field you cannot read clearly is null. A null is fixed with "
        "one tap; a wrong value may not be noticed.";
  }

  /// Null when the photo isn't a ticket or the reply can't be read at
  /// all. Otherwise a [ParsedTicket] holding only what survived checking:
  /// a branch or film from a different cinema than the one read, an id
  /// that doesn't exist, or an impossible date is dropped, not repaired.
  static ParsedTicket? readAnswer(String answer, List<CinemaCatalogue> catalogue, DateTime now) {
    final start = answer.indexOf("{");
    final end = answer.lastIndexOf("}");
    if (start == -1 || end == -1) return null;

    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(answer.substring(start, end + 1));
      if (decoded is! Map<String, dynamic>) return null;
      json = decoded;
    } catch (_) {
      return null;
    }

    if (json["is_ticket"] != true) return null;

    CinemaCatalogue? cinema;
    for (final c in catalogue) {
      if (c.name == json["cinema"]) cinema = c;
    }

    Branch? branch;
    Film? film;
    if (cinema != null) {
      for (final b in cinema.branches) {
        if (b.id == json["branch_id"]) branch = b;
      }
      for (final f in cinema.films) {
        if (f.filmId == json["film_id"]) film = f;
      }
    }

    final title = json["title_on_ticket"];

    return ParsedTicket(
      cinemaName: cinema?.name,
      branch: branch,
      film: film,
      ticketTime: readTicketTime(json, now),
      titleOnTicket: title is String && title.trim().isNotEmpty ? title.trim() : null,
    );
  }

  /// Needs the day and the clock both — a time without a date, or a
  /// date without a time, would put a wrong value on the card that looks
  /// right. A missing year is this year, since tickets often omit it.
  static DateTime? readTicketTime(Map<String, dynamic> json, DateTime now) {
    final year = json["year"] ?? now.year;
    final month = json["month"];
    final day = json["day"];
    final hour = json["hour"];
    final minute = json["minute"];

    if (year is! int || month is! int || day is! int || hour is! int || minute is! int) return null;
    if (month < 1 || month > 12 || day < 1 || hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    final time = DateTime(year, month, day, hour, minute);
    // DateTime rolls 31 June over to 1 July; that's a misread, not a date.
    if (time.month != month || time.day != day) return null;
    return time;
  }
}

/// One chain as Gemini is shown it: the branches and films a ticket from
/// that chain can match.
class CinemaCatalogue {
  const CinemaCatalogue(this.name, this.branches, this.films);

  final String name;
  final List<Branch> branches;
  final List<Film> films;
}

final TicketOcrService appTicketOcrService = GeminiTicketOcrService();
