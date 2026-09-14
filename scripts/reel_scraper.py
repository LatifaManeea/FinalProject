"""
Reel Cinemas (Saudi Arabia) "now showing" scraper.

What it does
------------
Reel's site (reelcinemas.com) is a Vista Entertainment "EEG" cloud
export: its own frontend gets every cinema, film and session straight
from public, unauthenticated static JSON files on Google Cloud Storage
- no API key, no cookies, nothing scraped off rendered HTML. Confirmed
by watching reelcinemas.com/en-sa/showtime's own network requests:

    https://storage.googleapis.com/eeg-prod-reelcinema-sb/web/vista/json/Cinemas.json
    https://storage.googleapis.com/eeg-prod-reelcinema-sb/web/vista/json/Films.json
    https://storage.googleapis.com/eeg-prod-reelcinema-sb/web/vista/json/Sessions.json

Each is a single OData-shaped payload - `{"odata.metadata": ..., "value":
[...]}` - covering every Reel cinema across every country Reel operates
in (UAE, Saudi, Bahrain, ...), not just Saudi. This scraper downloads
all three (they're not huge) and filters down to Saudi's one location.

One branch only
----------------
Reel has exactly one Saudi location: Granada Mall in Riyadh, cinema id
"0010" in Cinemas.json (CinemaNationalISO "sa"). That id is hardcoded
below as GRANADA_MALL_CINEMA_ID rather than derived, since there's
nothing to derive it from without also pulling in every UAE/Bahrain
cinema and filtering by country - simpler to pin the one id and let it
break loudly (an empty Films/Sessions result) if Reel ever renumbers it.

No per-film requests needed
------------------------------
Unlike VOX (HTML page scrape) and Muvi (one showtimes request per
film), Sessions.json already contains every session for every cinema
in one file. Nothing here needs a second round-trip per film - the
three JSON files above are the whole scrape.

Poster URLs: Films.json's own fields don't work
----------------------------------------------------
Every film in Films.json - including ones with dozens of showings this
week - has `GraphicUrl` and `FilmNameUrl` as empty strings. Confirmed
across multiple currently-showing titles, not just coming-soon ones, so
this isn't a "poster not uploaded yet" gap - the field just isn't
populated in this feed. The real poster comes from a predictable path
instead, found by reading the actual <img> tags reelcinemas.com renders
for its movie cards:

    https://storage.googleapis.com/eeg-prod-reelcinema-sb/web/vista/movie_images/<FilmID>.jpg

(e.g. .../movie_images/HO00005631.jpg for film id "HO00005631"). Built
from the film's own `ID` field below rather than trusted from the JSON.

Screen type / experience
--------------------------
Each session carries `SessionAttributesNames`, a mixed bag of dimension
tags ("2D"), promo codes ("PROMO-ARAB", "PROMO-ETIS", ...) and the
actual experience ("STANDARD", "PLATINUM", "DOLBY", "INFINITY V",
"ReelJunior"). `_screen_type_from_attributes()` below picks the first
recognised experience name out of that list and falls back to
"Standard" if none matches - same idea as VOX/Muvi's screen_type, just
derived from a noisier source field.

Timezone
--------
Cinemas.json lists Granada Mall's `TimeZoneId` as "Arab Standard Time"
(the Windows zone id for Saudi Arabia - UTC+3 year-round, no DST).
Sessions.json's own `Showtime` field is a naive local timestamp with no
offset ("2026-09-14T19:40:00"), so it's parsed as a plain datetime and
given +03:00 explicitly below - exactly what vox_scraper.py already
does with its own KSA_TZ constant for the same reason (VOX's HTML has
no offset either).

"Today" scope, matching VOX/Muvi
---------------------------------
Sessions.json holds roughly two and a half weeks of advance sales, not
just today - VOX and Muvi only ever surface "today" (VOX by construction,
Muvi because its API is asked for one date). This scraper filters to
Riyadh's current calendar day using each session's own
`SessionBusinessDate` (its cinema business day, which is more robust
than the raw Showtime date for a session that starts after midnight)
rather than pulling in over two weeks of future showtimes.

No bot protection expected
-----------------------------
This is a public Google Cloud Storage bucket, not Reel's own domain -
no Akamai/Cloudflare fingerprinting like VOX, nothing needing curl_cffi.
Plain `requests` is enough, same as Muvi.

Usage
-----
    pip install requests
    python3 reel_scraper.py
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Optional

import requests

JSON_BASE = "https://storage.googleapis.com/eeg-prod-reelcinema-sb/web/vista/json"
POSTER_BASE = "https://storage.googleapis.com/eeg-prod-reelcinema-sb/web/vista/movie_images"

# Reel's only Saudi location - see "One branch only" above.
GRANADA_MALL_CINEMA_ID = "0010"
GRANADA_MALL_NAME = "Granada Mall"

KSA_TZ = timezone(timedelta(hours=3))  # Arab Standard Time - UTC+3, no DST.

# The experience/format tags actually seen in SessionAttributesNames for
# Granada Mall, in priority order (first match wins) - everything else
# in that list is a dimension tag ("2D"/"3D") or a PROMO-* code, neither
# of which is a screen type. See "Screen type / experience" above.
KNOWN_EXPERIENCES = ["PLATINUM", "DOLBY", "INFINITY V", "ReelJunior", "STANDARD"]


@dataclass
class Showtime:
    branch: str
    branch_code: str  # Reel's own cinema id ("0010") - see docstring.
    screen_type: str
    show_time_iso: str
    sold_out: bool
    booking_id: str  # Sessions.json's own "ID" field (e.g. "0010-198415") - stable per showing.


@dataclass
class Movie:
    title: str
    slug: str  # Reel has no real slug; the film's own ID ("HO00005631") is used instead - see build_film_rows.
    poster_url: Optional[str]
    rating: Optional[str]
    language: Optional[str]
    genre: Optional[str] = None
    duration_minutes: Optional[int] = None
    release_date: Optional[str] = None
    detail_url: str = ""
    showtimes_today: list[Showtime] = field(default_factory=list)


def fetch_json(name: str) -> list[dict]:
    """GETs one of the three JSON files and returns its `value` array -
    every one of them is the same OData shape."""
    resp = requests.get(f"{JSON_BASE}/{name}.json", timeout=30)
    resp.raise_for_status()
    return resp.json()["value"]


def _screen_type_from_attributes(attrs: list[str]) -> str:
    attrs_upper = {a.upper() for a in attrs}
    for experience in KNOWN_EXPERIENCES:
        if experience.upper() in attrs_upper:
            return experience
    return "Standard"


def _parse_showtime(naive_iso: str) -> Optional[datetime]:
    """Sessions.json's Showtime has no timezone offset - attach KSA's
    directly, same approach as vox_scraper.py's _parse_showtime."""
    try:
        naive = datetime.fromisoformat(naive_iso)
    except ValueError:
        return None
    return naive.replace(tzinfo=KSA_TZ)


def parse_films(films_raw: list[dict]) -> dict[str, Movie]:
    """Every film that plays at Granada Mall at all (MovieDisplayed
    lists cinema "0010"), keyed by the film's own ID. Showtimes are
    filled in separately from Sessions.json."""
    movies: dict[str, Movie] = {}
    for f in films_raw:
        displayed = f.get("MovieDisplayed") or []
        if not any(d.get("CinemaId") == GRANADA_MALL_CINEMA_ID for d in displayed):
            continue
        film_id = f["ID"]
        genre_id = f.get("GenreId")
        movies[film_id] = Movie(
            title=(f.get("Title") or "").strip(),
            slug=film_id,
            poster_url=f"{POSTER_BASE}/{film_id}.jpg",
            rating=(f.get("Rating") or "").strip() or None,
            language=(f.get("Language") or "").strip() or None,
            genre=genre_id,
            duration_minutes=f.get("RunTime"),
            release_date=f.get("OpeningDate"),
            # No confirmed per-film deep link on reelcinemas.com's SPA
            # (its movie cards have no distinct URL - see the research
            # notes). Left blank rather than guessed; film.dart's
            # bookingUrl already returns null when a source has no
            # entry in _filmPageBySource, which is the honest state
            # here until a real deep link is found.
            detail_url="",
        )
    return movies


def scrape_all() -> list[Movie]:
    print("Fetching Cinemas.json, Films.json, Sessions.json ...")
    films_raw = fetch_json("Films")
    sessions_raw = fetch_json("Sessions")

    movies = parse_films(films_raw)
    print(f"Found {len(movies)} film(s) listed at {GRANADA_MALL_NAME}.")

    today = datetime.now(KSA_TZ).date()
    sessions_today = [
        s
        for s in sessions_raw
        if s.get("CinemaId") == GRANADA_MALL_CINEMA_ID
        and _business_date(s) == today
    ]
    print(f"{len(sessions_today)} session(s) today ({today.isoformat()}) at {GRANADA_MALL_NAME}.")

    skipped_no_film = 0
    for s in sessions_today:
        film_id = s.get("ScheduledFilmId")
        movie = movies.get(film_id)
        if movie is None:
            skipped_no_film += 1
            continue
        show_time = _parse_showtime(s.get("Showtime", ""))
        if show_time is None:
            continue
        movie.showtimes_today.append(
            Showtime(
                branch=GRANADA_MALL_NAME,
                branch_code=GRANADA_MALL_CINEMA_ID,
                screen_type=_screen_type_from_attributes(s.get("SessionAttributesNames") or []),
                show_time_iso=show_time.isoformat(),
                sold_out=bool(s.get("SoldoutStatus")),
                booking_id=str(s.get("ID") or s.get("SessionId")),
            )
        )
    if skipped_no_film:
        print(f"  ! {skipped_no_film} session(s) referenced a film id not in Films.json - skipped.")

    return list(movies.values())


def _business_date(session: dict) -> Optional[date]:
    raw = session.get("SessionBusinessDate")
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw).date()
    except ValueError:
        return None


def main() -> None:
    movies = scrape_all()
    out_path = "reel_movies.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump([asdict(m) for m in movies], f, ensure_ascii=False, indent=2)
    print(f"\nWrote {len(movies)} movie(s) to {out_path}")

    with_showtimes = [m for m in movies if m.showtimes_today]
    print(f"{len(with_showtimes)} of them have at least one showtime today.")

    missing_runtime = [m.title for m in movies if m.duration_minutes is None]
    if missing_runtime:
        print(f"Note: no runtime found for {len(missing_runtime)} title(s): {missing_runtime}")


if __name__ == "__main__":
    main()
