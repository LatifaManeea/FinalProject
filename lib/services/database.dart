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
/// `films` and `breaks` are the shared cache: any signed-in user may
/// write them, and every user reads what anyone else filled in. That is
/// deliberate — a film's running time and safe windows are the same for
/// everyone, so asking Gemini once per film rather than once per person
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

  // ---- Auth -------------------------------------------------------------

  /// Email confirmation is on, so this returns no user: Supabase sends
  /// the link and there is no session until it is clicked. The
  /// `profiles` row is created by the `on_auth_user_created` trigger
  /// from the [displayName] passed here.
  ///
  /// Signing up with an address that already exists does *not* throw —
  /// Supabase answers as if it worked and quietly sends nothing, so
  /// that a stranger cannot use this form to discover who has an
  /// account. The screen shows "check your inbox" either way.
  Future<void> signUp(String email, String password, String displayName) async {
    try {
      await supabase.auth.signUp(
        email: email,
        password: password,
        data: {"display_name": displayName},
      );
    } catch (error) {
      throw readableAuthError(error);
    }
  }

  /// Sends the confirmation email again — for when the first one never
  /// arrived, or went to spam.
  Future<void> resendConfirmation(String email) async {
    try {
      await supabase.auth.resend(type: OtpType.signup, email: email);
    } catch (error) {
      throw readableAuthError(error);
    }
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

  Future<void> sendPasswordReset(String email) async {
    try {
      await supabase.auth.resetPasswordForEmail(email);
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
      case "email_not_confirmed":
        return Exception("Confirm your email first — check your inbox for the link.");
      case "user_already_exists":
      case "email_exists":
        return Exception("An account with that email already exists.");
      case "weak_password":
        return Exception("That password is too weak — try a longer one.");
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
    final data = await supabase.from("films").select().order("title");

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
        .select()
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
        .select()
        .eq("film_id", filmId)
        .maybeSingle();

    if (data == null) {
      return null;
    }
    return Film.fromJson(data);
  }

  /// The safe windows for a film. An empty list is ambiguous on its own
  /// — it means either "never asked" or "asked, found nothing" — so
  /// read `Film.breaksAreCached` to tell those apart.
  Future<List<FilmBreak>> getBreaks(int filmId) async {
    final data = await supabase
        .from("breaks")
        .select()
        .eq("film_id", filmId)
        .order("start_min");

    List<FilmBreak> allBreaks = [];

    for (var element in data) {
      FilmBreak filmBreak = FilmBreak.fromJson(element);
      allBreaks.add(filmBreak);
    }
    return allBreaks;
  }

  /// Stamps the film as checked once Gemini has answered for it, and
  /// stores the credits minute it found.
  ///
  /// `breaks_checked_at` is set here rather than by the caller, because
  /// stamping it is what makes the cache a cache: a non-null timestamp
  /// with no `breaks` rows means "asked Gemini, found nothing", and is
  /// what stops the same film being sent to Gemini over and over.
  ///
  /// An update, never an insert — every film row is created by a
  /// scraper, which owns `source`, `source_slug` and the runtime. The
  /// app only ever fills in the two columns Gemini answers for.
  Future<void> markBreaksChecked(int filmId, int? creditsStartMin) async {
    await supabase.from("films").update({
      "credits_start_min": creditsStartMin,
      "breaks_checked_at": DateTime.now().toUtc().toIso8601String(),
    }).eq("film_id", filmId);
  }

  /// Caches the safe windows for a film. Call [markBreaksChecked] too —
  /// foreign key on `breaks` needs the film row to exist.
  Future<void> addNewBreaks(int filmId, List<FilmBreak> breaks) async {
    // Replace rather than append: re-asking Gemini for a film must not
    // trip the (film_id, start_min) primary key.
    await supabase.from("breaks").delete().eq("film_id", filmId);

    // Nothing found is a real answer, and the stamp on `films` already
    // recorded it. No rows to write.
    if (breaks.isEmpty) {
      return;
    }

    List<Map<String, dynamic>> rows = [];

    for (var filmBreak in breaks) {
      rows.add({
        "film_id": filmId,
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
        .select()
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
