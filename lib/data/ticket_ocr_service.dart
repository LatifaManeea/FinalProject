/// What on-device OCR + parsing (Challenge 1) hands back from a ticket
/// photo — every field is a *guess*, never a fact, which is why the
/// Schedule Card treats all of them as editable rather than final.
class ParsedTicket {
  const ParsedTicket({this.filmTitleGuess, this.cinemaNameGuess, this.ticketTimeGuess, required this.confidence});

  final String? filmTitleGuess;
  final String? cinemaNameGuess;
  final DateTime? ticketTimeGuess;

  /// 0–1. Low confidence still returns a best guess — a low-confidence
  /// match degrades into a two-tap correction, never a dead end.
  final double confidence;

  bool get isEmpty => filmTitleGuess == null && cinemaNameGuess == null && ticketTimeGuess == null;
}

/// Thrown while scanning is not implemented. Carries the sentence the
/// Upload Ticket screen shows, which points at manual entry — the path
/// that does work, on real data.
class TicketOcrUnavailable implements Exception {
  const TicketOcrUnavailable();

  @override
  String toString() => 'Reading tickets from a photo isn\'t switched on yet — '
      'enter the details manually and everything else works the same.';
}

/// The real implementation wraps `image_picker` +
/// `google_mlkit_text_recognition` (on-device, no network) and matches
/// the title it reads against [TickedRepository.matchFilmByTitle],
/// which is already real and queries the `films` table.
abstract class TicketOcrService {
  Future<ParsedTicket> parseTicketPhoto(String imagePath);
}

/// Scanning is not built yet, and this says so rather than answering.
///
/// It replaces a stub that returned "The Odyssey" at VOX, 9pm, for
/// every photo it was ever given — the app's last piece of invented
/// data. A wrong answer that looks right is worse than no answer, so
/// this path now refuses honestly and the photo buttons stay in place
/// for when ML Kit is wired up.
class UnavailableTicketOcrService implements TicketOcrService {
  @override
  Future<ParsedTicket> parseTicketPhoto(String imagePath) async {
    throw const TicketOcrUnavailable();
  }
}

final TicketOcrService appTicketOcrService = UnavailableTicketOcrService();
