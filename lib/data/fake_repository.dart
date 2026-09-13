import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/branch.dart';
import '../models/cinema.dart';
import '../models/film.dart';
import '../models/film_break.dart';
import '../models/schedule.dart';
import '../models/showtime.dart';
import '../models/yearly_recap.dart';
import 'ticked_repository.dart';

/// In-memory stand-in for the Supabase-backed repository — the
/// proposal's own day-1 pattern: build every screen against this, swap
/// the real implementation in later without touching a screen.
/// Everything here lives in process memory and resets when the app
/// restarts.
class FakeRepository implements TickedRepository {
  AppUser? _currentUser;
  final List<Attendance> _history = [];
  int _nextAttendanceId = 1;

  // ---- Seed data ------------------------------------------------------------

  final List<Cinema> _cinemas = const [
    Cinema(name: 'VOX', shortAdMinutes: 14, longAdMinutes: 11),
    Cinema(name: 'Muvi', shortAdMinutes: 18, longAdMinutes: 15),
    Cinema(name: 'Scene', shortAdMinutes: 12, longAdMinutes: 9),
    Cinema(name: 'Empire', shortAdMinutes: 20, longAdMinutes: 16),
    Cinema(name: 'Cinema House', shortAdMinutes: 16, longAdMinutes: 13),
  ];

  final List<Branch> _branches = const [
    Branch(id: 1, cinemaName: 'VOX', branchName: 'Riyadh Park', lat: 24.7743, lon: 46.6335),
    Branch(id: 2, cinemaName: 'VOX', branchName: 'Al Nakheel Mall', lat: 24.7256, lon: 46.7223),
    Branch(id: 3, cinemaName: 'Muvi', branchName: 'Panorama Mall', lat: 24.6889, lon: 46.6857),
    Branch(id: 4, cinemaName: 'Scene', branchName: 'Localizer Mall', lat: 24.8149, lon: 46.6577),
    Branch(id: 5, cinemaName: 'Empire', branchName: 'Hayat Mall', lat: 24.6963, lon: 46.6845),
    Branch(id: 6, cinemaName: 'Cinema House', branchName: 'Granada Mall', lat: 24.7605, lon: 46.7998),
  ];

  // Real titles/durations/posters scraped from ksa.voxcinemas.com's
  // "what's on" + per-film pages (scripts/vox_scraper.py). `filmId`
  // below is an arbitrary mock id local to this fake repository —
  // the real Supabase-backed film_id (see schema.sql) is a separate,
  // auto-incrementing id assigned when the scraper upserts a film.
  late final List<Film> _films = [
    Film(
      filmId: 2001,
      title: 'The Odyssey',
      durationMin: 175,
      posterUrl: 'https://assets.voxcinemas.com/posters/P_HO00013488_1783655908489.jpg',
      creditsStartMin: 166,
      breaksCheckedAt: DateTime.now().subtract(const Duration(days: 12)),
    ),
    Film(
      filmId: 2002,
      title: 'Spider-Man: Brand New Day',
      durationMin: 145,
      posterUrl: 'https://assets.voxcinemas.com/posters/P_HO00013065_1782227665332.jpg',
      creditsStartMin: 136,
      breaksCheckedAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    Film(
      filmId: 2003,
      title: 'Practical Magic 2',
      durationMin: 130,
      posterUrl: 'https://assets.voxcinemas.com/posters/P_HO00013352_1786338053973.jpg',
      creditsStartMin: null,
      breaksCheckedAt: DateTime.now().subtract(const Duration(days: 40)),
    ),
    // Uncached on purpose — demonstrates the "first person pays the
    // cost" cache-miss flow (section 9 / demo step 8) the moment
    // someone opens it.
    const Film(
      filmId: 2004,
      title: 'Coyote VS Acme',
      durationMin: 100,
      posterUrl: 'https://assets.voxcinemas.com/posters/P_HO00013137_1786079826557.jpg',
    ),
  ];

  final Map<int, List<FilmBreak>> _breaksByFilm = {
    2001: const [FilmBreak(startMin: 41, endMin: 46), FilmBreak(startMin: 78, endMin: 82)],
    2002: const [
      FilmBreak(startMin: 35, endMin: 40),
      FilmBreak(startMin: 70, endMin: 74),
      FilmBreak(startMin: 112, endMin: 117),
    ],
    2003: const [],
  };

  // ---- Showtimes (prototype — see Showtime's doc comment) ------------------
  // A slice of VOX's own real showtimes (same scrape) at the two VOX
  // branches already seeded above, enough to build/test the UI against
  // before this is a real Supabase table.
  late final List<Showtime> _showtimes = [
    Showtime(branchId: 1, filmId: 2001, screenType: 'IMAX', time: _todayAt(21, 0)),
    Showtime(branchId: 1, filmId: 2001, screenType: 'IMAX', time: _todayAt(0, 30, addDays: 1)),
    Showtime(branchId: 2, filmId: 2001, screenType: 'VIP', time: _todayAt(21, 30), soldOut: true),
    Showtime(branchId: 1, filmId: 2002, screenType: 'MAX', time: _todayAt(20, 15)),
    Showtime(branchId: 2, filmId: 2003, screenType: 'Standard', time: _todayAt(19, 45)),
  ];

  DateTime _todayAt(int hour, int minute, {int addDays = 0}) {
    final now = DateTime.now().add(Duration(days: addDays));
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  Cinema _cinemaByName(String name) => _cinemas.firstWhere((c) => c.name == name);

  // ---- Auth -------------------------------------------------------------

  @override
  Future<AppUser> register(String email, String password, String displayName) async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (email == 'taken@ticked.app') {
      throw Exception('An account with that email already exists.');
    }
    final user = AppUser(id: 'demo-${DateTime.now().millisecondsSinceEpoch}', email: email, displayName: displayName);
    _currentUser = user;
    return user;
  }

  @override
  Future<AppUser> signIn(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (email == 'offline@test.com') {
      throw Exception('Network error — check your connection and try again.');
    }
    if (password == 'wrong') {
      throw Exception('Incorrect email or password.');
    }
    final user = AppUser(id: 'demo-${email.hashCode}', email: email, displayName: email.split('@').first);
    _currentUser = user;
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await Future.delayed(const Duration(milliseconds: 600));
  }

  @override
  Future<AppUser?> currentUser() async => _currentUser;

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }

  void setCurrentUserForDemo(AppUser user) => _currentUser = user;

  // ---- Reference data -----------------------------------------------------

  @override
  Future<List<Cinema>> cinemas() async => List.unmodifiable(_cinemas);

  @override
  Future<List<Branch>> branches(String cinemaName) async =>
      _branches.where((b) => b.cinemaName == cinemaName).toList();

  @override
  Future<int> adMinutes(String cinemaName, int durationMin) async =>
      _cinemaByName(cinemaName).adMinutesFor(durationMin);

  // ---- Films (fake) ---------------------------------------------------------

  @override
  Future<List<Film>> nowShowing() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return List.unmodifiable(_films);
  }

  @override
  Future<Film?> matchFilmByTitle(String ocrTitle) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final needle = ocrTitle.toLowerCase().trim();
    if (needle.isEmpty) return null;
    for (final f in _films) {
      if (f.title.toLowerCase().contains(needle) || needle.contains(f.title.toLowerCase())) {
        return f;
      }
    }
    // Unrecognised OCR text still resolves to *something* so the demo
    // flow (and the Schedule Card fallback path) always has a film to
    // show, editable like every other field.
    return _films.first;
  }

  @override
  Future<Film> filmDetails(int filmId) async => _films.firstWhere((f) => f.filmId == filmId);

  // ---- Scheduling -----------------------------------------------------------

  @override
  Future<Schedule> buildSchedule({
    required int branchId,
    required int filmId,
    required DateTime ticketTime,
  }) async {
    final branch = _branches.firstWhere((b) => b.id == branchId);
    final film = await filmDetails(filmId);
    final ad = await adMinutes(branch.cinemaName, film.durationMin);
    final breaks = await breaksForFilm(filmId);
    return Schedule(branch: branch, film: film, ticketTime: ticketTime, adMinutes: ad, breaks: breaks);
  }

  @override
  Future<List<FilmBreak>> breaksForFilm(int filmId) async {
    final film = _films.firstWhere((f) => f.filmId == filmId, orElse: () => _films.first);

    if (film.breaksAreCached) {
      // Cache hit — including a correct negative cache (checked, none
      // found), which "Practical Magic 2" (2003) demonstrates.
      return List.unmodifiable(_breaksByFilm[filmId] ?? const []);
    }

    // Cache miss — simulates the Edge Function round trip to Gemini.
    // Only "Coyote VS Acme" (2004) is seeded uncached, matching the
    // demo script's "open a second, uncached film" beat.
    await Future.delayed(const Duration(seconds: 2));
    final generated = const [FilmBreak(startMin: 44, endMin: 49)];
    _breaksByFilm[filmId] = generated;

    final index = _films.indexWhere((f) => f.filmId == filmId);
    if (index != -1) {
      _films[index] = Film(
        filmId: film.filmId,
        title: film.title,
        durationMin: film.durationMin,
        posterUrl: film.posterUrl,
        creditsStartMin: film.durationMin - 8,
        breaksCheckedAt: DateTime.now(),
      );
    }
    return generated;
  }

  // ---- Showtimes (prototype, see Showtime's doc comment) -------------------

  @override
  Future<List<Showtime>> showtimesForFilm(int filmId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_showtimes.where((s) => s.filmId == filmId));
  }

  // ---- Attendance -----------------------------------------------------------

  @override
  Future<int> recordAttendance(Schedule schedule) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final id = _nextAttendanceId++;
    _history.insert(
      0,
      Attendance(
        id: id,
        filmTitle: schedule.film.title,
        posterUrl: schedule.film.posterUrl,
        cinemaName: schedule.branch.cinemaName,
        branchName: schedule.branch.branchName,
        ticketTime: schedule.ticketTime,
        adMinutes: schedule.adMinutes,
        durationMin: schedule.film.durationMin,
      ),
    );
    return id;
  }

  // ---- History ----------------------------------------------------------

  @override
  Future<List<Attendance>> history() async => List.unmodifiable(_history);

  @override
  Future<YearlyRecap> recap(int year) async {
    final rows = _history.where((a) => a.ticketTime.year == year).toList();
    final cinemasVisited = rows.map((a) => a.cinemaName).toSet().length;
    final totalAd = rows.fold<int>(0, (sum, a) => sum + a.adMinutes);
    final totalWatch = rows.fold<int>(0, (sum, a) => sum + a.adMinutes + a.durationMin);
    return YearlyRecap(
      year: year,
      filmsWatched: rows.length,
      cinemasVisited: cinemasVisited,
      totalAdMinutes: totalAd,
      totalWatchMinutes: totalWatch,
    );
  }
}
