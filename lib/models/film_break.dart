/// Mirrors a row of `breaks` — one safe window to step out, in minutes
/// from the film's start. Named `FilmBreak` rather than `Break` since
/// the latter collides with the Dart keyword.
class FilmBreak {
  const FilmBreak({required this.startMin, required this.endMin});

  factory FilmBreak.fromJson(Map<String, dynamic> json) {
    return FilmBreak(
      startMin: json["start_min"],
      endMin: json["end_min"],
    );
  }

  final int startMin;
  final int endMin;

  int get lengthMin => endMin - startMin;
}
