import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/branch.dart';
import '../models/cinema.dart';
import '../models/film.dart';
import '../models/film_break.dart';
import '../models/schedule.dart';
import '../models/showtime.dart';
import '../models/yearly_recap.dart';

/// The frozen interface contract from the proposal's two-person work
/// split (section 12) — agreed on day 1, implemented behind
/// [FakeRepository] for now so every screen below can be built and
/// navigated today, then swapped for the real Supabase-backed
/// implementation without any screen code changing.
abstract class TickedRepository {
  // ---- Auth -------------------------------------------------------------
  Future<AppUser> register(String email, String password, String displayName);
  Future<AppUser> signIn(String email, String password);
  Future<void> sendPasswordReset(String email);
  Future<AppUser?> currentUser();
  Future<void> signOut();

  // ---- Reference data -----------------------------------------------------
  Future<List<Cinema>> cinemas();
  Future<List<Branch>> branches(String cinemaName);
  Future<int> adMinutes(String cinemaName, int durationMin);

  // ---- Films ---------------------------------------------------------------
  Future<List<Film>> nowShowing();
  Future<Film?> matchFilmByTitle(String ocrTitle);
  Future<Film> filmDetails(int filmId);

  // ---- Scheduling -----------------------------------------------------------
  Future<Schedule> buildSchedule({
    required int branchId,
    required int filmId,
    required DateTime ticketTime,
  });

  /// Cache-first, Edge Function on miss. Also fills `creditsStartMin`
  /// and guarantees the film row exists, which recording attendance
  /// depends on.
  Future<List<FilmBreak>> breaksForFilm(int filmId);

  // ---- Showtimes ------------------------------------------------------------
  /// Every showing of [filmId] across all branches, soonest first.
  /// Real implementation reads the `showtimes` table (written only by
  /// the scraper's service-role key — see Database.getShowtimesForFilm
  /// and scripts/sync_to_supabase.py).
  Future<List<Showtime>> showtimesForFilm(int filmId);

  // ---- Attendance -----------------------------------------------------------
  Future<int> recordAttendance(Schedule schedule);

  // ---- History — scoped to the signed-in user in the real backend (RLS) ----
  Future<List<Attendance>> history();
  Future<YearlyRecap> recap(int year);
}
