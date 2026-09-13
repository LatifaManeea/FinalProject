import '../models/attendance.dart';
import '../models/branch.dart';
import '../models/cinema.dart';
import '../models/film.dart';
import '../models/film_break.dart';
import '../models/schedule.dart';
import '../models/showtime.dart';
import '../models/yearly_recap.dart';

/// The frozen interface contract from the proposal's two-person work
/// split (section 12) — agreed on day 1, built against a fake
/// repository so every screen could be finished before the backend
/// existed, and now implemented for real by [SupabaseRepository]. The
/// swap cost no screen a single line, which was the point of freezing
/// it.
abstract class TickedRepository {
  // ---- Auth -------------------------------------------------------------
  // Deliberately not here. Auth was in the contract when a fake
  // repository had to stand in for a signed-in session; every auth
  // screen has always called `Database` directly (see auth_flow.dart
  // and splash_screen.dart), so these five methods only ever existed to
  // be faked. Removing them breaks no caller.

  // ---- Reference data -----------------------------------------------------
  Future<List<Cinema>> cinemas();
  Future<List<Branch>> branches(String cinemaName);
  Future<int> adMinutes(String cinemaName, int durationMin);

  // ---- Films ---------------------------------------------------------------
  Future<List<Film>> nowShowing();

  /// Everything playing at one chain, for the Cinemas tab's per-chain
  /// row. Only VOX is scraped today, so the other four chains return an
  /// empty list and the tab shows them with an empty state — see
  /// Database.getFilmsBySource.
  Future<List<Film>> filmsForCinema(String cinemaName);
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
