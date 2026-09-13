"""
Pushes what vox_scraper.py scrapes straight into Supabase: films and
today's showtimes. Run schema.sql in the Supabase SQL Editor once
before ever running this.

branches is hand-managed, not touched by this script
------------------------------------------------------
branches is static reference data you fill in and keep accurate by
hand in Supabase - this script only ever READS it (to match a scraped
VOX branch code to the branch_id you assigned that branch) and never
writes to it. For that matching to work, every Riyadh branch's row
needs source='vox' and source_code set to VOX's own code for it (the
number in its booking ids, e.g. "0034" for Riyadh Park) - see
fetch_branch_ids()'s docstring. A branch with no matching row, or a
wrong source_code, just has its showtimes silently skipped.

Needs a scripts/.env file (NOT the Flutter app's root .env — see why
below) with:

    SUPABASE_URL=https://<project>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY=<service role key, from Project Settings > API>

Why a separate .env from the app's
-----------------------------------
The Flutter app's root .env is listed under pubspec.yaml's `assets:`,
which means its entire contents get bundled into the compiled app and
ship to every phone that installs it. That's fine for SUPABASE_URL and
the publishable/anon key (they're meant to be public — Postgres RLS is
what actually protects the data), but the service role key below
BYPASSES row-level security completely. It must never end up in a file
that gets bundled into the app. Keep it only here, in scripts/.env — a
different file from the app's, and (confirmed, not assumed) also
gitignored, since the project's ".env" line in .gitignore matches at
any folder depth.

Usage
-----
    pip install curl_cffi requests beautifulsoup4
    python3 sync_to_supabase.py

(vox_scraper.py needs curl_cffi to get past this site's Akamai bot
protection — see the "Why curl_cffi" note at the top of that file. The
upserts below talk to Supabase directly, which isn't behind that
protection, so they still use plain `requests`.)

(No python-dotenv dependency — scripts/.env is read by hand below so
this doesn't add one more package to keep installed.)
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import requests

from vox_scraper import Movie, scrape_all

SCRIPT_DIR = Path(__file__).resolve().parent

CINEMA_NAME = "VOX"
SOURCE = "vox"


def _load_env() -> tuple[str | None, str | None]:
    """Reads scripts/.env by hand rather than adding a hard dependency
    on python-dotenv, which may not be installed yet on a fresh machine.
    A real env var (already exported) always wins over the file."""
    env_path = SCRIPT_DIR / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))
    return os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_SERVICE_ROLE_KEY")


def _headers(service_role_key: str, prefer: str) -> dict:
    return {
        "apikey": service_role_key,
        "Authorization": f"Bearer {service_role_key}",
        "Content-Type": "application/json",
        "Prefer": prefer,
    }


def _upsert(supabase_url: str, service_role_key: str, table: str, rows: list[dict], on_conflict: str) -> list[dict]:
    """POSTs an upsert and returns the affected rows (with their ids),
    via PostgREST's merge-duplicates + return=representation."""
    if not rows:
        return []
    url = f"{supabase_url}/rest/v1/{table}?on_conflict={on_conflict}"
    resp = requests.post(
        url,
        headers=_headers(service_role_key, "resolution=merge-duplicates,return=representation"),
        json=rows,
        timeout=30,
    )
    if resp.status_code >= 300:
        raise RuntimeError(f"Upsert into {table} failed ({resp.status_code}): {resp.text}")
    return resp.json()


def _select(supabase_url: str, service_role_key: str, table: str, query: str) -> list[dict]:
    """GETs rows from a table via PostgREST. `query` is a raw query
    string, e.g. "source=eq.vox&select=branch_id,source_code"."""
    url = f"{supabase_url}/rest/v1/{table}?{query}"
    resp = requests.get(url, headers=_headers(service_role_key, "return=representation"), timeout=30)
    if resp.status_code >= 300:
        raise RuntimeError(f"Select from {table} failed ({resp.status_code}): {resp.text}")
    return resp.json()


def scrapeable_movies(movies: list[Movie]) -> list[Movie]:
    """Films.duration_min is NOT NULL in spirit even though the column
    allows it (see Film.durationMin on the Dart side, which is
    non-nullable on purpose — the whole ad/break schedule is computed
    from it). VOX itself has no runtime yet for a few not-yet-released
    re-releases; skip those rather than writing a film nothing can be
    scheduled from. They'll sync in automatically once VOX lists a
    runtime for them."""
    return [m for m in movies if m.duration_minutes is not None]


def build_film_rows(movies: list[Movie]) -> list[dict]:
    return [
        {
            "source": SOURCE,
            "source_slug": m.slug,
            "title": m.title,
            "duration_min": m.duration_minutes,
            "poster_url": m.poster_url,
        }
        for m in movies
    ]


def build_branch_rows(movies: list[Movie]) -> list[dict]:
    """One row per distinct branch code seen across every movie's
    showtimes today. dict preserves first-seen name per code.

    NOT called by sync() anymore - branches is hand-managed (kept
    static, edited by hand in Supabase) rather than auto-upserted by
    the daily job. Kept here (and still covered by
    test_sync_offline.py) in case it's ever useful again - e.g. to see
    what the scraper WOULD propose for branches without writing
    anything. See fetch_branch_ids() for what the daily sync uses
    instead."""
    branches_seen: dict[str, str] = {}
    for m in movies:
        for st in m.showtimes_today:
            branches_seen.setdefault(st.branch_code, st.branch)
    return [
        {"cinema_name": CINEMA_NAME, "branch_name": name, "source": SOURCE, "source_code": code}
        for code, name in branches_seen.items()
    ]


def fetch_branch_ids(supabase_url: str, service_role_key: str) -> dict[str, int]:
    """branches is hand-managed, static reference data (filled in and
    kept accurate by hand in Supabase) - the daily sync only ever
    READS it here, to match each VOX branch code to the branch_id you
    assigned it, and never writes to the table. A scraped branch code
    with no matching row here (e.g. VOX opens a new Riyadh location,
    or a row's source_code doesn't exactly match VOX's code) has its
    showtimes silently skipped - see the "skipped" count sync() prints."""
    rows = _select(supabase_url, service_role_key, "branches", "source=eq.vox&select=branch_id,source_code")
    return {row["source_code"]: row["branch_id"] for row in rows if row.get("source_code")}


def normalise_branch_name(name: str) -> str:
    """A branch name reduced to something two sources can agree on.

    VOX prints "Riyadh Park - Riyadh"; the row in `branches` says
    "Riyadh Park". Lowercase, drop anything after " - ", collapse
    whitespace."""
    return " ".join(name.split(" - ")[0].split()).casefold()


def fetch_branch_ids_by_name(supabase_url: str, service_role_key: str) -> dict[str, int]:
    """Fallback lookup for branches that have no source_code yet.

    Matching on source_code is the right way round — codes are stable
    and names are not — but it only works once someone has filled those
    codes in, and until then EVERY showtime is skipped while the sync
    still reports success. That failure is silent and it cost us a
    while to spot.

    So: match on the code when it's there, and fall back to the name
    when it isn't. The fallback is deliberately narrow (VOX rows only,
    normalised, and a name claimed by two rows is dropped rather than
    guessed at) because a wrong branch here puts a screening at the
    wrong cinema."""
    rows = _select(
        supabase_url, service_role_key, "branches", "cinema_name=eq.VOX&select=branch_id,branch_name"
    )

    by_name: dict[str, int] = {}
    ambiguous: set[str] = set()

    for row in rows:
        key = normalise_branch_name(row["branch_name"])
        if key in by_name:
            ambiguous.add(key)
        by_name[key] = row["branch_id"]

    for key in ambiguous:
        print(f"  ! two branches both normalise to {key!r} — matching neither by name.")
        del by_name[key]

    return by_name


def build_showtime_rows(
    movies: list[Movie],
    film_id_by_slug: dict[str, int],
    branch_id_by_code: dict[str, int],
    branch_id_by_name: dict[str, int] | None = None,
) -> tuple[list[dict], int]:
    """Returns (rows, skipped_count). A showtime is skipped if its film
    or branch didn't make it into the upsert responses above, or if the
    time text couldn't be parsed into a real timestamp.

    [branch_id_by_name] is the fallback for branch rows with no
    source_code filled in — see fetch_branch_ids_by_name()."""
    by_name = branch_id_by_name or {}
    rows = []
    skipped = 0
    for m in movies:
        film_id = film_id_by_slug.get(m.slug)
        if film_id is None:
            skipped += len(m.showtimes_today)
            continue
        for st in m.showtimes_today:
            branch_id = branch_id_by_code.get(st.branch_code)
            if branch_id is None:
                branch_id = by_name.get(normalise_branch_name(st.branch))
            if branch_id is None or st.show_time_iso is None:
                skipped += 1
                continue
            rows.append(
                {
                    "film_id": film_id,
                    "branch_id": branch_id,
                    "screen_type": st.screen_type,
                    "show_time": st.show_time_iso,
                    "sold_out": st.sold_out,
                    "source_booking_id": st.booking_id,
                }
            )
    return rows, skipped


def sync(movies: list[Movie], supabase_url: str, service_role_key: str) -> None:
    all_movies = movies
    movies = scrapeable_movies(movies)
    skipped_no_duration = len(all_movies) - len(movies)
    if skipped_no_duration:
        print(f"Skipping {skipped_no_duration} title(s) with no runtime listed yet (not synced).")

    saved_films = _upsert(supabase_url, service_role_key, "films", build_film_rows(movies), on_conflict="source,source_slug")
    film_id_by_slug = {row["source_slug"]: row["film_id"] for row in saved_films}
    print(f"Upserted {len(saved_films)} films.")

    # branches is hand-managed - only read from, never written to. See
    # fetch_branch_ids()'s docstring for what happens when a scraped
    # branch code has no matching row here.
    branch_id_by_code = fetch_branch_ids(supabase_url, service_role_key)
    branch_id_by_name = fetch_branch_ids_by_name(supabase_url, service_role_key)
    print(
        f"Matched against {len(branch_id_by_code)} branch(es) by source_code, "
        f"{len(branch_id_by_name)} available by name as a fallback."
    )
    if not branch_id_by_code and branch_id_by_name:
        print(
            "  note: no VOX branch has source/source_code set, so matching is "
            "by name this run. Run --propose-branches to fill those in."
        )

    showtime_rows, skipped = build_showtime_rows(
        movies, film_id_by_slug, branch_id_by_code, branch_id_by_name
    )
    saved_showtimes = _upsert(
        supabase_url, service_role_key, "showtimes", showtime_rows, on_conflict="branch_id,source_booking_id"
    )
    note = f" ({skipped} skipped — no matching film/branch or unparsed time)" if skipped else ""
    print(f"Upserted {len(saved_showtimes)} showtimes.{note}")


def print_proposed_branches(movies: list[Movie]) -> None:
    """Prints the VOX branches today's scrape saw, as SQL you can read
    before running.

    This exists because `branches` is hand-managed on purpose: the
    daily sync only ever reads it, so it can never invent a cinema
    location. The catch is that until those rows exist, every scraped
    showtime is skipped for want of a branch_id, and `showtimes` stays
    empty while the sync still reports success.

    So: this writes nothing. It shows what the scrape found, you check
    the names are ones you want, and you run the SQL yourself. After
    that the daily sync matches on source_code and fills showtimes.
    """
    rows = build_branch_rows(movies)

    if not rows:
        print("No Riyadh branches found in today's scrape — nothing to propose.")
        return

    print(f"-- {len(rows)} VOX branch(es) seen in today's scrape.")
    print("-- These are UPDATEs, not INSERTs: the VOX branch rows already")
    print("-- exist, they just have source/source_code left NULL, which is")
    print("-- why fetch_branch_ids() matches none of them and every showtime")
    print("-- is skipped. This fills in the two columns it matches on.")
    print("--")
    print("-- Match is on the branch name as VOX prints it, minus the trailing")
    print("-- ' - Riyadh' — your rows are stored without it. CHECK the row")
    print("-- counts: each statement should report UPDATE 1. UPDATE 0 means")
    print("-- that branch isn't in your table under that name (add it by")
    print("-- hand); UPDATE 2+ means two rows share a name.")
    print()

    for r in rows:
        scraped = r["branch_name"]
        # VOX prints "Riyadh Park - Riyadh"; the stored rows are just
        # "Riyadh Park", so match on the part before the separator.
        stem = scraped.split(" - ")[0].strip()
        # % and _ are wildcards in LIKE, and a branch name could
        # legitimately contain either.
        escaped = stem.replace("\\", "\\\\").replace("%", r"\%").replace("_", r"\_").replace("'", "''")

        print(f"-- VOX calls this \"{scraped}\"")
        print(
            "update branches set source = '{}', source_code = '{}'\n"
            "where cinema_name = '{}' and branch_name ilike '{}%';".format(
                r["source"], r["source_code"], r["cinema_name"], escaped
            )
        )
        print()

    print("-- Verify: every VOX branch should now have a source and a code.")
    print("-- select branch_id, branch_name, source, source_code")
    print("-- from branches where cinema_name = 'VOX' order by branch_name;")


def main() -> None:
    # Read-only: scrape, print the branch rows, write nothing at all.
    # Needs no service-role key, since it never talks to Supabase.
    if "--propose-branches" in sys.argv:
        print_proposed_branches(scrape_all())
        return

    supabase_url, service_role_key = _load_env()
    if not supabase_url or not service_role_key:
        print(
            "Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.\n"
            "Create scripts/.env with those two values first — see the "
            "docstring at the top of this file for where to get the key "
            "and why it must NOT go in the app's root .env.",
            file=sys.stderr,
        )
        sys.exit(1)

    movies = scrape_all()
    sync(movies, supabase_url, service_role_key)


if __name__ == "__main__":
    main()
