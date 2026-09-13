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

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json["branch_id"],
      cinemaName: json["cinema_name"],
      branchName: json["branch_name"],
      // `double precision` comes back as an int when the value is
      // whole, so widen rather than cast.
      lat: (json["lat"] as num?)?.toDouble(),
      lon: (json["lon"] as num?)?.toDouble(),
    );
  }

  final int id;
  final String cinemaName;
  final String branchName;
  final double? lat;
  final double? lon;

  String get displayName => '$cinemaName · $branchName';
}
