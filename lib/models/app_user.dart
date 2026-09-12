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
