"""
CineHouse (Saudi Arabia) "now showing" scraper.

What it does
------------
CineHouse's site (cinehousecinema.com) is a completely different stack
from VOX/Muvi/Reel - it's an Odoo 17 website (confirmed via its own
`odoo.__session_info__` bootstrap script and `/web/assets/...` /
`/website/translations` URLs), running what looks like a third-party
Odoo cinema-booking add-on (`sh.movie.model` records, `/event/.../movie/
seat/booking` booking links - "sh" is a common vendor prefix for these
Odoo apps). Nothing here is a public JSON API like Reel's - this scrapes
plain server-rendered HTML with BeautifulSoup, same approach as
vox_scraper.py.

One branch only
----------------
CineHouse has exactly one Saudi location - the site's own branch
dropdown (`<select name="branch_id">`) lists a single option, value
"3", labelled "Riyadh". That's Ar Rabi mall, per branches - hardcoded
below as BRANCH_CODE/BRANCH_NAME the same way reel_scraper.py hardcodes
Granada Mall, for the same reason (nothing to derive it from without
also pulling in whatever other countries this Odoo instance might serve).

The /show LISTING page is broken - use the homepage instead
----------------------------------------------------------------
CineHouse's own "browse everything" page (`/show?booking_date=...&
branch_id=3`) is a dead end - it returns an empty result for every date
tried (today, days out, no date at all), even though real bookable
sessions clearly exist (see below). The site's actual homepage
(https://cinehousecinema.com/) renders a working "Now Showing" /
"Coming Soon" list of movie tiles server-side instead, each linking to
that movie's own detail page (`/show/<slug>`) - this scraper enumerates
movies from the homepage rather than the broken listing page.

Per-movie detail pages: one showtime a day, picked via ?filter_date=
--------------------------------------------------------------------------
Each movie's own page (`/show/<slug>`) shows a row of the next several
days as date tabs. Some of the nearest days can be greyed out
(`md_date_disabled` - no bookable session that day, seemingly a
same-day/near-term booking cutoff rather than a scraping problem: this
showed up for today and the next two days during development, with
sessions resuming from a few days out). Clicking a date tab reloads the
page with `?filter_date=YYYY-MM-DD` and, if a session exists that day,
shows exactly one showtime for it (a time like "11:00 PM" inside a
`.sh_movie_show_timing` block) - confirmed to be genuinely one session
per movie per day, not a scraping artifact. `robots.txt` here has no
`Disallow` rules at all (unlike VOX's, which blocks query strings), so
requesting `?filter_date=...` is fine.

If today happens to be one of the disabled dates, a movie simply has no
`.sh_movie_show_timing` block and this scraper records zero showtimes
for it today - the same "nothing today" outcome as any other chain with
nothing scheduled, not an error.

Booking id
----------
Each showing's booking link looks like
`/event/resident-evil-11-00-pm-12393/movie/seat/booking?filter_date=...`
- Odoo's Events module underneath this booking add-on, apparently. The
trailing number (12393) is a real, stable per-showing id - used below
as source_booking_id, the same role VOX/Muvi/Reel's own session ids play.

Poster URL
----------
The homepage embeds movie posters as inline base64 data: URIs (no
usable URL). Each movie's own detail page instead has a real,
Odoo-served image URL (`/web/image/sh.movie.model/<id>/...`) - used
here instead, the same "don't trust the field that doesn't work, use
the one that does" situation as reel_scraper.py's GraphicUrl vs.
movie_images path.

Booking link
------------
Unlike Reel, CineHouse's `/show/<slug>` page IS a real, working,
stable per-movie deep link (no date/time baked in) - used as detail_url
below, and wired into film.dart's booking-link map.

Screen type / venue
--------------------
Every showing's page shows the same fixed marketing blurb ("Luxury
experience - Exclusive lounge - Special menu.") rather than a real
screen-type/experience tag the way VOX/Muvi/Reel have one - CineHouse
is a single small boutique cinema with (as far as this scrape found)
one experience tier. screen_type is hardcoded to "Standard" below;
worth revisiting if CineHouse ever adds a second screen/experience.

Timezone
--------
Same Saudi Arabia UTC+3, no DST, as every other chain here - the
scraped time text ("11:00 PM") is a plain local time with no timezone
info of its own, so KSA_TZ is attached directly, same approach as
vox_scraper.py and reel_scraper.py.

No bot protection expected
-----------------------------
This is a small business's own Odoo site - no Akamai/Cloudflare
fingerprinting seen (unlike VOX). Plain `requests` is used, same as
Muvi and Reel. Flagging as an assumption to double check on first run,
the same way muvi_scraper.py flags its own.

Usage
-----
    pip install requests beautifulsoup4
    python3 cinehouse_scraper.py
"""

from __future__ import annotations

import json
import re
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Optional

import requests
from bs4 import BeautifulSoup

BASE = "https://www.cinehousecinema.com"

# CineHouse's only Saudi location - see "One branch only" above.
BRANCH_CODE = "3"
BRANCH_NAME = "Ar Rabi"

KSA_TZ = timezone(timedelta(hours=3))  # Arabia Standard Time - UTC+3, no DST.

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
}

# Be polite: pause between each movie's detail-page request, same idea
# as muvi_scraper.py's REQUEST_DELAY_SECONDS.
REQUEST_DELAY_SECONDS = 0.6

# The event-id pattern in a showing's booking link, e.g.
# "/event/resident-evil-11-00-pm-12393/movie/seat/booking?..." -> "12393".
_EVENT_ID_RE = re.compile(r"-(\d+)/movie/seat/booking")


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
    showtimes_today: list[Showtime] = field(default_factory=list)


def fetch_html(url: str) -> BeautifulSoup:
    resp = requests.get(url, headers=HEADERS, timeout=20)
    resp.raise_for_status()
    return BeautifulSoup(resp.text, "html.parser")


def _slug_from_href(href: str) -> Optional[str]:
    """'/show/resident-evil-296' -> 'resident-evil-296'. None for
    anything that isn't a movie detail link."""
    if not href or not href.startswith("/show/"):
        return None
    slug = href[len("/show/"):].strip("/")
    return slug or None


def fetch_homepage_movies() -> list[dict]:
    """CineHouse's real `/show` listing is broken (see docstring) - the
    homepage's "Now Showing" / "Coming Soon" tiles are what actually
    works, so this is where every movie (and its detail-page slug) is
    enumerated from."""
    soup = fetch_html(f"{BASE}/")
    movies: dict[str, dict] = {}  # keyed by slug, de-dupes if a title repeats

    for section_class in ("now_showing_movies", "upcoming_movies"):
        section = soup.find(class_=section_class)
        if section is None:
            continue
        for link in section.select("a.a_cover_size[href^='/show/']"):
            slug = _slug_from_href(link.get("href", ""))
            if slug is None or slug in movies:
                continue
            card = link.parent
            title_el = card.find("h2") if card else None
            rating_el = link.select_one(".age_tag span")
            movies[slug] = {
                "slug": slug,
                "title": title_el.get_text(strip=True) if title_el else slug,
                "rating": rating_el.get_text(strip=True) if rating_el else None,
            }

    return list(movies.values())


def _parse_duration_minutes(soup: BeautifulSoup) -> Optional[int]:
    el = soup.select_one(".sh_calender span.fs_30")
    if el is None:
        return None
    match = re.search(r"\d+", el.get_text())
    return int(match.group()) if match else None


def _parse_genre(soup: BeautifulSoup) -> Optional[str]:
    spans = soup.select(".sh_show_type .fs_14")
    genres = [s.get_text(strip=True) for s in spans if s.get_text(strip=True)]
    return " / ".join(genres) if genres else None


def _parse_poster_url(soup: BeautifulSoup) -> Optional[str]:
    img = soup.select_one("img[src*='/web/image/sh.movie.model/']")
    if img is None:
        return None
    src = img.get("src", "")
    return f"{BASE}{src}" if src.startswith("/") else src or None


def _parse_rating(soup: BeautifulSoup) -> Optional[str]:
    """Only present on a date that actually has a session (it's the
    age-restriction hidden field next to that session's booking
    button) - homepage rating is used as the primary source, this is
    just a same-day double-check when available."""
    el = soup.find("input", id="message_name")
    return el.get("value") if el else None


def _parse_showtimes_for_date(soup: BeautifulSoup, date_str: str) -> list[Showtime]:
    showtimes: list[Showtime] = []
    for block in soup.select(".sh_movie_show_timing .ribbon-container"):
        time_text = block.get_text(strip=True)
        href = block.get("data-href", "")
        match = _EVENT_ID_RE.search(href)
        if not time_text or not match:
            continue
        try:
            naive = datetime.strptime(f"{date_str} {time_text}", "%Y-%m-%d %I:%M %p")
        except ValueError:
            continue
        showtimes.append(
            Showtime(
                branch=BRANCH_NAME,
                branch_code=BRANCH_CODE,
                screen_type="Standard",  # see "Screen type / venue" in the docstring.
                show_time_iso=naive.replace(tzinfo=KSA_TZ).isoformat(),
                sold_out=False,  # not exposed anywhere found on this page.
                booking_id=match.group(1),
            )
        )
    return showtimes


def fetch_movie_detail(slug: str, date_str: str, fallback_rating: Optional[str]) -> Optional[Movie]:
    try:
        soup = fetch_html(f"{BASE}/show/{slug}?filter_date={date_str}")
    except requests.RequestException as exc:
        print(f"    ! failed to fetch /show/{slug}: {exc}")
        return None

    title_el = soup.select_one("h1.md_movie_name")
    if title_el is None:
        # Not a real movie page (site returned something unexpected) - skip.
        return None

    lang_el = soup.select_one(".sh_language span.fs_30")

    return Movie(
        title=title_el.get_text(strip=True),
        slug=slug,
        poster_url=_parse_poster_url(soup),
        rating=_parse_rating(soup) or fallback_rating,
        language=lang_el.get_text(strip=True) if lang_el else None,
        genre=_parse_genre(soup),
        duration_minutes=_parse_duration_minutes(soup),
        detail_url=f"{BASE}/show/{slug}",
        showtimes_today=_parse_showtimes_for_date(soup, date_str),
    )


def scrape_all() -> list[Movie]:
    print(f"Fetching {BASE}/ for the current movie list...")
    listed = fetch_homepage_movies()
    print(f"Found {len(listed)} movie(s) listed.")

    today = datetime.now(KSA_TZ).date().isoformat()
    movies: list[Movie] = []
    for i, entry in enumerate(listed, start=1):
        print(f"  [{i}/{len(listed)}] {entry['title']} -> /show/{entry['slug']}")
        movie = fetch_movie_detail(entry["slug"], today, entry.get("rating"))
        if movie is not None:
            movies.append(movie)
        time.sleep(REQUEST_DELAY_SECONDS)

    with_showtimes = sum(1 for m in movies if m.showtimes_today)
    print(f"{with_showtimes} of {len(movies)} movie(s) have a showtime today ({today}).")
    return movies


def main() -> None:
    movies = scrape_all()
    out_path = "cinehouse_movies.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump([asdict(m) for m in movies], f, ensure_ascii=False, indent=2)
    print(f"\nWrote {len(movies)} movie(s) to {out_path}")

    missing_runtime = [m.title for m in movies if m.duration_minutes is None]
    if missing_runtime:
        print(f"Note: no runtime found for {len(missing_runtime)} title(s): {missing_runtime}")


if __name__ == "__main__":
    main()
