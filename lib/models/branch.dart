/// Mirrors `branches`. Kept separate from [Cinema] purely so a
/// location — and distance — can be shown; timing never lives here.
class Branch {
  const Branch({
    required this.id,
    required this.cinemaName,
    required this.branchName,
    this.lat,
    this.lon,
  });

  final int id;
  final String cinemaName;
  final String branchName;
  final double? lat;
  final double? lon;

  String get displayName => '$cinemaName · $branchName';
}
