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

/// Real implementation wraps `image_picker` + `google_mlkit_text_recognition`
/// (on-device, no network) plus the fuzzy title match against
/// [TickedRepository.matchFilmByTitle]. This fake stands in for both
/// the OCR pass and the parsing so Upload Ticket → Schedule Card works
/// end to end today.
abstract class TicketOcrService {
  Future<ParsedTicket> parseTicketPhoto(String imagePath);
}

class FakeTicketOcrService implements TicketOcrService {
  @override
  Future<ParsedTicket> parseTicketPhoto(String imagePath) async {
    await Future.delayed(const Duration(milliseconds: 1400));
    final now = DateTime.now();
    return ParsedTicket(
      filmTitleGuess: 'Desert Mirage',
      cinemaNameGuess: 'VOX',
      ticketTimeGuess: DateTime(now.year, now.month, now.day, 21, 0),
      confidence: 0.82,
    );
  }
}

final TicketOcrService appTicketOcrService = FakeTicketOcrService();
