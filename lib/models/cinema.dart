/// Mirrors `cinemas`. The ad block is a property of the chain, not the
/// building — every branch of a chain runs the same reel, so the two
/// researched numbers live here rather than on [Branch].
class Cinema {
  const Cinema({
    required this.name,
    required this.shortAdMinutes,
    required this.longAdMinutes,
  });

  /// Primary key — "VOX", "Muvi", "Scene", "Empire", "Cinema House".
  final String name;

  /// Ad block for films under 2 hours.
  final int shortAdMinutes;

  /// Ad block for films 2 hours and over.
  final int longAdMinutes;

  /// The researched number for a film of [durationMin] at this chain.
  int adMinutesFor(int durationMin) => durationMin >= 120 ? longAdMinutes : shortAdMinutes;
}
