import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/branch.dart';
import '../models/cinema.dart';
import '../models/film.dart';
import '../models/film_break.dart';
import '../models/showtime.dart';
import '../models/yearly_recap.dart';

/// Everything the app asks of Supabase: auth, and the seven tables.
///
/// `profiles` and `movies_seen` are written only for the signed-in user,
/// which RLS enforces. `cinemas` and `branches` are read-only reference
/// data; `branches` is additionally kept in sync by the VOX scraper for
/// VOX's own branches (see scripts/sync_to_supabase.py).
///
/// `movies` and `breaks` are the shared cache: any signed-in user may
/// write them, and every user reads what anyone else filled in. That is
/// deliberate — a movie's safe windows are the same for
/// everyone, at every cinema, so asking Gemini once per movie rather than once per person
/// is the whole point. It does mean the rows are only as trustworthy as
/// the app writing them, which is why [GeminiApi] validates hard before
/// anything reaches [markBreaksChecked] or [addNewBreaks].
///
/// `showtimes` is read-only from here too, but for a different reason:
/// it is written exclusively by the scraper's service-role key, which
/// bypasses RLS entirely, so there is no `addNewShowtime` — nothing in
/// the app is meant to write one.
class Database {
  final supabase = Supabase.instance.client;

  /// Every read of `films` embeds its movie. A film row is one cinema's
  /// listing; the credits minute and the breaks-checked stamp belong to
  /// the movie, in `movies`, so a listing without its movie can't say
  /// whether breaks are cached. See scripts/add_movies_table.sql.
  static const String filmWithMovie = "*, movies(*)";

  // ---- Auth -------------------------------------------------------------

  /// Registers and signs in, in one step. Email confirmation is off in
  /// the Supabase project, so `signUp` returns a live session and the
  /// new user goes straight into the app — there is no "check your
  /// inbox" step any more.
  ///
  /// The `profiles` row is created by the `on_auth_user_created`
  /// trigger from the [displayName] passed here, so it exists by the
  /// time [getProfile] is called.
  ///
  /// Throws when the address is already registered. That is a real
  /// change of behaviour from confirmation-on, where Supabase
  /// deliberately answered as if sign-up had worked so a stranger could
  /// not use the form to discover who has an account. Without
  /// confirmation that disclosure is unavoidable: a session either
  /// comes back or it doesn't.
  Future<AppUser> signUp(String email, String password, String displayName) async {
    AuthResponse response;

    try {
      response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {"display_name": displayName},
      );
    } catch (error) {
      throw readableAuthError(error);
    }

    final user = response.user;

    // No user back from a project that should hand one straight over —
    // almost always confirmation still switched on in the dashboard.
    // Raised outside the catch above so it isn't rewritten into
    // readableAuthError's generic network message.
    if (user == null) {
      throw Exception(
        "Account created, but this project still requires email confirmation. "
        "Check your inbox, or turn confirmation off in Supabase.",
      );
    }
    return getProfile(user.id);
  }

  Future<AppUser> signIn(String email, String password) async {
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      return await getProfile(response.user!.id);
    } catch (error) {
      throw readableAuthError(error);
    }
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  /// Emails a one-time reset code — not a link.
  ///
  /// A link would redirect to the project's Site URL (localhost by
  /// default) or need deep-link setup, and with PKCE it only works on the
  /// device that asked for it. A code typed into the app works wherever
  /// the email is read. This relies on the dashboard's "Reset Password"
  /// email template printing `{{ .Token }}`; the stock template only has
  /// the link.
  Future<void> sendPasswordReset(String email) async {
    try {
      await supabase.auth.resetPasswordForEmail(email);
    } catch (error) {
      throw readableAuthError(error);
    }
  }

  /// Trades the emailed reset code for a signed-in recovery session, which
  /// is what lets [updatePassword] run next.
  Future<void> verifyResetCode(String email, String code) async {
    try {
      await supabase.auth.verifyOTP(email: email, token: code, type: OtpType.recovery);
    } catch (error) {
      throw readableAuthError(error);
    }
  }

  /// Sets a new password for the signed-in user — during recovery, the
  /// session [verifyResetCode] just created.
  Future<void> updatePassword(String newPassword) async {
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
    } catch (error) {
      throw readableAuthError(error);
    }
  }

  /// Turns a Supabase failure into something worth showing a person.
  ///
  /// An [AuthException] prints as `AuthException(message: Invalid login
  /// credentials, statusCode: 400, code: invalid_credentials)`, and the
  /// auth screens put whatever is thrown straight into the error
  /// banner. So each case the user can actually act on gets a sentence,
  /// and anything unrecognised falls back to Supabase's own message
  /// rather than being swallowed.
  Exception readableAuthError(Object error) {
    if (error is! AuthException) {
      return Exception("Network error — check your connection and try again.");
    }

    switch (error.code) {
      case "invalid_credentials":
        return Exception("Incorrect email or password.");
      // Confirmation is off, so this should never fire. Kept because an
      // account made before it was switched off is still unconfirmed,
      // and that user needs to be told why they can't get in rather
      // than shown Supabase's raw message.
      case "email_not_confirmed":
        return Exception("Confirm your email first — check your inbox for the link.");
      case "user_already_exists":
      case "email_exists":
        return Exception("An account with that email already exists.");
      case "weak_password":
        return Exception("That password is too weak — try a longer one.");
      case "same_password":
        return Exception("That's already your password — choose a different one.");
      // Supabase answers a mistyped code and an expired one the same way.
      case "otp_expired":
        return Exception("That code is wrong or has expired. Check it, or send a new one.");
      case "over_email_send_rate_limit":
      case "over_request_rate_limit":
        return Exception("Too many attempts. Wait a minute, then try again.");
      default:
        return Exception(error.message);
    }
  }

  /// The signed-in person, or null when the session has expired or the
  /// email was never confirmed — what the splash screen decides on.
  Future<AppUser?> getCurrentUser() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      return null;
    }
    return getProfile(user.id);
  }

  Future<AppUser> getProfile(String userId) async {
    final data = await supabase
        .from("profiles")
        .select()
        .eq("profile_id", userId)
        .single();

    return AppUser.fromJson(data);
  }

  Future<void> updateProfile(String userId, String displayName, String? avatarUrl) async {
    await supabase.from("profiles").update({
      "display_name": displayName,
      "avatar_url": avatarUrl,
    }).eq("profile_id", userId);
  }

  // ---- Cinemas and branches ---------------------------------------------

  Future<List<Cinema>> getAllCinemas() async {
    final data = await supabase.from("cinemas").select().order("cinema_name");

    List<Cinema> allCinemas = [];

    for (var element in data) {
      Cinema cinema = Cinema.fromJson(element);
      allCinemas.add(cinema);
    }
    return allCinemas;
  }

  /// One branch by its id — what [SupabaseRepository.buildSchedule]
  /// needs to turn a `branch_id` back into a chain and a place.
  Future<Branch?> getBranch(int branchId) async {
    final data = await supabase
        .from("branches")
        .select()
        .eq("branch_id", branchId)
        .maybeSingle();

    if (data == null) {
      return null;
    }
    return Branch.fromJson(data);
  }

  Future<List<Branch>> getBranches(String cinemaName) async {
    final data = await supabase
        .from("branches")
        .select()
        .eq("cinema_name", cinemaName)
        .order("branch_name");

    List<Branch> allBranches = [];

    for (var element in data) {
      Branch branch = Branch.fromJson(element);
      allBranches.add(branch);
    }
    return allBranches;
  }

  // ---- Films and breaks (the shared cache) ------------------------------

  /// Everything the scrapers have mirrored, by title — the
  /// film picker on the Schedule Card. Titles with no runtime yet are
  /// included: the picker shows them, and `Film.hasKnownDuration` is
  /// what stops a schedule being built from one.
  Future<List<Film>> getNowShowing() async {
    final data = await supabase.from("films").select(filmWithMovie).order("title");

    List<Film> allFilms = [];

    for (var element in data) {
      allFilms.add(Film.fromJson(element));
    }
    return allFilms;
  }

  /// Films whose title contains [query], for matching a title read off
  /// a ticket. `ilike` is Postgres' case-insensitive LIKE, so the
  /// wildcards do the fuzzy part — a short or garbled OCR guess still
  /// finds "Spider-Man: Brand New Day" from "spider".
  Future<List<Film>> searchFilmsByTitle(String query) async {
    final data = await supabase
        .from("films")
        .select(filmWithMovie)
        .ilike("title", "%$query%")
        .order("title");

    List<Film> matches = [];

    for (var element in data) {
      matches.add(Film.fromJson(element));
    }
    return matches;
  }

  /// The cached film, or null when this film has never been mirrored
  /// — in which case the Edge Function has to run before a schedule can
  /// be built.
  Future<Film?> getFilm(int filmId) async {
    final data = await supabase
        .from("films")
        .select(filmWithMovie)
        .eq("film_id", filmId)
        .maybeSingle();

    if (data == null) {
      return null;
    }
    return Film.fromJson(data);
  }

  /// The safe windows for a movie. An empty list is ambiguous on its own
  /// — it means either "never asked" or "asked, found nothing" — so
  /// read `Film.breaksAreCached` to tell those apart.
  ///
  /// Keyed on the movie, not a cinema's listing: every cinema showing
  /// The Odyssey reads the same rows.
  Future<List<FilmBreak>> getBreaks(int movieId) async {
    final data = await supabase
        .from("breaks")
        .select()
        .eq("movie_id", movieId)
        .order("start_min");

    List<FilmBreak> allBreaks = [];

    for (var element in data) {
      FilmBreak filmBreak = FilmBreak.fromJson(element);
      allBreaks.add(filmBreak);
    }
    return allBreaks;
  }

  /// Stamps the movie as checked once Gemini has answered for it, and
  /// stores the credits minute it found.
  ///
  /// `breaks_checked_at` is set here rather than by the caller, because
  /// stamping it is what makes the cache a cache: a non-null timestamp
  /// with no `breaks` rows means "asked Gemini, found nothing", and is
  /// what stops the same movie being sent to Gemini over and over.
  ///
  /// Written to `movies`, not `films`: the answer belongs to the movie,
  /// so a second cinema listing the same movie finds it already stamped.
  /// An update, never an insert — movies are created by a database
  /// trigger when the scraper inserts a film.
  Future<void> markBreaksChecked(int movieId, int? creditsStartMin) async {
    await supabase.from("movies").update({
      "credits_start_min": creditsStartMin,
      "breaks_checked_at": DateTime.now().toUtc().toIso8601String(),
    }).eq("movie_id", movieId);
  }

  /// Caches the safe windows for a movie. Call [markBreaksChecked] too.
  Future<void> addNewBreaks(int movieId, List<FilmBreak> breaks) async {
    // Replace rather than append: re-asking Gemini for a movie must not
    // trip the (movie_id, start_min) primary key.
    await supabase.from("breaks").delete().eq("movie_id", movieId);

    // Nothing found is a real answer, and the stamp on `movies` already
    // recorded it. No rows to write.
    if (breaks.isEmpty) {
      return;
    }

    List<Map<String, dynamic>> rows = [];

    for (var filmBreak in breaks) {
      rows.add({
        "movie_id": movieId,
        "start_min": filmBreak.startMin,
        "end_min": filmBreak.endMin,
        "is_estimated": filmBreak.isEstimated,
      });
    }
    await supabase.from("breaks").insert(rows);
  }

  // ---- Showtimes (read-only — written only by the scraper) --------------

  /// Every showing of [filmId] across all branches, soonest first.
  Future<List<Showtime>> getShowtimesForFilm(int filmId) async {
    final data = await supabase
        .from("showtimes")
        .select()
        .eq("film_id", filmId)
        .order("show_time");

    List<Showtime> allShowtimes = [];

    for (var element in data) {
      allShowtimes.add(Showtime.fromJson(element));
    }
    return allShowtimes;
  }

  /// Every film scraped from one chain's own site — the Cinemas tab's
  /// per-chain row. [source] is the `films.source` token the scraper
  /// stamps each row with ('vox'), which is the direct record of whose
  /// listings a film came from.
  ///
  /// Deliberately *not* joined through `showtimes` → `branches`, which
  /// would look like the more correct question to ask. `branches` is
  /// hand-managed: sync_to_supabase.py only reads it, matching VOX's
  /// own branch codes against `source_code` values someone has to
  /// enter by hand, and silently skips the showtimes of any branch
  /// with no matching row. Until those rows exist, `showtimes` is
  /// empty and that join returns nothing for films that are plainly
  /// in the table. `source` is populated by the same upsert that
  /// writes the film, so it is true the moment a film exists.
  Future<List<Film>> getFilmsBySource(String source) async {
    final data = await supabase
        .from("films")
        .select(filmWithMovie)
        .eq("source", source)
        .order("title");

    List<Film> allFilms = [];

    for (var element in data) {
      allFilms.add(Film.fromJson(element));
    }
    return allFilms;
  }

  // ---- Movies seen ------------------------------------------------------

  /// Writes the inputs that produced a schedule, never the schedule
  /// itself. Returns the new `movie_seen_id`.
  Future<int> addNewMovieSeen(
    String userId,
    int branchId,
    int filmId,
    DateTime ticketTime,
  ) async {
    final data = await supabase
        .from("movies_seen")
        .insert({
          "user_id": userId,
          "branch_id": branchId,
          "film_id": filmId,
          "ticket_time": ticketTime.toUtc().toIso8601String(),
        })
        .select("movie_seen_id")
        .single();

    return data["movie_seen_id"];
  }

  /// One round trip for the History screen. The nested select tells
  /// PostgREST to embed the related rows through the foreign keys, so
  /// each entry arrives with its branch, that branch's chain, and the
  /// film already attached.
  Future<List<Attendance>> getHistory(String userId) async {
    final data = await supabase
        .from("movies_seen")
        .select("*, branches(*, cinemas(*)), films(*)")
        .eq("user_id", userId)
        .order("ticket_time", ascending: false);

    List<Attendance> allSeen = [];

    for (var element in data) {
      Attendance attendance = Attendance.fromJson(element);
      allSeen.add(attendance);
    }
    return allSeen;
  }

  /// The recap card's figures for one year, summed on the device from
  /// the same embedded rows [getHistory] returns.
  Future<YearlyRecap> getRecap(String userId, int year) async {
    final data = await supabase
        .from("movies_seen")
        .select("*, branches(*, cinemas(*)), films(*)")
        .eq("user_id", userId)
        .gte("ticket_time", DateTime.utc(year).toIso8601String())
        .lt("ticket_time", DateTime.utc(year + 1).toIso8601String());

    int totalAdMinutes = 0;
    int totalWatchMinutes = 0;
    Set<String> cinemasVisited = {};

    for (var element in data) {
      Attendance attendance = Attendance.fromJson(element);
      totalAdMinutes += attendance.adMinutes;
      totalWatchMinutes += attendance.durationMin;
      cinemasVisited.add(attendance.cinemaName);
    }

    return YearlyRecap(
      year: year,
      filmsWatched: data.length,
      cinemasVisited: cinemasVisited.length,
      totalAdMinutes: totalAdMinutes,
      totalWatchMinutes: totalWatchMinutes,
    );
  }
}
