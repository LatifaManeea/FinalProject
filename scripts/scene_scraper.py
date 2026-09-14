"""
Scene Cinemas (Saudi Arabia) "now showing" scraper - Riyadh branches only.

What it does
------------
Scene's site (scenecinemas.sa) is an ASP.NET MVC site (controller/action
URLs like /Home/LoadCinemas, /MoviesList/NowShowing) that renders almost
everything through small AJAX calls returning server-rendered HTML
fragments (not a JSON API like Reel's, and not one big page like VOX/
Muvi/CineHouse - a movie's own /movies/<slug> page loads with an EMPTY
<section id="partialshowtime">...</section> placeholder and fills it in
with jQuery after three separate POSTs). This scraper calls those same
POST endpoints directly with `requests` instead of driving a browser:

  1. POST /MoviesList/NowShowing (empty body) - the current "now
     showing" tiles. Each tile's `onclick="myFunction(slug, movieId,
     'ns', ...)"` gives the slug + the movie's own GUID; poster/title/
     rating/language come from the same tile's markup.
  2. GET  /movies/<slug> - the movie's detail page. Even though the
     showtime accordion itself is empty here, the page embeds a
     `<section id="partialshowtime" data-moviename=... data-lang=...
     data-genre=... data-rtime="1 hrs  30 min " data-rating=...
     data-releasedt=...>` tag with everything needed for
     title/language/genre/runtime/rating - this is more complete than
     the listing tile, so it wins when both are present.
  3. POST /MovieDetails/getalldatebymovieid with {movieid: <guid>} -
     returns {"sourceData": [{"actualshowdate": "2026-09-16T...Z", ...},
     ...]}, one entry per bookable day. `sourceData[0]` is literally
     what the site's own JS treats as "the default selected date" (see
     "No today or tomorrow" below for why that matters here).
  4. POST /moviedetails/getsinglemoviefilter with
     {newurl: "showdate=<date>&cinemaid=<guid>&cinemaid=<guid>&filmid=<movieId>",
      date: <date>, Filmid: <movieId>} - the actual showtime HTML,
     ALREADY FILTERED SERVER-SIDE to just the cinemaid(s) passed in, so
     passing only the two Riyadh GUIDs below returns only those two
     branches' panels instead of every Scene location in the Kingdom.

None of this needs a real browser or JS execution to find the right
data - confirmed by calling all four endpoints directly with plain
`fetch()` from an already-open browser tab and getting the same
fragments the live page renders. Getting past Scene's own bot
protection on the real network still needs curl_cffi, though - see
"Why curl_cffi instead of plain requests" below.

Riyadh branches only
---------------------
Scene has six Saudi locations in total (Abha, Ajdan Walk/Khobar, Tabuk,
Stars Avenue, and the two Riyadh ones below) - like VOX/Muvi, this only
tracks the branches already in your `branches` table, so it's scoped to
Riyadh via the two cinema GUIDs from /Home/LoadCinemas. RIYADH_BRANCHES
maps each GUID to the branch_name already sitting in your table for that
mall (the SITE calls these "Scene Panorama" / "Scene Riyadh Gallery" in
its own markup - a cosmetic difference, the GUID is what's actually
matched, both here and in sync_scene_to_supabase.py).

No "today" or "tomorrow" - this scrapes the EARLIEST bookable date instead
---------------------------------------------------------------------------
Unlike VOX/Muvi/Reel/CineHouse, Scene's own date picker never offers
today or tomorrow at all - checked live on 2026-09-14 (a Monday), and
every movie's date list started at "Wed, 16 Sep", i.e. two days out. A
literal "showtimes today" scrape would therefore always return zero
sessions for this chain - not a bug, just how far out Scene opens
booking. So this scrapes each movie's EARLIEST available date instead
(sourceData[0] from getalldatebymovieid - literally the date the site's
own page selects by default when you load it with no history), and
still calls the result `showtimes_today`/`Showtime.show_time_iso` to
keep the same shape every other chain's scraper and every sync script
already expects. In practice this means: the first sync will show
showtimes ~2 days out, and each day that date rolls forward as Scene
opens its next day of booking - flagged here since it's the one real
behavioral difference from the other four chains, worth knowing about
before relying on "today" language anywhere in the app for Scene rows.

Booking id
----------
Each showing's time link fires `onclick="LatestShowRulesEntry(sessionId,
rating, slug, movieId, experienceId, cinemaId, this)"` - the first
argument (a GUID) is the specific session, stable and unique - used
below as source_booking_id, the same role every other chain's own
session/showing id plays.

Screen type
-----------
Each branch panel can list more than one experience block
(`.individual-genre`), e.g. "Standard" and "Dolby" - screen_type comes
from that block's `.amc-exp-title` text, one Showtime per time slot per
experience, mirroring vox_scraper.py's nested branch/experience/time
loop.

Sold out
--------
No sold-out flag was found anywhere in the showtime fragment (checked
via a live response with no "sold"/"disabled" markers) - sold_out is
hardcoded False below, same situation as cinehouse_scraper.py.

Booking link
------------
/movies/<slug> is a real, stable, working per-movie deep link (no date
baked in - the page picks a default date itself) - used as detail_url
below and wired into film.dart's booking-link map.

Why curl_cffi instead of plain requests
----------------------------------------
Same root cause as vox_scraper.py, confirmed the same way: a bare
`requests` GET of the plain /movies page (no AJAX involved at all) came
back 403 on the real network, even with a real browser User-Agent and a
full set of Accept/Origin/Referer/Sec-Fetch-* headers added - so this
was never a missing-header or CSRF-token problem. The same page loaded
fine from an actual browser. That pattern - browser fine, `requests`
403 no matter what headers are added - is exactly what VOX's Akamai
protection does: it fingerprints the TLS handshake itself, not the
headers, and Python's built-in ssl/urllib3 handshake looks distinctly
non-browser. curl_cffi wraps curl-impersonate to reproduce a real
Chrome TLS fingerprint, so it gets through the same way a real browser
or plain curl(1) does - used here as a drop-in replacement for
`requests` (same .get/.post/.text/.raise_for_status API), with
impersonate="chrome124" on every call. Origin/Referer/Sec-Fetch-* are
still sent on the AJAX calls below since a real browser would send them
too, but they were not what was blocking things.

robots.txt
----------
Disallows /myaccount, /seats, /payment, /SetGEO, /WatchList,
/MovieDetails (the human-facing path, not the /MoviesList,
/moviedetails (lowercase) or /movies paths this scrapes) - nothing here
touches a disallowed path.

Timezone
--------
Same Saudi Arabia UTC+3, no DST, as every other chain here.

Usage
-----
    pip install curl_cffi beautifulsoup4
    python3 scene_scraper.py
"""

from __future__ import annotations

import json
import re
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Optional

from curl_cffi import requests
from bs4 import BeautifulSoup

# Real Chrome TLS fingerprint for every call below - see "Why curl_cffi
# instead of plain requests" in the module docstring.
IMPERSONATE = "chrome124"

BASE = "https://www.scenecinemas.sa"

# The two Riyadh branches this scrapes - GUID (the site's own cinema id,
# from /Home/LoadCinemas) -> the branch_name already in your `branches`
# table for that mall. See "Riyadh branches only" above.
RIYADH_BRANCHES: dict[str, str] = {
    "62c87307-8676-4ee2-8251-aaf3012b37ba": "Panorama Mall",
    "668cd400-cd80-4454-aded-efa778ccb8c2": "Riyadh Gallery Mall",
}

KSA_TZ = timezone(timedelta(hours=3))  # Arabia Standard Time - UTC+3, no DST.

_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)
_COMMON_HEADERS = {"User-Agent": _UA, "Accept-Language": "en-US,en;q=0.9,ar;q=0.8"}
PAGE_HEADERS = {
    **_COMMON_HEADERS,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}


def _ajax_headers(referer: str) -> dict:
    """A plain UA + X-Requested-With got a 403 on the real (non-sandboxed)
    network - ASP.NET sites commonly gate AJAX endpoints on Origin/Referer
    matching the site itself (a cheap CSRF check, not full bot-detection),
    so every AJAX call now sends a same-origin Origin/Referer pair plus
    the Sec-Fetch-* triplet a real jQuery XHR would carry."""
    return {
        **_COMMON_HEADERS,
        "Accept": "*/*",
        "X-Requested-With": "XMLHttpRequest",
        "Origin": BASE,
        "Referer": referer,
        "Sec-Fetch-Site": "same-origin",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Dest": "empty",
    }

# Be polite: pause between each movie's set of detail/date/showtime
# requests, same idea as muvi_scraper.py's REQUEST_DELAY_SECONDS.
REQUEST_DELAY_SECONDS = 0.6

# "1 hrs  30 min " -> (1, 30); the hours group is optional in case a
# short film's data-rtime ever omits it.
_DURATION_RE = re.compile(r"(?:(\d+)\s*hrs?)?\s*(\d+)\s*min", re.IGNORECASE)

# "myFunction('resident-evil','ec3e2cb7-...','ns', ...)" -> (slug, movie_id).
_MYFUNCTION_RE = re.compile(r"myFunction\('([^']+)','([^']+)','ns'")

# "LatestShowRulesEntry('186de082-...','R18','resident-evil',...)" -> session id.
_SESSION_ID_RE = re.compile(r"LatestShowRulesEntry\('([^']+)'")


@dataclass
class Showtime:
    branch: str
    branch_code: str
    screen_type: str
    show_time_iso: str
    sold_out: bool
    booking_id: str


@dataclass
class Movie:
    title: str
    slug: str
    poster_url: Optional[str]
    rating: Optional[str]
    language: Optional[str]
    genre: Optional[str] = None
    duration_minutes: Optional[int] = None
    release_date: Optional[str] = None
    detail_url: str = ""
    # Despite the name (kept for the same shape every other chain's
    # scraper/sync script expects), this holds each movie's EARLIEST
    # bookable date's showtimes, not literally today's - see "No today
    # or tomorrow" in the module docstring.
    showtimes_today: list[Showtime] = field(default_factory=list)


def _post(session: requests.Session, path: str, data: dict, referer: str) -> requests.Response:
    resp = session.post(
        f"{BASE}{path}", data=data, headers=_ajax_headers(referer), timeout=20, impersonate=IMPERSONATE
    )
    if resp.status_code >= 400:
        print(f"    ! POST {path} -> HTTP {resp.status_code}: {resp.text[:200]!r}")
    resp.raise_for_status()
    return resp


def _parse_duration_minutes(rtime_text: Optional[str]) -> Optional[int]:
    if not rtime_text:
        return None
    match = _DURATION_RE.search(rtime_text)
    if not match:
        return None
    hours = int(match.group(1)) if match.group(1) else 0
    minutes = int(match.group(2))
    return hours * 60 + minutes


def fetch_now_showing(session: requests.Session) -> list[dict]:
    """The "now showing" tiles - enumerates every movie's slug + its own
    GUID, plus a first-pass title/poster/rating/language (the detail
    page's data-attributes, fetched per movie below, are more complete
    and win when both are present)."""
    resp = _post(session, "/MoviesList/NowShowing", data={}, referer=f"{BASE}/movies")
    soup = BeautifulSoup(resp.text, "html.parser")
    movies: dict[str, dict] = {}  # keyed by slug, de-dupes a title shown in more than one carousel

    for block in soup.select("section.set-width"):
        match = _MYFUNCTION_RE.search(block.get("onclick", ""))
        if not match:
            continue
        slug, movie_id = match.group(1), match.group(2)
        if slug in movies:
            continue

        img = block.select_one(".img-blk img")
        title_el = block.select_one(".movie-ttl")
        tym_el = block.select_one(".tym")
        language = rating = None
        if tym_el is not None:
            parts = [p.strip() for p in tym_el.get_text(" ", strip=True).split("|")]
            language = parts[0] or None if parts else None
            rating = parts[1] or None if len(parts) > 1 else None

        movies[slug] = {
            "slug": slug,
            "movie_id": movie_id,
            "title": title_el.get_text(strip=True) if title_el else slug,
            "poster_url": img.get("src") if img else None,
            "rating": rating,
            "language": language,
        }

    return list(movies.values())


def fetch_movie_metadata(session: requests.Session, slug: str) -> Optional[dict]:
    """The movie's own /movies/<slug> page - the empty #partialshowtime
    tag's data-attributes are the richest single source for title/
    language/genre/runtime/rating/release date (see docstring)."""
    resp = session.get(
        f"{BASE}/movies/{slug}",
        headers={**PAGE_HEADERS, "Referer": f"{BASE}/movies"},
        timeout=20,
        impersonate=IMPERSONATE,
    )
    if resp.status_code >= 400:
        print(f"    ! GET /movies/{slug} -> HTTP {resp.status_code}: {resp.text[:200]!r}")
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    section = soup.find(id="partialshowtime")
    if section is None:
        return None
    return {
        "title": section.get("data-moviename") or None,
        "language": section.get("data-lang") or None,
        "rating": section.get("data-rating") or None,
        "genre": section.get("data-genre") or None,
        "duration_minutes": _parse_duration_minutes(section.get("data-rtime")),
        "release_date": section.get("data-releasedt") or None,
    }


def fetch_earliest_date(session: requests.Session, movie_id: str, slug: str) -> Optional[str]:
    """sourceData[0].actualshowdate from getalldatebymovieid - literally
    the date the site's own JS treats as the default selection (see "No
    today or tomorrow" in the module docstring). Returns "YYYY-MM-DD",
    or None if the movie has no bookable date at all yet."""
    resp = _post(
        session,
        "/MovieDetails/getalldatebymovieid",
        data={"movieid": movie_id},
        referer=f"{BASE}/movies/{slug}",
    )
    try:
        payload = resp.json()
    except ValueError:
        return None
    source_data = payload.get("sourceData") or []
    if not source_data:
        return None
    actual = source_data[0].get("actualshowdate")
    return actual[:10] if actual else None  # "2026-09-16T00:00:00.000Z" -> "2026-09-16"


def fetch_showtimes(session: requests.Session, movie_id: str, date_str: str, slug: str) -> list[Showtime]:
    """getsinglemoviefilter, asking only for the two Riyadh cinemaids -
    the server filters to just those branches' panels (confirmed live:
    passing 2 cinemaids returns exactly 2 panels, not all 6+)."""
    newurl = f"showdate={date_str}"
    for guid in RIYADH_BRANCHES:
        newurl += f"&cinemaid={guid}"
    newurl += f"&filmid={movie_id}"

    resp = _post(
        session,
        "/moviedetails/getsinglemoviefilter",
        data={"newurl": newurl, "date": date_str, "Filmid": movie_id},
        referer=f"{BASE}/movies/{slug}",
    )
    soup = BeautifulSoup(resp.text, "html.parser")

    showtimes: list[Showtime] = []
    for panel in soup.select("section.panel.panel-default"):
        controls_link = panel.select_one("h2.panel-title a[aria-controls]")
        branch_guid = controls_link.get("aria-controls") if controls_link else None
        branch_name = RIYADH_BRANCHES.get(branch_guid or "")
        if branch_name is None:
            continue  # not one of ours - shouldn't happen, we already filtered server-side.

        for genre_block in panel.select("section.individual-genre"):
            exp_title_el = genre_block.select_one(".amc-exp-title")
            screen_type = exp_title_el.get_text(strip=True) if exp_title_el else "Standard"

            for link in genre_block.select("ul.amc-time-list li a[onclick^='LatestShowRulesEntry']"):
                match = _SESSION_ID_RE.search(link.get("onclick", ""))
                time_el = link.select_one(".amc-time")
                if match is None or time_el is None:
                    continue
                time_text = time_el.get_text(strip=True)
                try:
                    naive = datetime.strptime(f"{date_str} {time_text}", "%Y-%m-%d %I:%M %p")
                except ValueError:
                    continue
                if naive.hour < 6:
                    # An after-midnight show (e.g. "01:00 AM") still
                    # belongs to date_str's operating day, same rolling
                    # convention as vox_scraper.py's _parse_showtime.
                    naive += timedelta(days=1)
                showtimes.append(
                    Showtime(
                        branch=branch_name,
                        branch_code=branch_guid,
                        screen_type=screen_type,
                        show_time_iso=naive.replace(tzinfo=KSA_TZ).isoformat(),
                        sold_out=False,  # not exposed anywhere found on this page - see docstring.
                        booking_id=match.group(1),
                    )
                )
    return showtimes


def scrape_all() -> list[Movie]:
    session = requests.Session()
    # Throwaway request purely to pick up any Set-Cookie headers, and to
    # give the very first AJAX call a real page to point its Referer at -
    # see "Why curl_cffi instead of plain requests" in the docstring.
    warmup = session.get(f"{BASE}/movies", headers=PAGE_HEADERS, timeout=20, impersonate=IMPERSONATE)
    if warmup.status_code >= 400:
        print(f"  ! warm-up GET /movies -> HTTP {warmup.status_code} (continuing anyway)")

    print(f"Fetching {BASE}/MoviesList/NowShowing for the current movie list...")
    listed = fetch_now_showing(session)
    print(f"Found {len(listed)} movie(s) listed.")

    movies: list[Movie] = []
    for i, entry in enumerate(listed, start=1):
        slug, movie_id = entry["slug"], entry["movie_id"]
        print(f"  [{i}/{len(listed)}] {entry['title']} -> /movies/{slug}")

        meta = fetch_movie_metadata(session, slug) or {}
        date_str = fetch_earliest_date(session, movie_id, slug)
        showtimes = fetch_showtimes(session, movie_id, date_str, slug) if date_str else []

        movies.append(
            Movie(
                title=meta.get("title") or entry["title"],
                slug=slug,
                poster_url=entry.get("poster_url"),
                rating=meta.get("rating") or entry.get("rating"),
                language=meta.get("language") or entry.get("language"),
                genre=meta.get("genre"),
                duration_minutes=meta.get("duration_minutes"),
                release_date=meta.get("release_date"),
                detail_url=f"{BASE}/movies/{slug}",
                showtimes_today=showtimes,
            )
        )
        time.sleep(REQUEST_DELAY_SECONDS)

    with_showtimes = sum(1 for m in movies if m.showtimes_today)
    dates_seen = sorted({st.show_time_iso[:10] for m in movies for st in m.showtimes_today})
    print(
        f"{with_showtimes} of {len(movies)} movie(s) have a Riyadh showtime "
        f"on their earliest bookable date ({', '.join(dates_seen) if dates_seen else 'none found'})."
    )
    return movies


def main() -> None:
    movies = scrape_all()
    out_path = "scene_movies.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump([asdict(m) for m in movies], f, ensure_ascii=False, indent=2)
    print(f"\nWrote {len(movies)} movie(s) to {out_path}")

    missing_runtime = [m.title for m in movies if m.duration_minutes is None]
    if missing_runtime:
        print(f"Note: no runtime found for {len(missing_runtime)} title(s): {missing_runtime}")


if __name__ == "__main__":
    main()
