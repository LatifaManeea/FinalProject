"""Offline check of sync_to_supabase's row-shaping logic (no network,
no real Supabase needed) using the same fixture shapes as test_offline.py."""

from vox_scraper import Movie, Showtime
from sync_to_supabase import build_film_rows, build_branch_rows, build_showtime_rows, scrapeable_movies

movies = [
    Movie(
        title="The Odyssey",
        slug="the-odyssey",
        poster_url="https://assets.voxcinemas.com/posters/x.jpg",
        rating="R15",
        language="English",
        duration_minutes=175,
        showtimes_today=[
            Showtime(branch="Al Qasr Mall - Riyadh", branch_code="0041", screen_type="MAX",
                     time="11:45pm", sold_out=False, booking_id="0041-282953",
                     show_time_iso="2026-09-13T23:45:00+03:00"),
            Showtime(branch="Kingdom Centre - Riyadh", branch_code="0043", screen_type="VIP",
                     time="9:30pm", sold_out=True, booking_id="0043-200603",
                     show_time_iso="2026-09-13T21:30:00+03:00"),
        ],
    ),
    Movie(
        title="Resident Evil",
        slug="resident-evil",
        poster_url="https://assets.voxcinemas.com/posters/y.jpg",
        rating="R18",
        language="English",
        duration_minutes=None,  # not yet released - no runtime on the site yet
        showtimes_today=[],
    ),
]


def test_build_film_rows():
    rows = build_film_rows(movies)
    assert len(rows) == 2
    assert rows[0] == {
        "source": "vox",
        "source_slug": "the-odyssey",
        "title": "The Odyssey",
        "duration_min": 175,
        "poster_url": "https://assets.voxcinemas.com/posters/x.jpg",
    }
    assert rows[1]["duration_min"] is None
    print("build_film_rows: OK")


def test_scrapeable_movies_filters_unknown_duration():
    # Resident Evil has duration_minutes=None (not released yet) and
    # must NOT be synced - Film.durationMin is non-nullable on the
    # Dart side on purpose.
    kept = scrapeable_movies(movies)
    assert [m.slug for m in kept] == ["the-odyssey"]
    print("scrapeable_movies: OK -> filtered out", len(movies) - len(kept), "title(s) with no runtime")


def test_build_branch_rows():
    # NOTE: build_branch_rows() itself is no longer called by sync() -
    # branches is hand-managed now (see fetch_branch_ids() in
    # sync_to_supabase.py) - but the function is kept around and still
    # tested here in case it's ever useful again.
    rows = build_branch_rows(movies)
    assert len(rows) == 2
    by_code = {r["source_code"]: r for r in rows}
    assert by_code["0041"]["branch_name"] == "Al Qasr Mall - Riyadh"
    assert by_code["0041"]["cinema_name"] == "VOX"
    assert by_code["0043"]["branch_name"] == "Kingdom Centre - Riyadh"
    print("build_branch_rows: OK ->", by_code.keys())


def test_build_showtime_rows_happy_path():
    film_id_by_slug = {"the-odyssey": 501, "resident-evil": 502}
    branch_id_by_code = {"0041": 10, "0043": 11}
    rows, skipped = build_showtime_rows(movies, film_id_by_slug, branch_id_by_code)
    assert skipped == 0, skipped
    assert len(rows) == 2
    assert rows[0] == {
        "film_id": 501,
        "branch_id": 10,
        "screen_type": "MAX",
        "show_time": "2026-09-13T23:45:00+03:00",
        "sold_out": False,
        "source_booking_id": "0041-282953",
    }
    assert rows[1]["sold_out"] is True
    print("build_showtime_rows (happy path): OK")


def test_build_showtime_rows_missing_branch():
    # branch 0043 didn't make it into the upsert response (e.g. it was
    # filtered/rejected) - its showtime should be skipped, not crash.
    film_id_by_slug = {"the-odyssey": 501}
    branch_id_by_code = {"0041": 10}
    rows, skipped = build_showtime_rows(movies, film_id_by_slug, branch_id_by_code)
    assert len(rows) == 1
    assert skipped == 1
    print("build_showtime_rows (missing branch): OK")


def test_build_showtime_rows_missing_film():
    # A film that failed to upsert should skip ALL of its showtimes.
    film_id_by_slug = {}
    branch_id_by_code = {"0041": 10, "0043": 11}
    rows, skipped = build_showtime_rows(movies, film_id_by_slug, branch_id_by_code)
    assert len(rows) == 0
    assert skipped == 2
    print("build_showtime_rows (missing film): OK")


if __name__ == "__main__":
    test_build_film_rows()
    test_scrapeable_movies_filters_unknown_duration()
    test_build_branch_rows()
    test_build_showtime_rows_happy_path()
    test_build_showtime_rows_missing_branch()
    test_build_showtime_rows_missing_film()
    print("\nAll offline sync checks passed.")
