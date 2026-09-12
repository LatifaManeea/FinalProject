/// Mirrors a row of `breaks` — one safe window to step out, in minutes
/// from the film's start. Named `FilmBreak` rather than `Break` since
/// the latter collides with the Dart keyword.
class FilmBreak {
  const FilmBreak({required this.startMin, required this.endMin});

  final int startMin;
  final int endMin;

  int get lengthMin => endMin - startMin;
}
