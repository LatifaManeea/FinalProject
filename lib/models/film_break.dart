/// Mirrors a row of `breaks` — one safe window to step out, in minutes
/// from the film's start. Named `FilmBreak` rather than `Break` since
/// the latter collides with the Dart keyword.
class FilmBreak {
  const FilmBreak({
    required this.startMin,
    required this.endMin,
    this.isEstimated = false,
  });

  factory FilmBreak.fromJson(Map<String, dynamic> json) {
    return FilmBreak(
      startMin: json["start_min"],
      endMin: json["end_min"],
      isEstimated: json["is_estimated"] ?? false,
    );
  }

  final int startMin;
  final int endMin;

  /// True when Gemini didn't know this specific film and reasoned from
  /// how films of its kind are usually paced, rather than from its
  /// actual scenes. The screen says which it is — someone deciding
  /// whether to step out during a twist should know whether this is
  /// knowledge or a considered guess.
  final bool isEstimated;

  int get lengthMin => endMin - startMin;
}
