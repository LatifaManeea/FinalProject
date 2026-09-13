/// Mirrors `profiles` (F1 / Supabase Auth). `id` is the same uuid as
/// `auth.users.id` — Supabase owns the password, this is everything
/// else about the signed-in person.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
  });

  /// One row of `profiles`. The row itself is created by the
  /// `on_auth_user_created` trigger, not by the app — RLS gives the
  /// client no INSERT on this table.
  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json["profile_id"],
      email: json["email"],
      displayName: json["display_name"],
      avatarUrl: json["avatar_url"],
    );
  }

  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;

  AppUser copyWith({String? displayName, String? avatarUrl}) {
    return AppUser(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
